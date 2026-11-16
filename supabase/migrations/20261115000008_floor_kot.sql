-- ============================================================================
-- CafeFlow Migration: 20261115000008_floor_kot.sql
-- Phase 08: Tables, Floor Management, Dine-In Operations & Kitchen Order Tickets (KOT)
-- ============================================================================

-- 1. Extend table_status enum with operational states
ALTER TYPE public.table_status ADD VALUE IF NOT EXISTS 'BILL_REQUESTED';
ALTER TYPE public.table_status ADD VALUE IF NOT EXISTS 'CLEANING';
ALTER TYPE public.table_status ADD VALUE IF NOT EXISTS 'OUT_OF_SERVICE';

-- ----------------------------------------------------------------------------
-- 2. Floor Sections Table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.floor_sections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT DEFAULT '',
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT unique_restaurant_floor_section UNIQUE (restaurant_id, name)
);

CREATE INDEX IF NOT EXISTS idx_floor_sections_restaurant
    ON public.floor_sections(restaurant_id, sort_order);

ALTER TABLE public.floor_sections ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE TRIGGER trg_floor_sections_updated_at
    BEFORE UPDATE ON public.floor_sections
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ----------------------------------------------------------------------------
-- 3. Kitchen Stations Table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.kitchen_stations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    code TEXT NOT NULL,
    description TEXT DEFAULT '',
    printer_name TEXT DEFAULT '',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT unique_restaurant_kitchen_station UNIQUE (restaurant_id, code)
);

CREATE INDEX IF NOT EXISTS idx_kitchen_stations_restaurant
    ON public.kitchen_stations(restaurant_id, is_active);

ALTER TABLE public.kitchen_stations ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE TRIGGER trg_kitchen_stations_updated_at
    BEFORE UPDATE ON public.kitchen_stations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ----------------------------------------------------------------------------
-- 4. Schema Enhancements: dining_tables
-- ----------------------------------------------------------------------------
ALTER TABLE public.dining_tables ADD COLUMN IF NOT EXISTS section_id UUID REFERENCES public.floor_sections(id) ON DELETE SET NULL;
ALTER TABLE public.dining_tables ADD COLUMN IF NOT EXISTS active_session_id UUID;

CREATE INDEX IF NOT EXISTS idx_dining_tables_section
    ON public.dining_tables(section_id);

-- ----------------------------------------------------------------------------
-- 5. Schema Enhancements: table_sessions
-- ----------------------------------------------------------------------------
ALTER TABLE public.table_sessions ADD COLUMN IF NOT EXISTS restaurant_id UUID REFERENCES public.restaurants(id) ON DELETE CASCADE;
ALTER TABLE public.table_sessions ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'ACTIVE';
ALTER TABLE public.table_sessions ADD COLUMN IF NOT EXISTS current_order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL;
ALTER TABLE public.table_sessions ADD COLUMN IF NOT EXISTS opened_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL;
ALTER TABLE public.table_sessions ADD COLUMN IF NOT EXISTS closed_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL;
ALTER TABLE public.table_sessions ADD COLUMN IF NOT EXISTS notes TEXT DEFAULT '';

-- Populate restaurant_id for any existing table_sessions
UPDATE public.table_sessions ts
SET restaurant_id = dt.restaurant_id
FROM public.dining_tables dt
WHERE ts.table_id = dt.id AND ts.restaurant_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_table_sessions_restaurant_status
    ON public.table_sessions(restaurant_id, status);

-- Partial unique index to enforce that a table CANNOT have two active sessions simultaneously
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_table_session
    ON public.table_sessions(table_id)
    WHERE status = 'ACTIVE';

-- ----------------------------------------------------------------------------
-- 6. Schema Enhancements: orders & order_items
-- ----------------------------------------------------------------------------
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS table_session_id UUID REFERENCES public.table_sessions(id) ON DELETE SET NULL;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_type TEXT NOT NULL DEFAULT 'TAKEAWAY';

CREATE INDEX IF NOT EXISTS idx_orders_table_session
    ON public.orders(table_session_id);

ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS kitchen_station_id UUID REFERENCES public.kitchen_stations(id) ON DELETE SET NULL;
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS kitchen_status TEXT NOT NULL DEFAULT 'NEW';

