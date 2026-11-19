-- ============================================================================
-- Migration 000012: Secure Live Demo Backend, Restricted Roles, Immutability & Isolation
-- Version: 20261119000012
-- Scope: Edge-Function-mediated Demo Auth, DEMO_OWNER role, Seed Immutability,
--        Demonstrator Session Overlays, Public Order Circuit Breaker, Hourly Sanitation
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Restricted Demo Roles in app_role ENUM
-- ----------------------------------------------------------------------------
DO $$ BEGIN
    ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'DEMO_OWNER';
    ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'DEMO_STAFF';
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- ----------------------------------------------------------------------------
-- 2. Schema Extensions (Demo Isolation Flags & Session Columns)
-- ----------------------------------------------------------------------------
ALTER TABLE public.restaurants 
    ADD COLUMN IF NOT EXISTS is_demo BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.menu_items 
    ADD COLUMN IF NOT EXISTS is_seed BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS demo_session_id UUID NULL;

ALTER TABLE public.menu_categories 
    ADD COLUMN IF NOT EXISTS is_seed BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.orders 
    ADD COLUMN IF NOT EXISTS demo_session_id UUID NULL,
    ADD COLUMN IF NOT EXISTS order_type TEXT NOT NULL DEFAULT 'DINE_IN';

CREATE INDEX IF NOT EXISTS idx_orders_demo_session 
    ON public.orders(demo_session_id) WHERE demo_session_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_menu_items_demo_session 
    ON public.menu_items(demo_session_id) WHERE demo_session_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 3. Flag Seed Flagship Bistro and Baseline Menu Items
-- ----------------------------------------------------------------------------
UPDATE public.restaurants 
SET is_demo = true 
WHERE id = 'a0000000-0000-0000-0000-000000000001';

UPDATE public.menu_items 
SET is_seed = true 
WHERE restaurant_id = 'a0000000-0000-0000-0000-000000000001';

UPDATE public.menu_categories 
SET is_seed = true 
WHERE restaurant_id = 'a0000000-0000-0000-0000-000000000001';

-- ----------------------------------------------------------------------------
-- 4. Demo Sessions & Pairing Table (Server-Controlled Lifetime)
-- ----------------------------------------------------------------------------
-- Uses TEXT CHECK constraint for role to prevent PostgreSQL transactional enum invariant
-- violations during single-transaction migration application (supabase db push).
CREATE TABLE IF NOT EXISTS public.demo_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'DEMO_OWNER' CHECK (role IN ('DEMO_OWNER', 'DEMO_STAFF')),
    pairing_code TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '2 hours')
);

CREATE INDEX IF NOT EXISTS idx_demo_sessions_user 
    ON public.demo_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_demo_sessions_pairing 
    ON public.demo_sessions(pairing_code) WHERE expires_at > now();

ALTER TABLE public.demo_sessions ENABLE ROW LEVEL SECURITY;

-- Demonstrators can inspect strictly their own session records (prevents open enumeration)
DROP POLICY IF EXISTS "Active pairing codes are queryable" ON public.demo_sessions;
DROP POLICY IF EXISTS "Users can view own demo sessions" ON public.demo_sessions;
CREATE POLICY "Users can view own demo sessions"
    ON public.demo_sessions FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- Dedicated secure RPC for pairing code resolution (prevents scraping all pairing codes)
CREATE OR REPLACE FUNCTION public.resolve_demo_pairing_code(p_code TEXT)
RETURNS UUID
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_session_id UUID;
BEGIN
    IF p_code IS NULL OR length(trim(p_code)) = 0 THEN
        RETURN NULL;
    END IF;

    SELECT id INTO v_session_id
    FROM public.demo_sessions
    WHERE pairing_code = trim(p_code) AND expires_at > now()
    LIMIT 1;

    RETURN v_session_id;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_demo_pairing_code FROM public;
GRANT EXECUTE ON FUNCTION public.resolve_demo_pairing_code TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. Server-Side Helper Functions for Session & Demo User Resolution
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_demo_user()
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.restaurant_memberships
        WHERE user_id = auth.uid()
          AND role::text IN ('DEMO_OWNER', 'DEMO_STAFF')
          AND is_active = true
          AND deleted_at IS NULL
    );
$$;

CREATE OR REPLACE FUNCTION public.current_demo_session_id()
RETURNS UUID
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE sql STABLE AS $$
    SELECT id FROM public.demo_sessions
    WHERE user_id = auth.uid() AND expires_at > now()
    ORDER BY created_at DESC
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_demo_session()
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE sql STABLE AS $$
    SELECT (public.current_demo_session_id() IS NOT NULL);
$$;

-- ----------------------------------------------------------------------------
-- 6. Rate Limiting Table & Infrastructure
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.demo_rate_limits (
    client_id TEXT NOT NULL,
    action_type TEXT NOT NULL,
    window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
    request_count INT NOT NULL DEFAULT 1,
    PRIMARY KEY (client_id, action_type)
);

CREATE INDEX IF NOT EXISTS idx_demo_rate_limits_window 
    ON public.demo_rate_limits(window_start);

