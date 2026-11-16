-- ============================================================================
-- CafeFlow Phase 04 Migration 04: Authentication, RBAC & Security Hardening
-- Version: 20261114000004
-- Scope: SEC-01 (Escalation Guard), SEC-02 (Parent Join Filtering),
--        SEC-03 (Order Status Restrictions), Username Resolution,
--        and Staff Account Provisioning Safeguards
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Username Support in user_profiles
-- ----------------------------------------------------------------------------
ALTER TABLE user_profiles
    ADD COLUMN IF NOT EXISTS username TEXT UNIQUE;

CREATE INDEX IF NOT EXISTS idx_user_profiles_username ON user_profiles(lower(username));

-- Secure Server-Side Username-to-Email Resolution
-- Resolves username to email for authentication without exposing auth.users
CREATE OR REPLACE FUNCTION public.resolve_username_to_email(p_identifier TEXT)
RETURNS TEXT
SECURITY DEFINER
SET search_path = public, auth
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_clean_id TEXT;
    v_email TEXT;
BEGIN
    v_clean_id := lower(trim(p_identifier));
    IF v_clean_id IS NULL OR length(v_clean_id) = 0 THEN
        RETURN NULL;
    END IF;

    -- If the identifier is already an email format, return it
    IF v_clean_id LIKE '%@%' THEN
        RETURN v_clean_id;
    END IF;

    -- Resolve username from user_profiles to auth.users.email
    SELECT u.email INTO v_email
    FROM auth.users u
    JOIN public.user_profiles p ON p.id = u.id
    WHERE lower(p.username) = v_clean_id
       OR p.phone = trim(p_identifier)
    LIMIT 1;

    RETURN v_email;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_username_to_email(TEXT) TO anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2. SEC-01: Admin Owner-Escalation Protection (Database Trigger)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_membership_security()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
DECLARE
    v_caller_uid UUID;
    v_caller_role app_role;
    v_target_restaurant_id UUID;
    v_owner_count INT;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required for membership operations.'
            USING ERRCODE = '42501';
    END IF;

    v_target_restaurant_id := COALESCE(NEW.restaurant_id, OLD.restaurant_id);

    -- Fetch caller role in the target restaurant
    SELECT role INTO v_caller_role
    FROM public.restaurant_memberships
    WHERE restaurant_id = v_target_restaurant_id
      AND user_id = v_caller_uid
      AND is_active = true
      AND deleted_at IS NULL;

    IF v_caller_role IS NULL THEN
        RAISE EXCEPTION 'Caller has no active membership in restaurant %.', v_target_restaurant_id
            USING ERRCODE = '42501';
    END IF;

    -- 1. Ordinary staff, cashier, or kitchen cannot manage memberships at all
    IF v_caller_role NOT IN ('OWNER'::app_role, 'ADMIN'::app_role) THEN
        RAISE EXCEPTION 'Unauthorized: only Owners and Admins may manage team memberships.'
            USING ERRCODE = '42501';
    END IF;

    -- 2. Anti-Self-Promotion: User cannot modify their own role
    IF TG_OP = 'UPDATE' AND OLD.user_id = v_caller_uid AND NEW.role <> OLD.role THEN
        RAISE EXCEPTION 'Unauthorized: users cannot alter their own assigned role.'
            USING ERRCODE = '42501';
    END IF;

    -- 3. ADMIN Escalation Guards:
    IF v_caller_role = 'ADMIN'::app_role THEN
        -- Admin cannot create or promote anyone to OWNER
        IF (TG_OP = 'INSERT' AND NEW.role = 'OWNER'::app_role) OR
           (TG_OP = 'UPDATE' AND NEW.role = 'OWNER'::app_role AND OLD.role <> 'OWNER'::app_role) THEN
            RAISE EXCEPTION 'Privilege escalation violation: Administrators cannot grant the OWNER role.'
                USING ERRCODE = '42501';
        END IF;

        -- Admin cannot alter or delete an existing OWNER membership
        IF (TG_OP IN ('UPDATE', 'DELETE') AND OLD.role = 'OWNER'::app_role) THEN
            RAISE EXCEPTION 'Privilege violation: Administrators cannot modify or revoke an Owner membership.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 4. Prevent deleting or deactivating the last active OWNER
    IF (TG_OP = 'DELETE' AND OLD.role = 'OWNER'::app_role) OR
       (TG_OP = 'UPDATE' AND OLD.role = 'OWNER'::app_role AND (NEW.is_active = false OR NEW.deleted_at IS NOT NULL OR NEW.role <> 'OWNER'::app_role)) THEN
        SELECT count(*) INTO v_owner_count
        FROM public.restaurant_memberships
        WHERE restaurant_id = v_target_restaurant_id
          AND role = 'OWNER'::app_role
          AND is_active = true
          AND deleted_at IS NULL
          AND id <> OLD.id;

        IF v_owner_count = 0 THEN
            RAISE EXCEPTION 'Cannot remove or demote the sole active Owner of the restaurant.'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_membership_security ON restaurant_memberships;
