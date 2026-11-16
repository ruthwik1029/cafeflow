-- ============================================================================
-- CafeFlow Phase 03 Migration 02: Multi-Tenant Row Level Security & RBAC
-- Version: 20261114000002
-- Scope: RLS enabled on all 20 tables, secure helper functions, 5 roles + public
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Enable RLS on all 20 tables
-- ----------------------------------------------------------------------------
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurant_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurant_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_item_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_item_addons ENABLE ROW LEVEL SECURITY;
ALTER TABLE dining_tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE table_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 2. Secure Security Definer Helper Functions
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auth_uid()
RETURNS UUID AS $$
    SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::UUID;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION public.has_role(target_restaurant_id UUID, allowed_roles app_role[])
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql STABLE AS $$
DECLARE
    current_uid UUID;
    has_match BOOLEAN;
BEGIN
    current_uid := auth.uid();
    IF current_uid IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM restaurant_memberships
        WHERE restaurant_id = target_restaurant_id
          AND user_id = current_uid
          AND role = ANY(allowed_roles)
          AND is_active = true
          AND deleted_at IS NULL
    ) INTO has_match;

    RETURN has_match;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_restaurant_member(target_restaurant_id UUID)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql STABLE AS $$
DECLARE
    current_uid UUID;
    is_member BOOLEAN;
BEGIN
    current_uid := auth.uid();
    IF current_uid IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM restaurant_memberships
        WHERE restaurant_id = target_restaurant_id
          AND user_id = current_uid
          AND is_active = true
          AND deleted_at IS NULL
    ) INTO is_member;

    RETURN is_member;
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. Public Website Read Policies (Strict read-only for active catalog & cafe)
-- ----------------------------------------------------------------------------

-- Restaurants: Public can view active cafes; Members can view their cafe
CREATE POLICY "Public can view active restaurants"
    ON restaurants FOR SELECT
    USING (is_active = true AND deleted_at IS NULL);

CREATE POLICY "Members can view their restaurant"
    ON restaurants FOR SELECT
    TO authenticated
    USING (is_restaurant_member(id));

CREATE POLICY "Owners can update restaurant"
    ON restaurants FOR UPDATE
    TO authenticated
    USING (has_role(id, ARRAY['OWNER'::app_role]));

-- Menu Categories: Public can view active categories
CREATE POLICY "Public can view active menu categories"
    ON menu_categories FOR SELECT
    USING (is_active = true AND deleted_at IS NULL);

CREATE POLICY "Members can view all menu categories"
    ON menu_categories FOR SELECT
    TO authenticated
    USING (is_restaurant_member(restaurant_id));

CREATE POLICY "Admins can manage menu categories"
    ON menu_categories FOR ALL
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role]));

-- Menu Items: Public can view active, non-archived items
CREATE POLICY "Public can view active menu items"
    ON menu_items FOR SELECT
    USING (is_available = true AND is_archived = false AND deleted_at IS NULL);

CREATE POLICY "Members can view all menu items"
    ON menu_items FOR SELECT
    TO authenticated
    USING (is_restaurant_member(restaurant_id));

CREATE POLICY "Admins can manage menu items"
    ON menu_items FOR ALL
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role]));

-- Menu Item Variants & Addons: Public read for available items
CREATE POLICY "Public can view available variants"
    ON menu_item_variants FOR SELECT
    USING (is_available = true AND deleted_at IS NULL);

CREATE POLICY "Members can view all variants"
    ON menu_item_variants FOR SELECT
    TO authenticated
    USING (EXISTS (
        SELECT 1 FROM menu_items
        WHERE menu_items.id = menu_item_variants.menu_item_id
          AND is_restaurant_member(menu_items.restaurant_id)
    ));

CREATE POLICY "Admins can manage variants"
    ON menu_item_variants FOR ALL
    TO authenticated
    USING (EXISTS (
        SELECT 1 FROM menu_items
        WHERE menu_items.id = menu_item_variants.menu_item_id
          AND has_role(menu_items.restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role])
    ));