-- Also add default station reference to menu_items
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS default_kitchen_station_id UUID REFERENCES public.kitchen_stations(id) ON DELETE SET NULL;

-- ----------------------------------------------------------------------------
-- 7. Kitchen Order Tickets (KOT) Table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.kitchen_order_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    table_session_id UUID REFERENCES public.table_sessions(id) ON DELETE SET NULL,
    kot_number TEXT NOT NULL,
    sequence_number INT NOT NULL DEFAULT 1,
    table_name TEXT DEFAULT 'Takeaway',
    station_id UUID REFERENCES public.kitchen_stations(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'NEW', -- NEW, PREPARING, READY, SERVED, CANCELLED
    special_instructions TEXT DEFAULT '',
    client_tx_id TEXT,
    created_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT unique_restaurant_kot_number UNIQUE (restaurant_id, kot_number)
);

CREATE INDEX IF NOT EXISTS idx_kot_restaurant_status
    ON public.kitchen_order_tickets(restaurant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_kot_order_id
    ON public.kitchen_order_tickets(order_id);
CREATE INDEX IF NOT EXISTS idx_kot_station_id
    ON public.kitchen_order_tickets(station_id);

ALTER TABLE public.kitchen_order_tickets ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE TRIGGER trg_kot_updated_at
    BEFORE UPDATE ON public.kitchen_order_tickets
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ----------------------------------------------------------------------------
-- 8. KOT Items Table (Item-Level Kitchen Fulfillment)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.kot_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kot_id UUID NOT NULL REFERENCES public.kitchen_order_tickets(id) ON DELETE CASCADE,
    order_item_id UUID REFERENCES public.order_items(id) ON DELETE SET NULL,
    item_name TEXT NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    selected_variant TEXT,
    selected_addons TEXT[],
    notes TEXT DEFAULT '',
    status TEXT NOT NULL DEFAULT 'NEW', -- NEW, ACCEPTED, PREPARING, READY, SERVED, CANCELLED
    prepared_at TIMESTAMPTZ,
    served_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    cancel_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_kot_items_kot
    ON public.kot_items(kot_id);
CREATE INDEX IF NOT EXISTS idx_kot_items_status
    ON public.kot_items(status);
CREATE INDEX IF NOT EXISTS idx_kot_items_order_item
    ON public.kot_items(order_item_id);

ALTER TABLE public.kot_items ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 9. Table Transfers and Merges Audit Table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.table_transfers_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES public.table_sessions(id) ON DELETE CASCADE,
    source_table_id UUID NOT NULL REFERENCES public.dining_tables(id),
    target_table_id UUID NOT NULL REFERENCES public.dining_tables(id),
    action_type TEXT NOT NULL, -- 'TRANSFER' or 'MERGE'
    notes TEXT DEFAULT '',
    performed_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_table_transfers_restaurant
    ON public.table_transfers_audit(restaurant_id, created_at DESC);

ALTER TABLE public.table_transfers_audit ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 10. ROW LEVEL SECURITY POLICIES
-- ----------------------------------------------------------------------------

-- Floor sections: Read by all tenant roles, modified by Owner/Admin
CREATE POLICY "floor_sections_select_staff"
    ON public.floor_sections FOR SELECT
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role, 'KITCHEN'::app_role]));

CREATE POLICY "floor_sections_modify_admin"
    ON public.floor_sections FOR ALL
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role]))
    WITH CHECK (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role]));

-- Kitchen stations: Read by all tenant roles, modified by Owner/Admin
CREATE POLICY "kitchen_stations_select_staff"
    ON public.kitchen_stations FOR SELECT
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role, 'KITCHEN'::app_role]));

CREATE POLICY "kitchen_stations_modify_admin"
    ON public.kitchen_stations FOR ALL
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role]))
    WITH CHECK (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role]));

-- Dining tables RLS update to allow KITCHEN read-only
CREATE POLICY "dining_tables_select_kitchen"
    ON public.dining_tables FOR SELECT
    USING (has_role(restaurant_id, ARRAY['KITCHEN'::app_role]));