CREATE TRIGGER trg_enforce_membership_security
    BEFORE INSERT OR UPDATE OR DELETE ON restaurant_memberships
    FOR EACH ROW EXECUTE FUNCTION public.enforce_membership_security();

-- ----------------------------------------------------------------------------
-- 3. SEC-02: Menu Variant & Addon Parent Join Filtering
-- ----------------------------------------------------------------------------

-- Replace loose public variant policy with strict parent-item & restaurant join
DROP POLICY IF EXISTS "Public can view available variants" ON menu_item_variants;
CREATE POLICY "Public can view available variants"
    ON menu_item_variants FOR SELECT
    USING (
        is_available = true
        AND deleted_at IS NULL
        AND EXISTS (
            SELECT 1 FROM public.menu_items mi
            JOIN public.restaurants r ON r.id = mi.restaurant_id
            WHERE mi.id = menu_item_variants.menu_item_id
              AND mi.is_available = true
              AND mi.is_archived = false
              AND mi.deleted_at IS NULL
              AND r.is_active = true
              AND r.deleted_at IS NULL
        )
    );

-- Replace loose public addon policy with strict parent-item & restaurant join
DROP POLICY IF EXISTS "Public can view available addons" ON menu_item_addons;
CREATE POLICY "Public can view available addons"
    ON menu_item_addons FOR SELECT
    USING (
        is_available = true
        AND deleted_at IS NULL
        AND EXISTS (
            SELECT 1 FROM public.menu_items mi
            JOIN public.restaurants r ON r.id = mi.restaurant_id
            WHERE mi.id = menu_item_addons.menu_item_id
              AND mi.is_available = true
              AND mi.is_archived = false
              AND mi.deleted_at IS NULL
              AND r.is_active = true
              AND r.deleted_at IS NULL
        )
    );

-- ----------------------------------------------------------------------------
-- 4. SEC-03: Order Status Column Restrictions & Controlled Lifecycle RPC
-- ----------------------------------------------------------------------------

-- Remove broad row-level update policy on orders
DROP POLICY IF EXISTS "Kitchen and Cashier can update order status" ON orders;

-- Restrict direct row update on orders strictly to OWNER and ADMIN
CREATE POLICY "Admins can update orders"
    ON orders FOR UPDATE
    TO authenticated
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role]))
    WITH CHECK (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role]));