CREATE POLICY "Public can view available addons"
    ON menu_item_addons FOR SELECT
    USING (is_available = true AND deleted_at IS NULL);

CREATE POLICY "Members can view all addons"
    ON menu_item_addons FOR SELECT
    TO authenticated
    USING (EXISTS (
        SELECT 1 FROM menu_items
        WHERE menu_items.id = menu_item_addons.menu_item_id
          AND is_restaurant_member(menu_items.restaurant_id)
    ));

CREATE POLICY "Admins can manage addons"
    ON menu_item_addons FOR ALL
    TO authenticated
    USING (EXISTS (
        SELECT 1 FROM menu_items
        WHERE menu_items.id = menu_item_addons.menu_item_id
          AND has_role(menu_items.restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role])
    ));

-- ----------------------------------------------------------------------------
-- 4. User Profiles & Memberships (RBAC & Identity Isolation)
-- ----------------------------------------------------------------------------
CREATE POLICY "Users can view own profile"
    ON user_profiles FOR SELECT
    TO authenticated
    USING (id = auth.uid());

CREATE POLICY "Members can view colleagues"
    ON user_profiles FOR SELECT
    TO authenticated
    USING (EXISTS (
        SELECT 1 FROM restaurant_memberships m1
        JOIN restaurant_memberships m2 ON m1.restaurant_id = m2.restaurant_id
        WHERE m1.user_id = auth.uid() AND m2.user_id = user_profiles.id
    ));

CREATE POLICY "Users can update own basic profile"
    ON user_profiles FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

CREATE POLICY "Members can view memberships of their restaurant"
    ON restaurant_memberships FOR SELECT
    TO authenticated
    USING (is_restaurant_member(restaurant_id));

CREATE POLICY "Admins can manage memberships"
    ON restaurant_memberships FOR ALL
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role]));

-- ----------------------------------------------------------------------------
-- 5. Restaurant Settings
-- ----------------------------------------------------------------------------
CREATE POLICY "Members can view settings"
    ON restaurant_settings FOR SELECT
    TO authenticated
    USING (is_restaurant_member(restaurant_id));

CREATE POLICY "Admins can update settings"
    ON restaurant_settings FOR ALL
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role]));

-- ----------------------------------------------------------------------------
-- 6. Dining Tables & Table Sessions
-- ----------------------------------------------------------------------------
CREATE POLICY "Members can view tables"
    ON dining_tables FOR SELECT
    TO authenticated
    USING (is_restaurant_member(restaurant_id));

CREATE POLICY "Staff and Admins can update table state"
    ON dining_tables FOR ALL
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role]));

CREATE POLICY "Members can view and manage table sessions"
    ON table_sessions FOR ALL
    TO authenticated
    USING (EXISTS (
        SELECT 1 FROM dining_tables
        WHERE dining_tables.id = table_sessions.table_id
          AND has_role(dining_tables.restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role])
    ));

-- ----------------------------------------------------------------------------
-- 7. Customers (Strict privacy: Cashier, Admin, Owner only)
-- ----------------------------------------------------------------------------
CREATE POLICY "Cashier and Admins can view customers"
    ON customers FOR SELECT
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role]));

CREATE POLICY "Cashier and Admins can manage customers"
    ON customers FOR ALL
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role]));

-- ----------------------------------------------------------------------------
-- 8. Orders & Order Items (Strict isolation: Staff, Cashier, Kitchen, Admin, Owner)
-- ----------------------------------------------------------------------------
CREATE POLICY "Members can view restaurant orders"
    ON orders FOR SELECT
    TO authenticated
    USING (is_restaurant_member(restaurant_id));

CREATE POLICY "Staff and Cashier can create orders"
    ON orders FOR INSERT
    TO authenticated
    WITH CHECK (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role]));