-- Table sessions: Full access for operational staff
DROP POLICY IF EXISTS "table_sessions_staff_all" ON public.table_sessions;
CREATE POLICY "table_sessions_staff_all"
    ON public.table_sessions FOR ALL
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role]))
    WITH CHECK (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role]));

CREATE POLICY "table_sessions_kitchen_read"
    ON public.table_sessions FOR SELECT
    USING (has_role(restaurant_id, ARRAY['KITCHEN'::app_role]));

-- Kitchen Order Tickets: Read by all, updated by operational roles + kitchen
CREATE POLICY "kot_select_tenant"
    ON public.kitchen_order_tickets FOR SELECT
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role, 'KITCHEN'::app_role]));

CREATE POLICY "kot_modify_staff_and_kitchen"
    ON public.kitchen_order_tickets FOR ALL
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role, 'KITCHEN'::app_role]))
    WITH CHECK (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role, 'KITCHEN'::app_role]));

-- KOT Items: Read and modified by staff and kitchen
CREATE POLICY "kot_items_select"
    ON public.kot_items FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.kitchen_order_tickets k
            WHERE k.id = kot_items.kot_id
              AND has_role(k.restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role, 'KITCHEN'::app_role])
        )
    );

CREATE POLICY "kot_items_modify"
    ON public.kot_items FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.kitchen_order_tickets k
            WHERE k.id = kot_items.kot_id
              AND has_role(k.restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role, 'KITCHEN'::app_role])
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.kitchen_order_tickets k
            WHERE k.id = kot_items.kot_id
              AND has_role(k.restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role, 'KITCHEN'::app_role])
        )
    );

-- Table transfers audit
CREATE POLICY "transfers_audit_select"
    ON public.table_transfers_audit FOR SELECT
    USING (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role]));

CREATE POLICY "transfers_audit_insert"
    ON public.table_transfers_audit FOR INSERT
    WITH CHECK (has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role]));

-- ----------------------------------------------------------------------------
-- 11. STORED PROCEDURES & TRANSACTIONAL RPCS
-- ----------------------------------------------------------------------------

-- A. Open a Table Session
CREATE OR REPLACE FUNCTION public.open_table_session(
    p_restaurant_id UUID,
    p_table_id UUID,
    p_guest_count INT DEFAULT 1,
    p_notes TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_table_record RECORD;
    v_session_id UUID;
BEGIN
    IF NOT has_role(p_restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role]) THEN
        RAISE EXCEPTION 'Unauthorized: insufficient permissions to open table session.'
            USING ERRCODE = '42501';
    END IF;

    SELECT id, status, table_number INTO v_table_record
    FROM public.dining_tables
    WHERE id = p_table_id AND restaurant_id = p_restaurant_id AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Table not found.';
    END IF;

    IF v_table_record.status = 'OCCUPIED' THEN
        -- Check if there's already an active session
        SELECT id INTO v_session_id
        FROM public.table_sessions
        WHERE table_id = p_table_id AND status = 'ACTIVE'
        LIMIT 1;

        IF FOUND THEN
            RETURN jsonb_build_object(
                'session_id', v_session_id,
                'table_id', p_table_id,
                'status', 'ALREADY_ACTIVE'
            );
        END IF;
    END IF;

    INSERT INTO public.table_sessions (
        restaurant_id,
        table_id,
        guest_count,
        opened_at,
        status,
        opened_by,
        notes
    ) VALUES (
        p_restaurant_id,
        p_table_id,
        GREATEST(1, p_guest_count),
        now(),
        'ACTIVE',
        auth.uid(),
        p_notes
    )
    RETURNING id INTO v_session_id;

    UPDATE public.dining_tables
    SET status = 'OCCUPIED',
        active_session_id = v_session_id,
        version = version + 1
    WHERE id = p_table_id;

    RETURN jsonb_build_object(
        'session_id', v_session_id,
        'table_id', p_table_id,
        'table_number', v_table_record.table_number,
        'status', 'OPENED'
    );
END;
$$;