ALTER TABLE public.demo_rate_limits ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.check_and_increment_rate_limit(
    p_client_id TEXT,
    p_action TEXT,
    p_window_minutes INT,
    p_max_requests INT
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
DECLARE
    v_record RECORD;
    v_cutoff TIMESTAMPTZ := now() - (p_window_minutes || ' minutes')::INTERVAL;
BEGIN
    SELECT * INTO v_record
    FROM public.demo_rate_limits
    WHERE client_id = p_client_id AND action_type = p_action
    FOR UPDATE;

    IF v_record IS NOT NULL THEN
        IF v_record.window_start > v_cutoff THEN
            IF v_record.request_count >= p_max_requests THEN
                RETURN false; -- Rate limit exceeded
            ELSE
                UPDATE public.demo_rate_limits
                SET request_count = request_count + 1
                WHERE client_id = p_client_id AND action_type = p_action;
                RETURN true;
            END IF;
        ELSE
            UPDATE public.demo_rate_limits
            SET window_start = now(), request_count = 1
            WHERE client_id = p_client_id AND action_type = p_action;
            RETURN true;
        END IF;
    ELSE
        INSERT INTO public.demo_rate_limits (client_id, action_type, window_start, request_count)
        VALUES (p_client_id, p_action, now(), 1);
        RETURN true;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.check_and_increment_rate_limit FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_increment_rate_limit TO service_role;

-- ----------------------------------------------------------------------------
-- 7. Seed Catalog Immutability Trigger (Defense Against Presentation Defacement)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_seed_catalog_immutability()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
    -- Prevent deletion of baseline seed products
    IF TG_OP = 'DELETE' AND OLD.is_seed = true THEN
        RAISE EXCEPTION 'Core seed demo items cannot be deleted. You may disable availability instead.' 
            USING ERRCODE = '42501';
    END IF;

    -- Prevent permanent archiving or name defacement of seed products
    IF TG_OP = 'UPDATE' AND OLD.is_seed = true THEN
        IF NEW.name <> OLD.name OR NEW.description <> OLD.description THEN
            RAISE EXCEPTION 'Core seed demo item names and descriptions cannot be modified.' 
                USING ERRCODE = '42501';
        END IF;

        IF NEW.is_archived = true AND OLD.is_archived = false THEN
            RAISE EXCEPTION 'Core seed demo items cannot be archived. Toggle availability instead.' 
                USING ERRCODE = '42501';
        END IF;

        -- Enforce sanity price clamping between ₹10.00 (1000 minor) and ₹10,000.00 (1000000 minor)
        IF NEW.price_minor < 1000 OR NEW.price_minor > 1000000 THEN
            RAISE EXCEPTION 'Price must remain between ₹10.00 and ₹10,000.00.' 
                USING ERRCODE = '22023';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_seed_menu_items ON public.menu_items;
CREATE TRIGGER trg_protect_seed_menu_items
    BEFORE UPDATE OR DELETE ON public.menu_items
    FOR EACH ROW
    WHEN (OLD.is_seed = true)
    EXECUTE FUNCTION public.enforce_seed_catalog_immutability();

-- ----------------------------------------------------------------------------
-- 8. Block DEMO_OWNER from Altering Core Store Settings
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protect_demo_restaurant_settings()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
DECLARE
    v_is_demo BOOLEAN;
BEGIN
    SELECT is_demo INTO v_is_demo
    FROM public.restaurants
    WHERE id = OLD.restaurant_id;

    IF v_is_demo IS TRUE THEN
        -- Only service_role can alter settings for demo restaurants
        IF auth.role() <> 'service_role' THEN
            RAISE EXCEPTION 'Configuration changes are disabled for the demo bistro.' 
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_demo_settings ON public.restaurant_settings;
CREATE TRIGGER trg_protect_demo_settings
    BEFORE UPDATE OR DELETE ON public.restaurant_settings
    FOR EACH ROW
    EXECUTE FUNCTION public.protect_demo_restaurant_settings();

-- ----------------------------------------------------------------------------
-- 8b. Financial Deletion Trigger Exemption for Automated Demo Sanitation
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prevent_financial_deletion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Permit automated sanitation of demo orders by service_role in demo bistro
    IF OLD.restaurant_id = 'a0000000-0000-0000-0000-000000000001' AND auth.role() = 'service_role' THEN
        RETURN OLD;
    END IF;

    RAISE EXCEPTION 'Security violation: Deletion of financial records (% table, id %) is strictly forbidden for auditing integrity.',
        TG_TABLE_NAME, OLD.id
        USING ERRCODE = '42501';
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. Demonstrator Order Policies (SELECT, INSERT, UPDATE)
-- ----------------------------------------------------------------------------
-- Non-demo members see all orders in their tenant.
-- Demo visitors see strictly active session orders. If expired, yields 0 orders (eliminates fallthrough).
DROP POLICY IF EXISTS "Members can view restaurant orders" ON public.orders;
CREATE POLICY "Members can view restaurant orders"
    ON public.orders FOR SELECT
    TO authenticated
    USING (
        is_restaurant_member(restaurant_id) AND (
            -- Non-demo members see all orders in their tenant
            NOT public.is_demo_user()
            OR
            -- Demo users see strictly their own active session orders
            (public.is_demo_user() AND demo_session_id IS NOT NULL AND demo_session_id = public.current_demo_session_id())
        )
    );

-- Demo users can insert POS orders scoped to their active demo session
DROP POLICY IF EXISTS "Demo users can create demo orders" ON public.orders;
CREATE POLICY "Demo users can create demo orders"
    ON public.orders FOR INSERT
    TO authenticated
    WITH CHECK (
        restaurant_id = 'a0000000-0000-0000-0000-000000000001'
        AND public.is_demo_user()
        AND demo_session_id IS NOT NULL
        AND demo_session_id = public.current_demo_session_id()
    );

-- Demo users can update POS orders scoped to their active demo session
DROP POLICY IF EXISTS "Demo users can update demo orders" ON public.orders;
CREATE POLICY "Demo users can update demo orders"
    ON public.orders FOR UPDATE
    TO authenticated
    USING (
        restaurant_id = 'a0000000-0000-0000-0000-000000000001'
        AND public.is_demo_user()
        AND demo_session_id IS NOT NULL
        AND demo_session_id = public.current_demo_session_id()
    )
    WITH CHECK (
        restaurant_id = 'a0000000-0000-0000-0000-000000000001'
        AND public.is_demo_user()
        AND demo_session_id IS NOT NULL
        AND demo_session_id = public.current_demo_session_id()
    );

-- ----------------------------------------------------------------------------
-- 9b. Order Status RPC Authority for Demo Roles
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.advance_order_status(
    p_order_id UUID,
    p_next_status order_status,
    p_notes TEXT DEFAULT ''
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public, pg_temp
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

    -- Demo roles can advance tickets within their active demo session in the demo bistro
    IF v_caller_role::text IN ('DEMO_OWNER', 'DEMO_STAFF') THEN
        IF v_order.restaurant_id = 'a0000000-0000-0000-0000-000000000001'
           AND v_order.demo_session_id IS NOT NULL
           AND v_order.demo_session_id = public.current_demo_session_id() THEN
            v_is_allowed := true;
        ELSE
            RAISE EXCEPTION 'Demo users may only advance orders in their active demo session.'
                USING ERRCODE = '42501';
        END IF;
    ELSIF v_caller_role = 'KITCHEN'::app_role THEN
        IF (v_order.status = 'NEW'::order_status AND p_next_status = 'PREPARING'::order_status) OR
           (v_order.status = 'PREPARING'::order_status AND p_next_status = 'READY'::order_status) THEN
            v_is_allowed := true;
        ELSE
            RAISE EXCEPTION 'Kitchen role may only advance orders from NEW to PREPARING, or PREPARING to READY.'
                USING ERRCODE = '42501';
        END IF;
    ELSIF v_caller_role = 'CASHIER'::app_role THEN
        IF (v_order.status = 'READY'::order_status AND p_next_status = 'COMPLETED'::order_status) OR
           (v_order.status IN ('NEW'::order_status, 'PREPARING'::order_status) AND p_next_status = 'CANCELLED'::order_status) THEN
            v_is_allowed := true;
        ELSE
            RAISE EXCEPTION 'Cashier role cannot transition order from % to %.', v_order.status, p_next_status
                USING ERRCODE = '42501';
        END IF;
    ELSIF v_caller_role = 'STAFF'::app_role THEN
        IF v_order.created_by = v_caller_uid AND
           v_order.status = 'NEW'::order_status AND
           p_next_status = 'CANCELLED'::order_status THEN
            v_is_allowed := true;
        ELSE
            RAISE EXCEPTION 'Staff role may only cancel their own pending NEW orders.'
                USING ERRCODE = '42501';
        END IF;
    ELSIF v_caller_role IN ('OWNER'::app_role, 'ADMIN'::app_role) THEN
        v_is_allowed := true;
    END IF;

    IF NOT v_is_allowed THEN
        RAISE EXCEPTION 'Unauthorized order status transition.' USING ERRCODE = '42501';
    END IF;

    UPDATE public.orders
    SET status = p_next_status,
        updated_at = now()
    WHERE id = p_order_id;

    INSERT INTO public.order_status_history (
        order_id,
        previous_status,
        new_status,
        changed_by,
        notes
    ) VALUES (
        p_order_id,
        v_order.status,
        p_next_status,
        v_caller_uid,
        p_notes
    );

    RETURN jsonb_build_object(
        'order_id', p_order_id,
        'previous_status', v_order.status,
        'new_status', p_next_status,
        'transitioned_at', now()
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 10. Demonstrator Custom Menu Items Policies (SELECT & MANAGE)
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can view all menu items" ON public.menu_items;
CREATE POLICY "Members can view all menu items"
    ON public.menu_items FOR SELECT
    TO authenticated
    USING (
        is_restaurant_member(restaurant_id) AND (
            -- Non-demo members see all items
            NOT public.is_demo_user()
            OR
            -- Seed items are visible to all demo sessions
            is_seed = true
            OR
            -- Custom demo items are visible strictly to the creator's active session
            (public.is_demo_user() AND demo_session_id IS NOT NULL AND demo_session_id = public.current_demo_session_id())
        )
    );

-- Demo Owner can manage custom items and update seed item prices/availability within trigger guards
DROP POLICY IF EXISTS "Demo owner can manage demo menu items" ON public.menu_items;
CREATE POLICY "Demo owner can manage demo menu items"
    ON public.menu_items FOR ALL
    TO authenticated
    USING (
        restaurant_id = 'a0000000-0000-0000-0000-000000000001'
        AND public.is_demo_user()
        AND (
            is_seed = true
            OR
            (demo_session_id IS NOT NULL AND demo_session_id = public.current_demo_session_id())
        )
    )
    WITH CHECK (
        restaurant_id = 'a0000000-0000-0000-0000-000000000001'
        AND public.is_demo_user()
        AND (
            is_seed = true
            OR
            (demo_session_id IS NOT NULL AND demo_session_id = public.current_demo_session_id())
        )
    );

-- ----------------------------------------------------------------------------
-- 11. Hardened Public Customer Online Order Placement RPC
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_public_online_order(
    p_customer_name TEXT,
    p_customer_phone TEXT,
    p_order_type TEXT,
    p_table_name TEXT,
    p_special_instructions TEXT,
    p_items JSONB,
    p_pairing_code TEXT DEFAULT NULL,
    p_client_ip TEXT DEFAULT 'web-guest'
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
DECLARE
    v_demo_id UUID := 'a0000000-0000-0000-0000-000000000001';
    v_active_count INT;
    v_rate_allowed BOOLEAN;
    v_session_id UUID;
    v_order_id UUID;
    v_order_number TEXT;
    v_subtotal INT := 0;
    v_tax INT := 0;
    v_total INT := 0;
    v_item JSONB;
    v_item_id UUID;
    v_qty INT;
    v_db_price INT;
    v_db_name TEXT;
    v_db_avail BOOLEAN;
    v_clean_name TEXT;
    v_effective_ip TEXT;
    v_header_ip TEXT;
BEGIN
    -- 1. Active Order Queue Circuit Breaker (Max 30 active tickets)
    SELECT count(*) INTO v_active_count
    FROM public.orders
    WHERE restaurant_id = v_demo_id 
      AND status IN ('NEW', 'PREPARING');

    IF v_active_count >= 30 THEN
        RAISE EXCEPTION 'The demo kitchen queue has reached capacity (30 active orders). Please complete or advance existing tickets first.'
            USING ERRCODE = '54000';
    END IF;

    -- 2. Sliding-Window Rate Limiting (Server-Derived IP)
    -- Inspects request.headers injected by PostgREST to prevent client argument tampering
    BEGIN
        v_header_ip := coalesce(
            nullif(trim(current_setting('request.headers', true)::jsonb->>'cf-connecting-ip'), ''),
            nullif(trim(split_part(coalesce(current_setting('request.headers', true)::jsonb->>'x-forwarded-for', ''), ',', 1)), '')
        );
    EXCEPTION WHEN OTHERS THEN
        v_header_ip := NULL;
    END;

    v_effective_ip := coalesce(v_header_ip, nullif(trim(p_client_ip), ''), 'web-guest');

    v_rate_allowed := public.check_and_increment_rate_limit(v_effective_ip, 'ONLINE_ORDER', 5, 3);
    IF v_rate_allowed IS NOT TRUE THEN
        RAISE EXCEPTION 'Order submission rate limit exceeded (max 3 orders per 5 minutes). Please wait.'
            USING ERRCODE = '42900';
    END IF;

    -- 3. Resolve Optional Session Pairing Code via dedicated resolution logic
    IF p_pairing_code IS NOT NULL AND length(trim(p_pairing_code)) > 0 THEN
        v_session_id := public.resolve_demo_pairing_code(p_pairing_code);
        IF v_session_id IS NULL THEN
            RAISE EXCEPTION 'Demo channel code % is invalid or expired. Please check the 6-digit code on the demonstrator screen.' p_pairing_code
                USING ERRCODE = '22023';
        END IF;
    ELSE
        -- Default to the most recent active demo session if none specified
        SELECT id INTO v_session_id
        FROM public.demo_sessions
        WHERE expires_at > now()
        ORDER BY created_at DESC
        LIMIT 1;
    END IF;

    -- 4. Input Sanitization
    v_clean_name := trim(regexp_replace(p_customer_name, '[^a-zA-Z0-9 .''-]', '', 'g'));
    IF length(v_clean_name) < 2 OR length(v_clean_name) > 40 THEN
        RAISE EXCEPTION 'Please provide a valid customer name (2-40 characters).' USING ERRCODE = '22023';
    END IF;

    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 OR jsonb_array_length(p_items) > 6 THEN
        RAISE EXCEPTION 'Orders must contain between 1 and 6 items.' USING ERRCODE = '22023';
    END IF;

    -- 5. Server-Enforced Price Verification (Never trust client prices)
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_item_id := (v_item->>'product_id')::UUID;
        v_qty := GREATEST(1, LEAST(5, coalesce((v_item->>'quantity')::INT, 1)));

        SELECT name, price_minor, is_available INTO v_db_name, v_db_price, v_db_avail
        FROM public.menu_items
        WHERE id = v_item_id AND restaurant_id = v_demo_id AND is_archived = false;

        IF v_db_price IS NULL OR v_db_avail IS NOT TRUE THEN
            RAISE EXCEPTION 'Product % is unavailable.' v_db_name USING ERRCODE = '22023';
        END IF;

        v_subtotal := v_subtotal + (v_db_price * v_qty);
    END LOOP;

    -- Compute 5.00% GST
    v_tax := (v_subtotal * 500) / 10000;
    v_total := v_subtotal + v_tax;

    -- 6. Sequence Number
    v_order_number := 'WEB-' || to_char(now(), 'HH24MI') || '-' || floor(random() * 900 + 100)::TEXT;

    -- 7. Insert Order
    INSERT INTO public.orders (
        restaurant_id,
        demo_session_id,
        order_number,
        table_name,
        order_type,
        status,
        financial_status,
        subtotal_minor,
        tax_minor,
        total_minor,
        special_instructions,
        created_at
    ) VALUES (
        v_demo_id,
        v_session_id,
        v_order_number,
        CASE WHEN p_order_type = 'DINE_IN' THEN coalesce(nullif(trim(p_table_name), ''), 'Table 01') ELSE 'Takeaway' END,
        CASE WHEN p_order_type = 'DINE_IN' THEN 'DINE_IN' ELSE 'TAKEAWAY' END,
        'NEW',
        'UNPAID',
        v_subtotal,
        v_tax,
        v_total,
        left(trim(coalesce(p_special_instructions, '')), 120),
        now()
    ) RETURNING id INTO v_order_id;

    -- 8. Insert Order Items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_item_id := (v_item->>'product_id')::UUID;
        v_qty := GREATEST(1, LEAST(5, coalesce((v_item->>'quantity')::INT, 1)));

        SELECT name, price_minor INTO v_db_name, v_db_price
        FROM public.menu_items
        WHERE id = v_item_id;

        INSERT INTO public.order_items (
            order_id,
            menu_item_id,
            item_name,
            unit_price_minor,
            quantity,
            total_price_minor
        ) VALUES (
            v_order_id,
            v_item_id,
            v_db_name,
            v_db_price,
            v_qty,
            v_db_price * v_qty
        );
    END LOOP;

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'order_number', v_order_number,
        'subtotal_minor', v_subtotal,
        'tax_minor', v_tax,
        'total_minor', v_total,
        'pairing_code', p_pairing_code
    );
END;
$$;

REVOKE ALL ON FUNCTION public.create_public_online_order FROM public;
GRANT EXECUTE ON FUNCTION public.create_public_online_order TO anon, authenticated;

-- ----------------------------------------------------------------------------
-- 12. Automated Hourly Sanitation Procedure (Runs Hourly via pg_cron or Edge Cron)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reset_demo_tenant_data()
RETURNS VOID
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
DECLARE
    v_demo_id UUID := 'a0000000-0000-0000-0000-000000000001';
BEGIN
    -- 1. Purge demo orders older than 60 minutes (authorized via prevent_financial_deletion exemption)
    DELETE FROM public.orders
    WHERE restaurant_id = v_demo_id 
      AND created_at < now() - INTERVAL '60 minutes';

    -- 2. Purge non-seed custom products older than 2 hours
    DELETE FROM public.menu_items
    WHERE restaurant_id = v_demo_id 
      AND is_seed = false 
      AND created_at < now() - INTERVAL '2 hours';

    -- 3. Reset seed menu items back to default baseline prices & availability
    UPDATE public.menu_items SET is_available = true WHERE restaurant_id = v_demo_id AND is_seed = true;
    UPDATE public.menu_items SET price_minor = 24000 WHERE id = 'e0000000-0000-0000-0000-000000000001'; -- Velvet Latte
    UPDATE public.menu_items SET price_minor = 18000 WHERE id = 'e0000000-0000-0000-0000-000000000002'; -- House Espresso
    UPDATE public.menu_items SET price_minor = 26000 WHERE id = 'e0000000-0000-0000-0000-000000000003'; -- Cold Brew Reserve
    UPDATE public.menu_items SET price_minor = 21000 WHERE id = 'e0000000-0000-0000-0000-000000000004'; -- Golden Croissant

    -- 4. Clean up expired active demo sessions and rate limits
    DELETE FROM public.demo_sessions WHERE expires_at < now();
    DELETE FROM public.demo_rate_limits WHERE window_start < now() - INTERVAL '30 minutes';

    -- 5. Clean up expired demo memberships and profiles to prevent orphan account accumulation
    DELETE FROM public.restaurant_memberships
    WHERE restaurant_id = v_demo_id
      AND role::text IN ('DEMO_OWNER', 'DEMO_STAFF')
      AND user_id NOT IN (
          SELECT user_id FROM public.demo_sessions WHERE expires_at > now()
      );

    DELETE FROM public.user_profiles
    WHERE id NOT IN (SELECT user_id FROM public.restaurant_memberships)
      AND username LIKE 'demo_%';
END;
$$;

REVOKE ALL ON FUNCTION public.reset_demo_tenant_data FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reset_demo_tenant_data TO service_role;

-- ----------------------------------------------------------------------------
-- 13. Enable Realtime Replication on demo_sessions
-- ----------------------------------------------------------------------------
DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.demo_sessions;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- ----------------------------------------------------------------------------
-- 14. Phase 2 Client Integration: Role Harmonization, Auto-Stamping & Public Tracking
-- ----------------------------------------------------------------------------

-- 14a. Harmonize has_role for Flagship Bistro Demo Roles
CREATE OR REPLACE FUNCTION public.has_role(target_restaurant_id UUID, allowed_roles app_role[])
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public, pg_temp
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
        FROM public.restaurant_memberships
        WHERE restaurant_id = target_restaurant_id
          AND user_id = current_uid
          AND (
            role = ANY(allowed_roles)
            OR (
                target_restaurant_id = 'a0000000-0000-0000-0000-000000000001'
                AND (
                    (role::text = 'DEMO_OWNER' AND (
                        'OWNER'::app_role = ANY(allowed_roles) OR
                        'ADMIN'::app_role = ANY(allowed_roles) OR
                        'CASHIER'::app_role = ANY(allowed_roles) OR
                        'STAFF'::app_role = ANY(allowed_roles) OR
                        'KITCHEN'::app_role = ANY(allowed_roles)
                    ))
                    OR
                    (role::text = 'DEMO_STAFF' AND (
                        'CASHIER'::app_role = ANY(allowed_roles) OR
                        'STAFF'::app_role = ANY(allowed_roles) OR
                        'KITCHEN'::app_role = ANY(allowed_roles)
                    ))
                )
            )
          )
          AND is_active = true
          AND deleted_at IS NULL
    ) INTO has_match;

    RETURN has_match;
END;
$$;

-- 14b. Server-Side Demo Session Auto-Stamping Triggers
CREATE OR REPLACE FUNCTION public.stamp_demo_session_id()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql AS $$
BEGIN
    IF public.is_demo_user() THEN
        IF NEW.demo_session_id IS NULL THEN
            NEW.demo_session_id := public.current_demo_session_id();
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_order_demo_session ON public.orders;
CREATE TRIGGER trg_stamp_order_demo_session
    BEFORE INSERT ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.stamp_demo_session_id();

DROP TRIGGER IF EXISTS trg_stamp_menu_item_demo_session ON public.menu_items;
CREATE TRIGGER trg_stamp_menu_item_demo_session
    BEFORE INSERT ON public.menu_items
    FOR EACH ROW EXECUTE FUNCTION public.stamp_demo_session_id();

-- 14c. Public Order Tracking Policies on Flagship Bistro for Anon
DROP POLICY IF EXISTS "Public can view demo orders" ON public.orders;
CREATE POLICY "Public can view demo orders"
    ON public.orders FOR SELECT
    TO anon
    USING (
        restaurant_id = 'a0000000-0000-0000-0000-000000000001'
    );

DROP POLICY IF EXISTS "Public can view demo order items" ON public.order_items;
CREATE POLICY "Public can view demo order items"
    ON public.order_items FOR SELECT
    TO anon
    USING (
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.id = order_items.order_id
              AND orders.restaurant_id = 'a0000000-0000-0000-0000-000000000001'
        )
    );

-- 14d. Atomic Order Status Tracking Function for Customers
CREATE OR REPLACE FUNCTION public.get_customer_order_status(p_order_id UUID)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_order RECORD;
    v_items JSONB;
BEGIN
    SELECT * INTO v_order
    FROM public.orders
    WHERE id = p_order_id
      AND restaurant_id = 'a0000000-0000-0000-0000-000000000001'
      AND deleted_at IS NULL;

    IF v_order IS NULL THEN
        RAISE EXCEPTION 'Order not found.' USING ERRCODE = '02000';
    END IF;

    SELECT jsonb_agg(
        jsonb_build_object(
            'item_name', item_name,
            'quantity', quantity,
            'unit_price_minor', unit_price_minor,
            'total_price_minor', coalesce(total_price_minor, unit_price_minor * quantity)
        )
    ) INTO v_items
    FROM public.order_items
    WHERE order_id = p_order_id;

    RETURN jsonb_build_object(
        'order_id', v_order.id,
        'order_number', v_order.order_number,
        'status', v_order.status,
        'financial_status', v_order.financial_status,
        'subtotal_minor', v_order.subtotal_minor,
        'tax_minor', v_order.tax_minor,
        'total_minor', v_order.total_minor,
        'table_name', v_order.table_name,
        'order_type', v_order.order_type,
        'created_at', v_order.created_at,
        'updated_at', v_order.updated_at,
        'items', coalesce(v_items, '[]'::jsonb)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_customer_order_status FROM public;
GRANT EXECUTE ON FUNCTION public.get_customer_order_status TO anon, authenticated;

-- 14e. Harmonize create_order_with_items & record_order_payment Authorization for Demo Roles
CREATE OR REPLACE FUNCTION public.create_order_with_items(
    p_restaurant_id UUID,
    p_table_name TEXT,
    p_special_instructions TEXT DEFAULT '',
    p_discount_minor BIGINT DEFAULT 0,
    p_items JSONB DEFAULT '[]'::jsonb,
    p_idempotency_key TEXT DEFAULT NULL,
    p_customer_id UUID DEFAULT NULL,
    p_discount_reason TEXT DEFAULT '',
    p_client_tx_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id UUID;
    v_order_id UUID;
    v_order_number TEXT;
    v_today_seq INT;
    v_subtotal_minor BIGINT := 0;
    v_taxable_minor BIGINT := 0;
    v_tax_rate_bps INT := 500;
    v_tax_name TEXT := 'GST';
    v_tax_is_inclusive BOOLEAN := false;
    v_service_charge_bps INT := 0;
    v_service_charge_minor BIGINT := 0;
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
    v_settings RECORD;
    v_clean_tx_id TEXT;
    v_clean_idempotency TEXT;
BEGIN
    v_caller_id := auth.uid();
    v_clean_tx_id := NULLIF(TRIM(COALESCE(p_client_tx_id, '')), '');
    v_clean_idempotency := NULLIF(TRIM(COALESCE(p_idempotency_key, '')), '');

    -- 1. Idempotency Check
    IF v_clean_tx_id IS NOT NULL THEN
        SELECT id, order_number INTO v_existing_order_id, v_existing_order_number
        FROM public.orders
        WHERE restaurant_id = p_restaurant_id
          AND client_tx_id = v_clean_tx_id;
    END IF;

    IF v_existing_order_id IS NULL AND v_clean_idempotency IS NOT NULL THEN
        SELECT id, order_number INTO v_existing_order_id, v_existing_order_number
        FROM public.orders
        WHERE restaurant_id = p_restaurant_id
          AND idempotency_key = v_clean_idempotency;
    END IF;

    IF v_existing_order_id IS NOT NULL THEN
        SELECT * INTO v_settings FROM public.orders WHERE id = v_existing_order_id;
        RETURN jsonb_build_object(
            'id', v_existing_order_id,
            'order_number', v_existing_order_number,
            'subtotal_minor', v_settings.subtotal_minor,
            'discount_minor', v_settings.discount_minor,
            'tax_minor', v_settings.tax_minor,
            'service_charge_minor', v_settings.service_charge_minor,
            'total_minor', v_settings.total_minor,
            'financial_status', v_settings.financial_status,
            'client_tx_id', v_settings.client_tx_id,
            'version', v_settings.version,
            'idempotent_replay', true
        );
    END IF;

    -- 2. Authorization check (via harmonized has_role)
    IF v_caller_id IS NOT NULL THEN
        IF NOT public.has_role(p_restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role]) THEN
            RAISE EXCEPTION 'Unauthorized: Caller has insufficient role to create customer orders.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 3. Validate items array
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Order validation error: At least one item is required.'
            USING ERRCODE = '22023';
    END IF;

    -- 4. Read authentic restaurant tax and surcharge settings
    SELECT 
        COALESCE(tax_name, 'GST') AS tax_name,
        COALESCE(gst_rate_basis_points, 500) AS gst_rate_basis_points,
        COALESCE(tax_is_inclusive, false) AS tax_is_inclusive,
        COALESCE(service_charge_basis_points, 0) AS service_charge_basis_points
    INTO v_settings
    FROM public.restaurant_settings
    WHERE restaurant_id = p_restaurant_id;

    IF FOUND THEN
        v_tax_name := v_settings.tax_name;
        v_tax_rate_bps := v_settings.gst_rate_basis_points;
        v_tax_is_inclusive := v_settings.tax_is_inclusive;
        v_service_charge_bps := v_settings.service_charge_basis_points;
    END IF;

    -- 5. Calculate line totals and subtotal
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_menu_item_id := (v_item->>'menu_item_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;

        IF v_quantity <= 0 THEN
            RAISE EXCEPTION 'Order validation error: Quantity must be greater than zero.'
                USING ERRCODE = '22023';
        END IF;

        SELECT name, price_minor, is_available, is_archived
        INTO v_item_name, v_unit_price, v_is_available, v_is_archived
        FROM public.menu_items
        WHERE id = v_menu_item_id
          AND restaurant_id = p_restaurant_id
          AND deleted_at IS NULL;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Order validation error: Menu item % not found in this restaurant.', v_menu_item_id
                USING ERRCODE = '22023';
        END IF;

        IF v_is_archived OR NOT v_is_available THEN
            RAISE EXCEPTION 'Order validation error: Item "%" is currently unavailable.', v_item_name
                USING ERRCODE = '22023';
        END IF;

        v_line_total := v_unit_price * v_quantity;
        v_subtotal_minor := v_subtotal_minor + v_line_total;
    END LOOP;

    -- 6. Validate discount
    IF p_discount_minor < 0 THEN
        RAISE EXCEPTION 'Order validation error: Discount cannot be negative.'
            USING ERRCODE = '22023';
    END IF;

    IF p_discount_minor > v_subtotal_minor THEN
        RAISE EXCEPTION 'Order validation error: Discount cannot exceed the subtotal.'
            USING ERRCODE = '22023';
    END IF;

    -- 7. Calculate Tax, Surcharges & Total
    v_taxable_minor := v_subtotal_minor - p_discount_minor;

    IF v_taxable_minor > 0 AND v_service_charge_bps > 0 THEN
        v_service_charge_minor := (v_taxable_minor * v_service_charge_bps + 5000) / 10000;
    END IF;

    IF v_taxable_minor > 0 AND v_tax_rate_bps > 0 THEN
        IF v_tax_is_inclusive THEN
            v_tax_minor := (v_taxable_minor * v_tax_rate_bps) / (10000 + v_tax_rate_bps);
            v_total_minor := v_taxable_minor + v_service_charge_minor;
        ELSE
            v_tax_minor := (v_taxable_minor * v_tax_rate_bps + 5000) / 10000;
            v_total_minor := v_taxable_minor + v_tax_minor + v_service_charge_minor;
        END IF;
    ELSE
        v_tax_minor := 0;
        v_total_minor := v_taxable_minor + v_service_charge_minor;
    END IF;

    -- 8. Generate sequential daily order number
    SELECT COALESCE(MAX(SUBSTRING(order_number FROM 'CF-[0-9]+-([0-9]+)$')::INT), 0) + 1
    INTO v_today_seq
    FROM public.orders
    WHERE restaurant_id = p_restaurant_id
      AND created_at >= CURRENT_DATE::TIMESTAMPTZ;

    v_order_number := 'CF-' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD') || '-' || LPAD(v_today_seq::TEXT, 4, '0');

    -- 9. Insert order record (auto-stamps demo_session_id via trigger if demo user)
    INSERT INTO public.orders (
        restaurant_id,
        order_number,
        table_name,
        special_instructions,
        subtotal_minor,
        discount_minor,
        discount_reason,
        discount_authorized_by,
        tax_name,
        tax_rate_basis_points,
        tax_is_inclusive,
        tax_minor,
        service_charge_minor,
        total_minor,
        paid_amount_minor,
        refunded_amount_minor,
        status,
        financial_status,
        customer_id,
        idempotency_key,
        client_tx_id,
        version,
        sync_status,
        synced_at,
        created_by
    ) VALUES (
        p_restaurant_id,
        v_order_number,
        p_table_name,
        p_special_instructions,
        v_subtotal_minor,
        p_discount_minor,
        p_discount_reason,
        CASE WHEN p_discount_minor > 0 THEN v_caller_id ELSE NULL END,
        v_tax_name,
        v_tax_rate_bps,
        v_tax_is_inclusive,
        v_tax_minor,
        v_service_charge_minor,
        v_total_minor,
        0,
        0,
        'NEW',
        'UNPAID',
        p_customer_id,
        v_clean_idempotency,
        v_clean_tx_id,
        1,
        'SYNCED',
        now(),
        v_caller_id
    ) RETURNING id INTO v_order_id;

    -- 10. Insert order items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_menu_item_id := (v_item->>'menu_item_id')::UUID;
        v_quantity := (v_item->>'quantity')::INT;

        SELECT name, price_minor
        INTO v_item_name, v_unit_price
        FROM public.menu_items
        WHERE id = v_menu_item_id;

        INSERT INTO public.order_items (
            order_id,
            menu_item_id,
            item_name,
            quantity,
            unit_price_minor,
            line_total_minor,
            client_tx_id,
            version
        ) VALUES (
            v_order_id,
            v_menu_item_id,
            v_item_name,
            v_quantity,
            v_unit_price,
            v_unit_price * v_quantity,
            v_clean_tx_id,
            1
        );
    END LOOP;

    RETURN jsonb_build_object(
        'id', v_order_id,
        'order_number', v_order_number,
        'subtotal_minor', v_subtotal_minor,
        'discount_minor', p_discount_minor,
        'tax_minor', v_tax_minor,
        'service_charge_minor', v_service_charge_minor,
        'total_minor', v_total_minor,
        'financial_status', 'UNPAID',
        'client_tx_id', v_clean_tx_id,
        'version', 1,
        'idempotent_replay', false
    );
END;
$$;

REVOKE ALL ON FUNCTION public.create_order_with_items FROM public, anon;
GRANT EXECUTE ON FUNCTION public.create_order_with_items TO authenticated;

CREATE OR REPLACE FUNCTION public.record_order_payment(
    p_restaurant_id UUID,
    p_order_id UUID,
    p_payment_method_code TEXT,
    p_amount_minor BIGINT,
    p_tendered_amount_minor BIGINT DEFAULT NULL,
    p_transaction_reference TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT '',
    p_idempotency_key TEXT DEFAULT NULL,
    p_client_tx_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_id UUID;
    v_order RECORD;
    v_payment_id UUID;
    v_payment_method_id UUID;
    v_change_due_minor BIGINT := 0;
    v_new_paid_total BIGINT;
    v_new_financial_status TEXT;
    v_existing_payment RECORD;
    v_clean_tx_id TEXT;
    v_clean_idempotency TEXT;
BEGIN
    v_caller_id := auth.uid();
    v_clean_tx_id := NULLIF(TRIM(COALESCE(p_client_tx_id, '')), '');
    v_clean_idempotency := NULLIF(TRIM(COALESCE(p_idempotency_key, '')), '');

    -- 1. Idempotency Check
    IF v_clean_tx_id IS NOT NULL THEN
        SELECT * INTO v_existing_payment
        FROM public.payments
        WHERE restaurant_id = p_restaurant_id
          AND client_tx_id = v_clean_tx_id;
    END IF;

    IF v_existing_payment.id IS NULL AND v_clean_idempotency IS NOT NULL THEN
        SELECT * INTO v_existing_payment
        FROM public.payments
        WHERE restaurant_id = p_restaurant_id
          AND idempotency_key = v_clean_idempotency;
    END IF;

    IF v_existing_payment.id IS NOT NULL THEN
        SELECT * INTO v_order FROM public.orders WHERE id = v_existing_payment.order_id;
        RETURN jsonb_build_object(
            'payment_id', v_existing_payment.id,
            'order_id', v_existing_payment.order_id,
            'amount_minor', v_existing_payment.amount_minor,
            'change_due_minor', v_existing_payment.change_due_minor,
            'financial_status', v_order.financial_status,
            'paid_amount_minor', v_order.paid_amount_minor,
            'total_minor', v_order.total_minor,
            'remaining_minor', GREATEST(0, v_order.total_minor - v_order.paid_amount_minor),
            'client_tx_id', v_existing_payment.client_tx_id,
            'is_replay', true
        );
    END IF;

    -- 2. Authorization check (via harmonized has_role)
    IF v_caller_id IS NOT NULL THEN
        IF NOT public.has_role(p_restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role]) THEN
            RAISE EXCEPTION 'Unauthorized: Caller has insufficient role to record customer payments.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 3. Lock target order row FOR UPDATE
    SELECT * INTO v_order
    FROM public.orders
    WHERE id = p_order_id
      AND restaurant_id = p_restaurant_id
      AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order not found in this restaurant.'
            USING ERRCODE = 'P0002';
    END IF;

    -- 4. Amount validation
    IF p_amount_minor <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than zero.'
            USING ERRCODE = '22023';
    END IF;

    IF (v_order.paid_amount_minor + p_amount_minor) > v_order.total_minor THEN
        RAISE EXCEPTION 'Payment amount % exceeds remaining balance %.',
            p_amount_minor, (v_order.total_minor - v_order.paid_amount_minor)
            USING ERRCODE = '22023';
    END IF;

    -- 5. Find payment method
    SELECT id INTO v_payment_method_id
    FROM public.payment_methods
    WHERE restaurant_id = p_restaurant_id
      AND code = UPPER(TRIM(p_payment_method_code))
      AND is_active = TRUE;

    -- 6. Cash Tender & Change Calculations
    IF UPPER(TRIM(p_payment_method_code)) = 'CASH' THEN
        IF p_tendered_amount_minor IS NOT NULL THEN
            IF p_tendered_amount_minor < p_amount_minor THEN
                RAISE EXCEPTION 'Tendered cash % is less than required payment %.',
                    p_tendered_amount_minor, p_amount_minor
                    USING ERRCODE = '22023';
            END IF;
            v_change_due_minor := p_tendered_amount_minor - p_amount_minor;
        END IF;
    END IF;

    -- 7. Insert payment record
    INSERT INTO public.payments (
        restaurant_id,
        order_id,
        payment_method_id,
        payment_method_code,
        amount_minor,
        status,
        tendered_amount_minor,
        change_due_minor,
        transaction_reference,
        notes,
        idempotency_key,
        client_tx_id,
        version,
        sync_status,
        synced_at,
        processed_by,
        processed_at
    ) VALUES (
        p_restaurant_id,
        p_order_id,
        v_payment_method_id,
        UPPER(TRIM(p_payment_method_code)),
        p_amount_minor,
        'COMPLETED',
        p_tendered_amount_minor,
        v_change_due_minor,
        NULLIF(TRIM(COALESCE(p_transaction_reference, '')), ''),
        TRIM(COALESCE(p_notes, '')),
        v_clean_idempotency,
        v_clean_tx_id,
        1,
        'SYNCED',
        now(),
        v_caller_id,
        now()
    ) RETURNING id INTO v_payment_id;

    -- 8. Advance Order Financial Status
    v_new_paid_total := v_order.paid_amount_minor + p_amount_minor;
    IF v_new_paid_total >= v_order.total_minor THEN
        v_new_financial_status := 'PAID';
    ELSE
        v_new_financial_status := 'PARTIALLY_PAID';
    END IF;

    UPDATE public.orders
    SET paid_amount_minor = v_new_paid_total,
        financial_status = v_new_financial_status,
        version = v_order.version + 1,
        updated_at = now()
    WHERE id = p_order_id;

    RETURN jsonb_build_object(
        'payment_id', v_payment_id,
        'order_id', p_order_id,
        'amount_minor', p_amount_minor,
        'change_due_minor', v_change_due_minor,
        'financial_status', v_new_financial_status,
        'paid_amount_minor', v_new_paid_total,
        'total_minor', v_order.total_minor,
        'remaining_minor', GREATEST(0, v_order.total_minor - v_new_paid_total),
        'client_tx_id', v_clean_tx_id,
        'is_replay', false
    );
END;
$$;

REVOKE ALL ON FUNCTION public.record_order_payment FROM public, anon;
GRANT EXECUTE ON FUNCTION public.record_order_payment TO authenticated;