CREATE POLICY "Kitchen and Cashier can update order status"
    ON orders FOR UPDATE
    TO authenticated
    USING (is_restaurant_member(restaurant_id))
    WITH CHECK (is_restaurant_member(restaurant_id));

CREATE POLICY "Order items viewable by restaurant members"
    ON order_items FOR SELECT
    TO authenticated
    USING (EXISTS (
        SELECT 1 FROM orders
        WHERE orders.id = order_items.order_id
          AND is_restaurant_member(orders.restaurant_id)
    ));

CREATE POLICY "Order items insertable by ordering roles"
    ON order_items FOR INSERT
    TO authenticated
    WITH CHECK (EXISTS (
        SELECT 1 FROM orders
        WHERE orders.id = order_items.order_id
          AND has_role(orders.restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role])
    ));

CREATE POLICY "Order status history viewable by members"
    ON order_status_history FOR SELECT
    TO authenticated
    USING (EXISTS (
        SELECT 1 FROM orders
        WHERE orders.id = order_status_history.order_id
          AND is_restaurant_member(orders.restaurant_id)
    ));

CREATE POLICY "Order status history insertable by members"
    ON order_status_history FOR INSERT
    TO authenticated
    WITH CHECK (EXISTS (
        SELECT 1 FROM orders
        WHERE orders.id = order_status_history.order_id
          AND is_restaurant_member(orders.restaurant_id)
    ));

-- ----------------------------------------------------------------------------
-- 9. Payments & Payment Methods (Cashier, Admin, Owner only)
-- ----------------------------------------------------------------------------
CREATE POLICY "Cashiers and Admins can view payment methods"
    ON payment_methods FOR SELECT
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role]));

CREATE POLICY "Admins can manage payment methods"
    ON payment_methods FOR ALL
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role]));

CREATE POLICY "Cashiers and Admins can view payments"
    ON payments FOR SELECT
    TO authenticated
    USING (EXISTS (
        SELECT 1 FROM orders
        WHERE orders.id = payments.order_id
          AND has_role(orders.restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role])
    ));

CREATE POLICY "Cashiers can record payments"
    ON payments FOR INSERT
    TO authenticated
    WITH CHECK (EXISTS (
        SELECT 1 FROM orders
        WHERE orders.id = payments.order_id
          AND has_role(orders.restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role])
    ));

-- ----------------------------------------------------------------------------
-- 10. Inventory & Stock Movements (Kitchen, Admin, Owner only)
-- ----------------------------------------------------------------------------
CREATE POLICY "Kitchen and Admins can view inventory categories"
    ON inventory_categories FOR SELECT
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'KITCHEN'::app_role]));

CREATE POLICY "Admins can manage inventory categories"
    ON inventory_categories FOR ALL
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role]));

CREATE POLICY "Kitchen and Admins can view inventory items"
    ON inventory_items FOR SELECT
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'KITCHEN'::app_role]));

CREATE POLICY "Kitchen and Admins can manage inventory items"
    ON inventory_items FOR ALL
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'KITCHEN'::app_role]));

CREATE POLICY "Kitchen and Admins can view and record stock movements"
    ON stock_movements FOR ALL
    TO authenticated
    USING (EXISTS (
        SELECT 1 FROM inventory_items
        WHERE inventory_items.id = stock_movements.inventory_item_id
          AND has_role(inventory_items.restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'KITCHEN'::app_role])
    ));

-- ----------------------------------------------------------------------------
-- 11. Audit Logs (Admin and Owner only)
-- ----------------------------------------------------------------------------
CREATE POLICY "Admins and Owners can view audit logs"
    ON audit_logs FOR SELECT
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role]));

CREATE POLICY "Members can record audit entries"
    ON audit_logs FOR INSERT
    TO authenticated
    WITH CHECK (is_restaurant_member(restaurant_id));