-- B. Close Table Session (with Unsettled Order Guard)
CREATE OR REPLACE FUNCTION public.close_table_session(
    p_restaurant_id UUID,
    p_session_id UUID,
    p_force BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session RECORD;
    v_unsettled_count INT;
BEGIN
    IF NOT has_role(p_restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role]) THEN
        RAISE EXCEPTION 'Unauthorized: only cashiers and admins can close table sessions.'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_session
    FROM public.table_sessions
    WHERE id = p_session_id AND restaurant_id = p_restaurant_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Table session not found.';
    END IF;

    IF v_session.status = 'CLOSED' THEN
        RETURN jsonb_build_object('session_id', p_session_id, 'status', 'ALREADY_CLOSED');
    END IF;

    -- Verify all orders for this session are settled
    SELECT COUNT(*) INTO v_unsettled_count
    FROM public.orders
    WHERE table_session_id = p_session_id
      AND financial_status NOT IN ('PAID', 'REFUNDED')
      AND status != 'CANCELLED';

    IF v_unsettled_count > 0 AND NOT p_force THEN
        RAISE EXCEPTION 'Cannot close table session: % order(s) remain unsettled.', v_unsettled_count;
    END IF;

    UPDATE public.table_sessions
    SET status = 'CLOSED',
        closed_at = now(),
        closed_by = auth.uid()
    WHERE id = p_session_id;

    -- Free the dining table
    UPDATE public.dining_tables
    SET status = 'AVAILABLE',
        active_session_id = NULL,
        version = version + 1
    WHERE id = v_session.table_id;

    RETURN jsonb_build_object(
        'session_id', p_session_id,
        'table_id', v_session.table_id,
        'status', 'CLOSED'
    );
END;
$$;

-- C. Transfer Table Session
CREATE OR REPLACE FUNCTION public.transfer_table_session(
    p_restaurant_id UUID,
    p_session_id UUID,
    p_target_table_id UUID,
    p_notes TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session RECORD;
    v_source_table RECORD;
    v_target_table RECORD;
BEGIN
    IF NOT has_role(p_restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role]) THEN
        RAISE EXCEPTION 'Unauthorized.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_session
    FROM public.table_sessions
    WHERE id = p_session_id AND restaurant_id = p_restaurant_id AND status = 'ACTIVE'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active table session not found.';
    END IF;

    SELECT * INTO v_source_table
    FROM public.dining_tables
    WHERE id = v_session.table_id AND restaurant_id = p_restaurant_id
    FOR UPDATE;

    SELECT * INTO v_target_table
    FROM public.dining_tables
    WHERE id = p_target_table_id AND restaurant_id = p_restaurant_id AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target table not found.';
    END IF;

    IF v_target_table.status != 'AVAILABLE' THEN
        RAISE EXCEPTION 'Target table % is not available (current status: %).',
            v_target_table.table_number, v_target_table.status;
    END IF;

    -- Update session
    UPDATE public.table_sessions
    SET table_id = p_target_table_id
    WHERE id = p_session_id;

    -- Free source table
    UPDATE public.dining_tables
    SET status = 'AVAILABLE',
        active_session_id = NULL,
        version = version + 1
    WHERE id = v_source_table.id;

    -- Occupy target table
    UPDATE public.dining_tables
    SET status = 'OCCUPIED',
        active_session_id = p_session_id,
        version = version + 1
    WHERE id = p_target_table_id;

    -- Update active orders table name reference
    UPDATE public.orders
    SET table_id = p_target_table_id,
        table_name = v_target_table.table_number
    WHERE table_session_id = p_session_id;

    -- Audit log
    INSERT INTO public.table_transfers_audit (
        restaurant_id,
        session_id,
        source_table_id,
        target_table_id,
        action_type,
        notes,
        performed_by
    ) VALUES (
        p_restaurant_id,
        p_session_id,
        v_source_table.id,
        p_target_table_id,
        'TRANSFER',
        p_notes,
        auth.uid()
    );

    RETURN jsonb_build_object(
        'session_id', p_session_id,
        'source_table_number', v_source_table.table_number,
        'target_table_number', v_target_table.table_number,
        'status', 'TRANSFERRED'
    );