-- Controlled Order Status Transition RPC Function
-- Non-admin roles must advance orders through this function, preventing modification of financial totals
CREATE OR REPLACE FUNCTION public.advance_order_status(
    p_order_id UUID,
    p_next_status order_status,
    p_notes TEXT DEFAULT ''
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
DECLARE
    v_caller_uid UUID;
    v_order RECORD;
    v_caller_role app_role;
    v_is_allowed BOOLEAN := false;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    -- Retrieve order and verify existence
    SELECT * INTO v_order
    FROM public.orders
    WHERE id = p_order_id
      AND deleted_at IS NULL
    FOR UPDATE;

    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order % does not exist.', p_order_id USING ERRCODE = '02000';
    END IF;

    -- Retrieve caller role for this order's restaurant
    SELECT role INTO v_caller_role
    FROM public.restaurant_memberships
    WHERE restaurant_id = v_order.restaurant_id
      AND user_id = v_caller_uid
      AND is_active = true
      AND deleted_at IS NULL;

    IF v_caller_role IS NULL THEN
        RAISE EXCEPTION 'Access denied: caller is not a member of this restaurant.' USING ERRCODE = '42501';
    END IF;

    -- Validate role-specific lifecycle transition rules
    IF v_caller_role = 'KITCHEN'::app_role THEN
        -- Kitchen can only advance NEW -> PREPARING and PREPARING -> READY
        IF (v_order.status = 'NEW'::order_status AND p_next_status = 'PREPARING'::order_status) OR
           (v_order.status = 'PREPARING'::order_status AND p_next_status = 'READY'::order_status) THEN
            v_is_allowed := true;
        ELSE
            RAISE EXCEPTION 'Kitchen role may only advance orders from NEW to PREPARING, or PREPARING to READY.'
                USING ERRCODE = '42501';
        END IF;

    ELSIF v_caller_role = 'CASHIER'::app_role THEN
        -- Cashier can complete orders (READY -> COMPLETED) or cancel in-flight orders
        IF (v_order.status = 'READY'::order_status AND p_next_status = 'COMPLETED'::order_status) OR
           (v_order.status IN ('NEW'::order_status, 'PREPARING'::order_status) AND p_next_status = 'CANCELLED'::order_status) THEN
            v_is_allowed := true;
        ELSE
            RAISE EXCEPTION 'Cashier role cannot transition order from % to %.', v_order.status, p_next_status
                USING ERRCODE = '42501';
        END IF;

    ELSIF v_caller_role = 'STAFF'::app_role THEN
        -- Staff can only cancel their own newly created orders before preparation begins
        IF v_order.created_by = v_caller_uid AND
           v_order.status = 'NEW'::order_status AND
           p_next_status = 'CANCELLED'::order_status THEN
            v_is_allowed := true;
        ELSE
            RAISE EXCEPTION 'Staff role may only cancel their own pending NEW orders.'
                USING ERRCODE = '42501';
        END IF;

    ELSIF v_caller_role IN ('OWNER'::app_role, 'ADMIN'::app_role) THEN
        -- Owner and Admin have lifecycle transition authority
        v_is_allowed := true;
    END IF;

    IF NOT v_is_allowed THEN
        RAISE EXCEPTION 'Unauthorized order status transition.' USING ERRCODE = '42501';
    END IF;

    -- Execute status update: TOTALS, TAX, DISCOUNT, AND ITEMS ARE STRICTLY PRESERVED
    UPDATE public.orders
    SET status = p_next_status,
        updated_at = now()
    WHERE id = p_order_id;

    -- Record transition into order_status_history
    INSERT INTO public.order_status_history (
        order_id,
        previous_status,
        new_status,
        changed_by,
        changed_at,
        notes
    ) VALUES (
        p_order_id,
        v_order.status,
        p_next_status,
        v_caller_uid,
        now(),
        p_notes
    );

    RETURN jsonb_build_object(
        'order_id', p_order_id,
        'previous_status', v_order.status,
        'new_status', p_next_status,
        'changed_by', v_caller_uid
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.advance_order_status(UUID, order_status, TEXT) TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. Staff Account Provisioning Safeguards
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.provision_staff_member(
    p_restaurant_id UUID,
    p_user_id UUID,
    p_role app_role,
    p_full_name TEXT,
    p_phone TEXT DEFAULT NULL,
    p_username TEXT DEFAULT NULL
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
DECLARE
    v_caller_uid UUID;
    v_caller_role app_role;
    v_membership_id UUID;
BEGIN
    v_caller_uid := auth.uid();
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
    END IF;

    -- Verify caller role
    SELECT role INTO v_caller_role
    FROM public.restaurant_memberships
    WHERE restaurant_id = p_restaurant_id
      AND user_id = v_caller_uid
      AND is_active = true
      AND deleted_at IS NULL;

    IF v_caller_role NOT IN ('OWNER'::app_role, 'ADMIN'::app_role) THEN
        RAISE EXCEPTION 'Only Owners and Admins may provision staff accounts.' USING ERRCODE = '42501';
    END IF;

    -- SEC-01 check: Admin cannot provision an Owner
    IF v_caller_role = 'ADMIN'::app_role AND p_role = 'OWNER'::app_role THEN
        RAISE EXCEPTION 'Admins cannot provision an account with the OWNER role.' USING ERRCODE = '42501';
    END IF;

    -- Upsert profile
    INSERT INTO public.user_profiles (id, full_name, phone, username, is_active)
    VALUES (p_user_id, p_full_name, p_phone, lower(trim(p_username)), true)
    ON CONFLICT (id) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        phone = COALESCE(EXCLUDED.phone, user_profiles.phone),
        username = COALESCE(EXCLUDED.username, user_profiles.username),
        updated_at = now();

    -- Upsert membership
    INSERT INTO public.restaurant_memberships (restaurant_id, user_id, role, is_active)
    VALUES (p_restaurant_id, p_user_id, p_role, true)
    ON CONFLICT (restaurant_id, user_id) DO UPDATE SET
        role = EXCLUDED.role,
        is_active = true,
        deleted_at = NULL,
        updated_at = now()
    RETURNING id INTO v_membership_id;

    RETURN jsonb_build_object(
        'membership_id', v_membership_id,
        'restaurant_id', p_restaurant_id,
        'user_id', p_user_id,
        'role', p_role
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.provision_staff_member(UUID, UUID, app_role, TEXT, TEXT, TEXT) TO authenticated;

