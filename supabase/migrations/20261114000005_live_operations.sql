-- ============================================================================
-- CafeFlow Phase 05 Migration: Live Operations & Realtime Enhancements
-- Version: 20261114000005
-- Scope: 
--   1. Realtime publication additions (menu_categories, customers, stock_movements)
--   2. Atomic order creation RPC (create_order_with_items)
--   3. Transactional inventory adjustment RPC (adjust_inventory_stock)
--   4. Table status management RPC (update_table_status)
--   5. Idempotency & order duplicate prevention
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Realtime Publication Enhancements
-- ----------------------------------------------------------------------------
ALTER TABLE menu_categories REPLICA IDENTITY FULL;
ALTER TABLE customers REPLICA IDENTITY FULL;
ALTER TABLE stock_movements REPLICA IDENTITY FULL;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE menu_categories;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE customers;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE stock_movements;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- Add idempotency_key to orders table if not present
DO $$ BEGIN
    ALTER TABLE public.orders ADD COLUMN idempotency_key TEXT;
    CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_idempotency 
        ON public.orders(restaurant_id, idempotency_key) 
        WHERE idempotency_key IS NOT NULL;
EXCEPTION
    WHEN duplicate_column THEN NULL;
END $$;

-- ----------------------------------------------------------------------------
-- 2. Atomic Order Creation RPC: create_order_with_items
-- ----------------------------------------------------------------------------
-- Creates an order and its items in a single atomic transaction.
-- Snapshots product names and unit prices from trusted menu_items rows,
-- computes subtotal, tax, and total server-side, preventing client tampering.
CREATE OR REPLACE FUNCTION public.create_order_with_items(
    p_restaurant_id UUID,
    p_table_name TEXT,
    p_special_instructions TEXT DEFAULT '',
    p_discount_minor BIGINT DEFAULT 0,
    p_items JSONB DEFAULT '[]'::jsonb,
    p_idempotency_key TEXT DEFAULT NULL,
    p_customer_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role TEXT;
    v_order_id UUID;
    v_order_number TEXT;
    v_today_seq INT;
    v_subtotal_minor BIGINT := 0;
    v_tax_rate_bps INT := 500; -- Default 5.00%
    v_tax_minor BIGINT := 0;
    v_total_minor BIGINT := 0;
    v_item JSONB;
    v_menu_item_id UUID;
    v_item_name TEXT;
    v_unit_price BIGINT;
    v_quantity INT;
    v_line_total BIGINT;
    v_is_available BOOLEAN;
    v_is_archived BOOLEAN;
    v_existing_order_id UUID;
    v_existing_order_number TEXT;
BEGIN
    v_caller_id := auth.uid();

    -- Validate idempotency key if provided
    IF p_idempotency_key IS NOT NULL AND p_idempotency_key != '' THEN
        SELECT id, order_number INTO v_existing_order_id, v_existing_order_number
        FROM public.orders
        WHERE restaurant_id = p_restaurant_id
          AND idempotency_key = p_idempotency_key;

        IF v_existing_order_id IS NOT NULL THEN
            RETURN jsonb_build_object(
                'id', v_existing_order_id,
                'order_number', v_existing_order_number,
                'idempotent_replay', true
            );
        END IF;
    END IF;

    -- Validate caller membership and permissions
    IF v_caller_id IS NOT NULL THEN
        SELECT role INTO v_caller_role
        FROM public.restaurant_memberships
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_caller_id
          AND is_active = TRUE;

        IF v_caller_role IS NULL THEN
            RAISE EXCEPTION 'Unauthorized: Caller has no active membership in this restaurant.'
                USING ERRCODE = '42501';
        END IF;

        IF v_caller_role NOT IN ('OWNER', 'ADMIN', 'CASHIER', 'STAFF') THEN
            RAISE EXCEPTION 'Unauthorized: Role % cannot create customer orders.', v_caller_role
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- Validate item list is not empty
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Order validation error: At least one item is required.'
            USING ERRCODE = '22023';
    END IF;

    -- Fetch restaurant tax setting if available
    SELECT COALESCE(gst_rate_basis_points, 500) INTO v_tax_rate_bps
    FROM public.restaurant_settings
    WHERE restaurant_id = p_restaurant_id;

    -- Generate sequence-based order number (e.g. CF-1045 or ORD-20261115-001)
    SELECT COUNT(*) + 1 INTO v_today_seq
    FROM public.orders
    WHERE restaurant_id = p_restaurant_id
      AND created_at::date = CURRENT_DATE;

    v_order_number := 'CF-' || TO_CHAR(CURRENT_DATE, 'YYMMDD') || '-' || LPAD(v_today_seq::text, 3, '0');

    -- Create empty order row first
    INSERT INTO public.orders (
        restaurant_id,
        order_number,
        table_name,
        customer_id,
        status,
        subtotal_minor,
        discount_minor,
        tax_minor,
        total_minor,
        special_instructions,
        created_by,
        idempotency_key
    ) VALUES (
        p_restaurant_id,
        v_order_number,
        COALESCE(NULLIF(p_table_name, ''), 'Takeaway'),
        p_customer_id,
        'NEW'::public.order_status,
        0,
        GREATEST(0, p_discount_minor),
        0,
        0,
        COALESCE(p_special_instructions, ''),
        v_caller_id,
        p_idempotency_key
    ) RETURNING id INTO v_order_id;

    -- Iterate items, verifying availability and prices from DB
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_menu_item_id := (v_item->>'menu_item_id')::UUID;
        v_quantity := COALESCE((v_item->>'quantity')::INT, 1);

        IF v_quantity <= 0 THEN
            RAISE EXCEPTION 'Item quantity must be greater than zero.'
                USING ERRCODE = '22023';
        END IF;

        -- Verify product from database
        SELECT name, price_minor, is_available, is_archived
        INTO v_item_name, v_unit_price, v_is_available, v_is_archived
        FROM public.menu_items
        WHERE id = v_menu_item_id
          AND restaurant_id = p_restaurant_id;

        IF v_item_name IS NULL OR v_is_archived THEN
            RAISE EXCEPTION 'Product % is no longer available on this menu.', v_menu_item_id
                USING ERRCODE = '22023';
        END IF;

        IF NOT v_is_available THEN
            RAISE EXCEPTION 'Product "%" is currently marked unavailable.', v_item_name
                USING ERRCODE = '22023';
        END IF;

        v_line_total := v_unit_price * v_quantity;
        v_subtotal_minor := v_subtotal_minor + v_line_total;

        -- Insert order item
        INSERT INTO public.order_items (
            order_id,
            menu_item_id,
            item_name,
            unit_price_minor,
            quantity,
            total_price_minor,
            selected_variant,
            selected_addons,
            notes
        ) VALUES (
            v_order_id,
            v_menu_item_id,
            v_item_name,
            v_unit_price,
            v_quantity,
            v_line_total,
            v_item->>'selected_variant',
            ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_item->'selected_addons', '[]'::jsonb))),
            COALESCE(v_item->>'notes', '')
        );
    END LOOP;

    -- Validate discount
    IF p_discount_minor > v_subtotal_minor THEN
        RAISE EXCEPTION 'Discount cannot exceed order subtotal.'
            USING ERRCODE = '22023';
    END IF;

    -- Calculate tax on taxable amount
    v_tax_minor := ((v_subtotal_minor - p_discount_minor) * v_tax_rate_bps) / 10000;
    v_total_minor := v_subtotal_minor - p_discount_minor + v_tax_minor;

    -- Update final verified amounts on order
    UPDATE public.orders
    SET subtotal_minor = v_subtotal_minor,
        discount_minor = p_discount_minor,
        tax_minor = v_tax_minor,
        total_minor = v_total_minor
    WHERE id = v_order_id;

    -- Record initial order status history
    INSERT INTO public.order_status_history (
        order_id,
        previous_status,
        new_status,
        changed_by,
        notes
    ) VALUES (
        v_order_id,
        NULL,
        'NEW'::public.order_status,
        v_caller_id,
        'Order submitted'
    );

    RETURN jsonb_build_object(
        'id', v_order_id,
        'order_number', v_order_number,
        'subtotal_minor', v_subtotal_minor,
        'discount_minor', p_discount_minor,
        'tax_minor', v_tax_minor,
        'total_minor', v_total_minor,
        'idempotent_replay', false
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_order_with_items TO authenticated, anon;

-- ----------------------------------------------------------------------------
-- 3. Inventory Stock Adjustment RPC: adjust_inventory_stock
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.adjust_inventory_stock(
    p_restaurant_id UUID,
    p_inventory_item_id UUID,
    p_movement_type TEXT,
    p_quantity_change NUMERIC,
    p_reason TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role TEXT;
    v_prev_stock NUMERIC(12, 3);
    v_new_stock NUMERIC(12, 3);
BEGIN
    v_caller_id := auth.uid();

    IF v_caller_id IS NOT NULL THEN
        SELECT role INTO v_caller_role
        FROM public.restaurant_memberships
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_caller_id
          AND is_active = TRUE;

        IF v_caller_role IS NULL OR v_caller_role NOT IN ('OWNER', 'ADMIN', 'KITCHEN') THEN
            RAISE EXCEPTION 'Unauthorized: Caller cannot adjust inventory stock.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- Get and lock current inventory item row
    SELECT current_stock INTO v_prev_stock
    FROM public.inventory_items
    WHERE id = p_inventory_item_id
      AND restaurant_id = p_restaurant_id
    FOR UPDATE;

    IF v_prev_stock IS NULL THEN
        RAISE EXCEPTION 'Inventory item % does not exist in this restaurant.', p_inventory_item_id
            USING ERRCODE = '22023';
    END IF;

    v_new_stock := v_prev_stock + p_quantity_change;
    IF v_new_stock < 0 THEN
        v_new_stock := 0;
    END IF;

    -- Update inventory item
    UPDATE public.inventory_items
    SET current_stock = v_new_stock,
        updated_at = now()
    WHERE id = p_inventory_item_id;

    -- Record stock movement
    INSERT INTO public.stock_movements (
        inventory_item_id,
        movement_type,
        quantity_change,
        previous_stock,
        new_stock,
        reason,
        performed_by
    ) VALUES (
        p_inventory_item_id,
        p_movement_type::public.stock_movement_type,
        p_quantity_change,
        v_prev_stock,
        v_new_stock,
        COALESCE(p_reason, ''),
        v_caller_id
    );

    RETURN jsonb_build_object(
        'inventory_item_id', p_inventory_item_id,
        'previous_stock', v_prev_stock,
        'new_stock', v_new_stock,
        'quantity_change', p_quantity_change
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.adjust_inventory_stock TO authenticated, anon;

-- ----------------------------------------------------------------------------
-- 4. Dining Table Status Management RPC: update_table_status
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_table_status(
    p_restaurant_id UUID,
    p_table_id UUID,
    p_status TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role TEXT;
BEGIN
    v_caller_id := auth.uid();

    IF v_caller_id IS NOT NULL THEN
        SELECT role INTO v_caller_role
        FROM public.restaurant_memberships
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_caller_id
          AND is_active = TRUE;

        IF v_caller_role IS NULL OR v_caller_role NOT IN ('OWNER', 'ADMIN', 'CASHIER', 'STAFF') THEN
            RAISE EXCEPTION 'Unauthorized: Caller cannot update table status.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    UPDATE public.dining_tables
    SET status = p_status::public.table_status,
        updated_at = now()
    WHERE id = p_table_id
      AND restaurant_id = p_restaurant_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_table_status TO authenticated, anon;