END;
$$;

-- D. Merge Table Sessions
CREATE OR REPLACE FUNCTION public.merge_table_sessions(
    p_restaurant_id UUID,
    p_source_session_id UUID,
    p_target_session_id UUID,
    p_notes TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_src_session RECORD;
    v_tgt_session RECORD;
BEGIN
    IF NOT has_role(p_restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role]) THEN
        RAISE EXCEPTION 'Unauthorized: only cashiers and admins can merge table sessions.'
            USING ERRCODE = '42501';
    END IF;

    IF p_source_session_id = p_target_session_id THEN
        RAISE EXCEPTION 'Cannot merge a table session into itself.';
    END IF;

    SELECT * INTO v_src_session
    FROM public.table_sessions
    WHERE id = p_source_session_id AND restaurant_id = p_restaurant_id AND status = 'ACTIVE'
    FOR UPDATE;

    SELECT * INTO v_tgt_session
    FROM public.table_sessions
    WHERE id = p_target_session_id AND restaurant_id = p_restaurant_id AND status = 'ACTIVE'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Source or target active table session not found.';
    END IF;

    -- Re-associate source orders to target session
    UPDATE public.orders
    SET table_session_id = p_target_session_id
    WHERE table_session_id = p_source_session_id;

    -- Merge guest counts
    UPDATE public.table_sessions
    SET guest_count = guest_count + v_src_session.guest_count
    WHERE id = p_target_session_id;

    -- Mark source session as merged and closed
    UPDATE public.table_sessions
    SET status = 'MERGED',
        closed_at = now(),
        closed_by = auth.uid()
    WHERE id = p_source_session_id;

    -- Free source dining table
    UPDATE public.dining_tables
    SET status = 'AVAILABLE',
        active_session_id = NULL,
        version = version + 1
    WHERE id = v_src_session.table_id;

    -- Audit log
    INSERT INTO public.table_transfers_audit (
        restaurant_id,
        session_id,
        source_table_id,
        target_table_id,
        action_type,
        notes,
        performed_by
    ) VALUES (
        p_restaurant_id,
        p_target_session_id,
        v_src_session.table_id,
        v_tgt_session.table_id,
        'MERGE',
        p_notes,
        auth.uid()
    );

    RETURN jsonb_build_object(
        'target_session_id', p_target_session_id,
        'source_session_id', p_source_session_id,
        'status', 'MERGED'
    );
END;
$$;

-- E. Create Dine-In or Takeaway Order with Automatic KOT
CREATE OR REPLACE FUNCTION public.create_order_with_kot(
    p_restaurant_id UUID,
    p_table_name TEXT,
    p_table_session_id UUID,
    p_order_type TEXT,
    p_items JSONB,
    p_special_instructions TEXT DEFAULT '',
    p_discount_minor BIGINT DEFAULT 0,
    p_discount_reason TEXT DEFAULT '',
    p_idempotency_key TEXT DEFAULT NULL,
    p_client_tx_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order_id UUID;
    v_order_number TEXT;
    v_subtotal_minor BIGINT := 0;
    v_tax_minor BIGINT := 0;
    v_total_minor BIGINT := 0;
    v_item JSONB;
    v_menu_record RECORD;
    v_item_subtotal BIGINT;
    v_order_item_id UUID;
    v_tax_rate_bps INT := 500;
    v_tax_inclusive BOOLEAN := false;
    v_kot_id UUID;
    v_kot_number TEXT;
    v_kot_seq INT := 1;
    v_target_session_id UUID := p_table_session_id;
    v_table_id UUID;
BEGIN
    IF NOT has_role(p_restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role]) THEN
        RAISE EXCEPTION 'Unauthorized: insufficient role to create orders.' USING ERRCODE = '42501';
    END IF;

    -- Idempotency check
    IF p_client_tx_id IS NOT NULL THEN
        SELECT id, order_number INTO v_order_id, v_order_number
        FROM public.orders
        WHERE restaurant_id = p_restaurant_id AND client_tx_id = p_client_tx_id
        LIMIT 1;

        IF FOUND THEN
            RETURN jsonb_build_object(
                'order_id', v_order_id,
                'order_number', v_order_number,
                'idempotent_replay', true,
                'status', 'EXISTING'
            );
        END IF;
    END IF;

    -- Look up tax settings
    SELECT
        COALESCE(tax_rate_basis_points, 500),
        COALESCE(tax_is_inclusive, false)
    INTO v_tax_rate_bps, v_tax_inclusive
    FROM public.restaurant_settings
    WHERE restaurant_id = p_restaurant_id;

    -- If table session provided, verify and resolve table_id
    IF v_target_session_id IS NOT NULL THEN
        SELECT table_id INTO v_table_id
        FROM public.table_sessions
        WHERE id = v_target_session_id AND restaurant_id = p_restaurant_id AND status = 'ACTIVE';

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Active table session not found.';
        END IF;
    END IF;

    -- Calculate subtotal
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        SELECT id, name, price_minor INTO v_menu_record
        FROM public.menu_items
        WHERE id = (v_item->>'menu_item_id')::UUID
          AND restaurant_id = p_restaurant_id
          AND is_available = true
          AND deleted_at IS NULL;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Item % is unavailable.', (v_item->>'menu_item_id');
        END IF;

        v_item_subtotal := v_menu_record.price_minor * (v_item->>'quantity')::INT;
        v_subtotal_minor := v_subtotal_minor + v_item_subtotal;
    END LOOP;

    -- Tax and Total
    IF v_tax_inclusive THEN
        v_tax_minor := (v_subtotal_minor * v_tax_rate_bps) / (10000 + v_tax_rate_bps);
        v_total_minor := GREATEST(0, v_subtotal_minor - p_discount_minor);
    ELSE
        v_tax_minor := ((v_subtotal_minor - p_discount_minor) * v_tax_rate_bps) / 10000;
        v_total_minor := GREATEST(0, (v_subtotal_minor - p_discount_minor) + v_tax_minor);
    END IF;

    -- Generate order number
    v_order_number := 'ORD-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(FLOOR(random() * 9000 + 1000)::TEXT, 4, '0');

    -- Insert Order
    INSERT INTO public.orders (
        restaurant_id,
        order_number,
        table_id,
        table_name,
        table_session_id,
        order_type,
        status,
        subtotal_minor,
        discount_minor,
        tax_minor,
        total_minor,
        special_instructions,
        client_tx_id,
        created_by
    ) VALUES (
        p_restaurant_id,
        v_order_number,
        v_table_id,
        p_table_name,
        v_target_session_id,
        COALESCE(p_order_type, 'TAKEAWAY'),
        'NEW',
        v_subtotal_minor,
        p_discount_minor,
        v_tax_minor,
        v_total_minor,
        p_special_instructions,
        p_client_tx_id,
        auth.uid()
    ) RETURNING id INTO v_order_id;

    -- Generate KOT number
    v_kot_number := 'KOT-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(FLOOR(random() * 9000 + 1000)::TEXT, 4, '0');

    INSERT INTO public.kitchen_order_tickets (
        restaurant_id,
        order_id,
        table_session_id,
        kot_number,
        sequence_number,
        table_name,
        status,
        special_instructions,
        client_tx_id,
        created_by
    ) VALUES (
        p_restaurant_id,
        v_order_id,
        v_target_session_id,
        v_kot_number,
        v_kot_seq,
        p_table_name,
        'NEW',
        p_special_instructions,
        p_client_tx_id,
        auth.uid()
    ) RETURNING id INTO v_kot_id;

    -- Insert order_items and kot_items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        SELECT id, name, price_minor, default_kitchen_station_id INTO v_menu_record
        FROM public.menu_items
        WHERE id = (v_item->>'menu_item_id')::UUID;

        INSERT INTO public.order_items (
            order_id,
            menu_item_id,
            item_name,
            unit_price_minor,
            quantity,
            total_price_minor,
            kitchen_station_id,
            kitchen_status,
            notes
        ) VALUES (
            v_order_id,
            v_menu_record.id,
            v_menu_record.name,
            v_menu_record.price_minor,
            (v_item->>'quantity')::INT,
            v_menu_record.price_minor * (v_item->>'quantity')::INT,
            v_menu_record.default_kitchen_station_id,
            'NEW',
            COALESCE(v_item->>'notes', '')
        ) RETURNING id INTO v_order_item_id;

        INSERT INTO public.kot_items (
            kot_id,
            order_item_id,
            item_name,
            quantity,
            notes,
            status
        ) VALUES (
            v_kot_id,
            v_order_item_id,
            v_menu_record.name,
            (v_item->>'quantity')::INT,
            COALESCE(v_item->>'notes', ''),
            'NEW'
        );
    END LOOP;

    -- Update table session current order
    IF v_target_session_id IS NOT NULL THEN
        UPDATE public.table_sessions
        SET current_order_id = v_order_id
        WHERE id = v_target_session_id;
    END IF;

    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'order_number', v_order_number,
        'kot_id', v_kot_id,
        'kot_number', v_kot_number,
        'subtotal_minor', v_subtotal_minor,
        'tax_minor', v_tax_minor,
        'total_minor', v_total_minor,
        'status', 'CREATED'
    );
END;
$$;

-- F. Add Items to Existing Open Table Order (Generates Incremental KOT)
CREATE OR REPLACE FUNCTION public.add_items_to_table_order(
    p_restaurant_id UUID,
    p_order_id UUID,
    p_new_items JSONB,
    p_special_instructions TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order RECORD;
    v_item JSONB;
    v_menu_record RECORD;
    v_add_subtotal BIGINT := 0;
    v_add_tax BIGINT := 0;
    v_tax_rate_bps INT := 500;
    v_tax_inclusive BOOLEAN := false;
    v_next_seq INT := 1;
    v_kot_id UUID;
    v_kot_number TEXT;
    v_order_item_id UUID;
BEGIN
    IF NOT has_role(p_restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role]) THEN
        RAISE EXCEPTION 'Unauthorized.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_order
    FROM public.orders
    WHERE id = p_order_id AND restaurant_id = p_restaurant_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order not found.';
    END IF;

    IF v_order.status IN ('COMPLETED', 'CANCELLED') THEN
        RAISE EXCEPTION 'Cannot add items to completed or cancelled order.';
    END IF;

    -- Calculate additional subtotal
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_new_items) LOOP
        SELECT id, name, price_minor INTO v_menu_record
        FROM public.menu_items
        WHERE id = (v_item->>'menu_item_id')::UUID
          AND restaurant_id = p_restaurant_id
          AND is_available = true
          AND deleted_at IS NULL;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Item % is unavailable.', (v_item->>'menu_item_id');
        END IF;

        v_add_subtotal := v_add_subtotal + (v_menu_record.price_minor * (v_item->>'quantity')::INT);
    END LOOP;

    -- Lookup tax settings
    SELECT
        COALESCE(tax_rate_basis_points, 500),
        COALESCE(tax_is_inclusive, false)
    INTO v_tax_rate_bps, v_tax_inclusive
    FROM public.restaurant_settings
    WHERE restaurant_id = p_restaurant_id;

    IF v_tax_inclusive THEN
        v_add_tax := (v_add_subtotal * v_tax_rate_bps) / (10000 + v_tax_rate_bps);
    ELSE
        v_add_tax := (v_add_subtotal * v_tax_rate_bps) / 10000;
    END IF;

    -- Determine next KOT sequence number
    SELECT COALESCE(MAX(sequence_number), 0) + 1 INTO v_next_seq
    FROM public.kitchen_order_tickets
    WHERE order_id = p_order_id;

    v_kot_number := 'KOT-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(FLOOR(random() * 9000 + 1000)::TEXT, 4, '0');

    -- Create incremental KOT
    INSERT INTO public.kitchen_order_tickets (
        restaurant_id,
        order_id,
        table_session_id,
        kot_number,
        sequence_number,
        table_name,
        status,
        special_instructions,
        created_by
    ) VALUES (
        p_restaurant_id,
        p_order_id,
        v_order.table_session_id,
        v_kot_number,
        v_next_seq,
        v_order.table_name,
        'NEW',
        p_special_instructions,
        auth.uid()
    ) RETURNING id INTO v_kot_id;

    -- Insert new items into order_items and kot_items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_new_items) LOOP
        SELECT id, name, price_minor, default_kitchen_station_id INTO v_menu_record
        FROM public.menu_items
        WHERE id = (v_item->>'menu_item_id')::UUID;

        INSERT INTO public.order_items (
            order_id,
            menu_item_id,
            item_name,
            unit_price_minor,
            quantity,
            total_price_minor,
            kitchen_station_id,
            kitchen_status,
            notes
        ) VALUES (
            p_order_id,
            v_menu_record.id,
            v_menu_record.name,
            v_menu_record.price_minor,
            (v_item->>'quantity')::INT,
            v_menu_record.price_minor * (v_item->>'quantity')::INT,
            v_menu_record.default_kitchen_station_id,
            'NEW',
            COALESCE(v_item->>'notes', '')
        ) RETURNING id INTO v_order_item_id;

        INSERT INTO public.kot_items (
            kot_id,
            order_item_id,
            item_name,
            quantity,
            notes,
            status
        ) VALUES (
            v_kot_id,
            v_order_item_id,
            v_menu_record.name,
            (v_item->>'quantity')::INT,
            COALESCE(v_item->>'notes', ''),
            'NEW'
        );
    END LOOP;

    -- Update order financial totals
    UPDATE public.orders
    SET subtotal_minor = subtotal_minor + v_add_subtotal,
        tax_minor = tax_minor + v_add_tax,
        total_minor = total_minor + v_add_subtotal + (CASE WHEN v_tax_inclusive THEN 0 ELSE v_add_tax END),
        updated_at = now()
    WHERE id = p_order_id;

    RETURN jsonb_build_object(
        'order_id', p_order_id,
        'kot_id', v_kot_id,
        'kot_number', v_kot_number,
        'sequence_number', v_next_seq,
        'added_subtotal_minor', v_add_subtotal,
        'added_tax_minor', v_add_tax,
        'status', 'UPDATED'
    );
END;
$$;

-- G. Update KOT Item Status & Cascade to Order Items
CREATE OR REPLACE FUNCTION public.update_kot_item_status(
    p_restaurant_id UUID,
    p_kot_item_id UUID,
    p_status TEXT,
    p_cancel_reason TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_item RECORD;
    v_kot RECORD;
BEGIN
    IF NOT has_role(p_restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role, 'STAFF'::app_role, 'KITCHEN'::app_role]) THEN
        RAISE EXCEPTION 'Unauthorized.' USING ERRCODE = '42501';
    END IF;

    SELECT ki.*, k.restaurant_id, k.order_id, k.id as parent_kot_id INTO v_item
    FROM public.kot_items ki
    JOIN public.kitchen_order_tickets k ON ki.kot_id = k.id
    WHERE ki.id = p_kot_item_id AND k.restaurant_id = p_restaurant_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'KOT item not found.';
    END IF;

    UPDATE public.kot_items
    SET status = p_status,
        prepared_at = CASE WHEN p_status = 'READY' AND prepared_at IS NULL THEN now() ELSE prepared_at END,
        served_at = CASE WHEN p_status = 'SERVED' AND served_at IS NULL THEN now() ELSE served_at END,
        cancelled_at = CASE WHEN p_status = 'CANCELLED' AND cancelled_at IS NULL THEN now() ELSE cancelled_at END,
        cancel_reason = CASE WHEN p_status = 'CANCELLED' THEN p_cancel_reason ELSE cancel_reason END
    WHERE id = p_kot_item_id;

    -- Update linked order_item kitchen_status
    IF v_item.order_item_id IS NOT NULL THEN
        UPDATE public.order_items
        SET kitchen_status = p_status
        WHERE id = v_item.order_item_id;
    END IF;

    RETURN jsonb_build_object(
        'kot_item_id', p_kot_item_id,
        'status', p_status,
        'order_id', v_item.order_id
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 12. ADD TO REALTIME PUBLICATION
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.floor_sections;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.kitchen_stations;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.table_sessions;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.kitchen_order_tickets;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.kot_items;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

