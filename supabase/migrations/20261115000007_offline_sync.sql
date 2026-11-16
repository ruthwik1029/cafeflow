-- ============================================================================
-- CafeFlow Migration: Phase 07 — Offline-First Architecture & Sync
-- Version: 20261115000007
-- Description:
--   1. Schema extensions for offline tracking and entity versioning:
--      - client_tx_id, version, sync_status, synced_at on orders, order_items, payments
--      - version on menu_items, menu_categories, dining_tables, inventory_items
--   2. Unique partial indexes for idempotency and duplicate prevention
--   3. Sync conflicts tracking table (public.sync_conflicts) with RLS
--   4. Sync audit logging table (public.sync_audit_logs) with RLS
--   5. Updated RPC: create_order_with_items (with p_client_tx_id support)
--   6. Updated RPC: record_order_payment (with p_client_tx_id support)
--   7. Batch reconciliation RPC: reconcile_offline_sync_batch
--   8. Realtime publication extensions for sync tracking
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Schema Extensions on Core Tables
-- ----------------------------------------------------------------------------

-- Orders: client transaction ID, versioning and sync tracking
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS client_tx_id TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS sync_status TEXT NOT NULL DEFAULT 'SYNCED';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS synced_at TIMESTAMPTZ DEFAULT now();

-- Unique partial index for client_tx_id per restaurant to prevent duplicate order creations
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_client_tx 
    ON public.orders(restaurant_id, client_tx_id) 
    WHERE client_tx_id IS NOT NULL;

-- Order Items: client transaction ID and versioning
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS client_tx_id TEXT;
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;

-- Payments: client transaction ID, versioning and sync tracking
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS client_tx_id TEXT;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS sync_status TEXT NOT NULL DEFAULT 'SYNCED';
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS synced_at TIMESTAMPTZ DEFAULT now();

-- Unique partial index for client_tx_id per restaurant to prevent duplicate payments
CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_client_tx 
    ON public.payments(restaurant_id, client_tx_id) 
    WHERE client_tx_id IS NOT NULL;

-- Entity versioning for optimistic concurrency and conflict detection
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;
ALTER TABLE public.menu_categories ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;
ALTER TABLE public.dining_tables ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;
ALTER TABLE public.inventory_items ADD COLUMN IF NOT EXISTS version INT NOT NULL DEFAULT 1;

-- ----------------------------------------------------------------------------
-- 2. Synchronization Conflicts Table (public.sync_conflicts)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sync_conflicts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    entity_type TEXT NOT NULL, -- 'ORDER', 'PAYMENT', 'INVENTORY', 'MENU', 'TABLE'
    entity_id TEXT NOT NULL,
    client_tx_id TEXT,
    client_version INT DEFAULT 1,
    server_version INT DEFAULT 1,
    conflict_reason TEXT NOT NULL,
    client_payload JSONB NOT NULL,
    server_payload JSONB,
    status TEXT NOT NULL DEFAULT 'PENDING_REVIEW', -- 'PENDING_REVIEW', 'RESOLVED_SERVER_WINS', 'RESOLVED_CLIENT_WINS', 'DISMISSED'
    resolved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    resolved_at TIMESTAMPTZ,
    resolution_notes TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sync_conflicts_restaurant_status 
    ON public.sync_conflicts(restaurant_id, status, created_at DESC);

-- Enable RLS
ALTER TABLE public.sync_conflicts ENABLE ROW LEVEL SECURITY;

-- RLS: Read restricted to restaurant members with elevated role (OWNER, ADMIN, CASHIER)
CREATE POLICY "sync_conflicts_select_policy"
    ON public.sync_conflicts
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.restaurant_memberships m
            WHERE m.restaurant_id = sync_conflicts.restaurant_id
              AND m.user_id = auth.uid()
              AND m.is_active = TRUE
              AND m.deleted_at IS NULL
              AND m.role IN ('OWNER', 'ADMIN', 'CASHIER')
        )
    );

-- RLS: Updates (resolutions) restricted strictly to OWNER and ADMIN
CREATE POLICY "sync_conflicts_update_policy"
    ON public.sync_conflicts
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.restaurant_memberships m
            WHERE m.restaurant_id = sync_conflicts.restaurant_id
              AND m.user_id = auth.uid()
              AND m.is_active = TRUE
              AND m.deleted_at IS NULL
              AND m.role IN ('OWNER', 'ADMIN')
        )
    );

-- ----------------------------------------------------------------------------
-- 3. Synchronization Audit Logs Table (public.sync_audit_logs)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sync_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL DEFAULT 'unknown',
    batch_id TEXT,
    client_tx_id TEXT,
    operation_type TEXT NOT NULL, -- 'CREATE_ORDER', 'RECORD_PAYMENT', 'UPDATE_STATUS', etc.
    status TEXT NOT NULL, -- 'ACKNOWLEDGED', 'REPLAYED', 'CONFLICT', 'REJECTED'
    details JSONB DEFAULT '{}'::jsonb,
    processed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sync_audit_logs_restaurant 
    ON public.sync_audit_logs(restaurant_id, created_at DESC);

-- Enable RLS
ALTER TABLE public.sync_audit_logs ENABLE ROW LEVEL SECURITY;

-- RLS: Read restricted to authenticated restaurant members
CREATE POLICY "sync_audit_logs_select_policy"
    ON public.sync_audit_logs
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.restaurant_memberships m
            WHERE m.restaurant_id = sync_audit_logs.restaurant_id
              AND m.user_id = auth.uid()
              AND m.is_active = TRUE
              AND m.deleted_at IS NULL
        )
    );

-- ----------------------------------------------------------------------------
-- 4. Updated Order Creation RPC: create_order_with_items
-- ----------------------------------------------------------------------------
-- Extends create_order_with_items with p_client_tx_id for idempotency and offline sync
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
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role TEXT;
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

    -- 1. Idempotency Check: By client_tx_id OR idempotency_key
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

    -- If order already recorded, replay the original result safely
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

    -- 2. Authorization check
    IF v_caller_id IS NOT NULL THEN
        SELECT role INTO v_caller_role
        FROM public.restaurant_memberships
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_caller_id
          AND is_active = TRUE
          AND deleted_at IS NULL;

        IF v_caller_role IS NULL THEN
            RAISE EXCEPTION 'Unauthorized: Caller has no active membership in this restaurant.'
                USING ERRCODE = '42501';
        END IF;

        IF v_caller_role NOT IN ('OWNER', 'ADMIN', 'CASHIER', 'STAFF') THEN
            RAISE EXCEPTION 'Unauthorized: Role % cannot create customer orders.', v_caller_role
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

        -- Verify item exists in this restaurant
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
            -- Embedded tax extraction
            v_tax_minor := (v_taxable_minor * v_tax_rate_bps) / (10000 + v_tax_rate_bps);
            v_total_minor := v_taxable_minor + v_service_charge_minor;
        ELSE
            -- Add-on exclusive tax
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

    -- 9. Insert order record
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

    -- 10. Insert order items with snapshots
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

    -- 11. Write audit log
    INSERT INTO public.audit_logs (
        restaurant_id,
        actor_id,
        action,
        entity_type,
        entity_id,
        payload
    ) VALUES (
        p_restaurant_id,
        v_caller_id,
        'ORDER_CREATED',
        'orders',
        v_order_id,
        jsonb_build_object(
            'order_number', v_order_number,
            'total_minor', v_total_minor,
            'client_tx_id', v_clean_tx_id,
            'items_count', jsonb_array_length(p_items)
        )
    );

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

GRANT EXECUTE ON FUNCTION public.create_order_with_items TO authenticated, anon;

-- ----------------------------------------------------------------------------
-- 5. Updated Payment Recording RPC: record_order_payment
-- ----------------------------------------------------------------------------
-- Extends record_order_payment with p_client_tx_id for offline payment settlement
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
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role TEXT;
    v_order RECORD;
    v_payment_method_id UUID;
    v_change_due_minor BIGINT := 0;
    v_payment_id UUID;
    v_new_paid_total BIGINT;
    v_new_financial_status order_financial_status;
    v_existing_payment RECORD;
    v_clean_tx_id TEXT;
    v_clean_idempotency TEXT;
BEGIN
    v_caller_id := auth.uid();
    v_clean_tx_id := NULLIF(TRIM(COALESCE(p_client_tx_id, '')), '');
    v_clean_idempotency := NULLIF(TRIM(COALESCE(p_idempotency_key, '')), '');

    -- 1. Idempotency Check: By client_tx_id OR idempotency_key
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

    -- If payment already processed, return existing record
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

    -- 2. Authorization check
    IF v_caller_id IS NOT NULL THEN
        SELECT role INTO v_caller_role
        FROM public.restaurant_memberships
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_caller_id
          AND is_active = TRUE
          AND deleted_at IS NULL;

        IF v_caller_role IS NULL THEN
            RAISE EXCEPTION 'Unauthorized: Caller has no active membership in this restaurant.'
                USING ERRCODE = '42501';
        END IF;

        IF v_caller_role NOT IN ('OWNER', 'ADMIN', 'CASHIER') THEN
            RAISE EXCEPTION 'Unauthorized: Role % cannot record customer payments.', v_caller_role
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

    -- 9. Write audit log
    INSERT INTO public.audit_logs (
        restaurant_id,
        actor_id,
        action,
        entity_type,
        entity_id,
        payload
    ) VALUES (
        p_restaurant_id,
        v_caller_id,
        'PAYMENT_RECORDED',
        'payments',
        v_payment_id,
        jsonb_build_object(
            'order_id', p_order_id,
            'amount_minor', p_amount_minor,
            'method', UPPER(TRIM(p_payment_method_code)),
            'change_due_minor', v_change_due_minor,
            'client_tx_id', v_clean_tx_id,
            'new_financial_status', v_new_financial_status
        )
    );

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

GRANT EXECUTE ON FUNCTION public.record_order_payment TO authenticated, anon;

-- ----------------------------------------------------------------------------
-- 6. Batch Offline Reconciliation RPC: reconcile_offline_sync_batch
-- ----------------------------------------------------------------------------
-- Safely processes a batch of queued operations from an offline station,
-- verifying membership, preventing duplicate records, and tracking conflicts.
CREATE OR REPLACE FUNCTION public.reconcile_offline_sync_batch(
    p_restaurant_id UUID,
    p_device_id TEXT,
    p_operations JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role TEXT;
    v_op JSONB;
    v_op_type TEXT;
    v_client_tx_id TEXT;
    v_payload JSONB;
    v_result JSONB;
    v_acknowledged JSONB := '[]'::jsonb;
    v_replayed JSONB := '[]'::jsonb;
    v_conflicted JSONB := '[]'::jsonb;
    v_failed JSONB := '[]'::jsonb;
BEGIN
    v_caller_id := auth.uid();

    -- Authorization check
    IF v_caller_id IS NOT NULL THEN
        SELECT role INTO v_caller_role
        FROM public.restaurant_memberships
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_caller_id
          AND is_active = TRUE
          AND deleted_at IS NULL;

        IF v_caller_role IS NULL THEN
            RAISE EXCEPTION 'Unauthorized: Caller has no active membership in this restaurant.'
                USING ERRCODE = '42501';
        END IF;

        IF v_caller_role NOT IN ('OWNER', 'ADMIN', 'CASHIER', 'STAFF') THEN
            RAISE EXCEPTION 'Unauthorized: Role % cannot sync offline operations.', v_caller_role
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- Process each queued operation in dependency order
    FOR v_op IN SELECT * FROM jsonb_array_elements(p_operations)
    LOOP
        v_op_type := v_op->>'operation_type';
        v_client_tx_id := v_op->>'client_tx_id';
        v_payload := v_op->'payload';

        BEGIN
            IF v_op_type = 'CREATE_ORDER' THEN
                v_result := public.create_order_with_items(
                    p_restaurant_id,
                    COALESCE(v_payload->>'table_name', 'Takeaway'),
                    COALESCE(v_payload->>'special_instructions', ''),
                    COALESCE((v_payload->>'discount_minor')::BIGINT, 0),
                    COALESCE(v_payload->'items', '[]'::jsonb),
                    v_payload->>'idempotency_key',
                    (v_payload->>'customer_id')::UUID,
                    COALESCE(v_payload->>'discount_reason', ''),
                    v_client_tx_id
                );

                IF (v_result->>'idempotent_replay')::BOOLEAN THEN
                    v_replayed := v_replayed || jsonb_build_object('client_tx_id', v_client_tx_id, 'result', v_result);
                ELSE
                    v_acknowledged := v_acknowledged || jsonb_build_object('client_tx_id', v_client_tx_id, 'result', v_result);
                END IF;

            ELSIF v_op_type = 'RECORD_PAYMENT' THEN
                -- Locate parent order if specified by client_tx_id
                DECLARE
                    v_target_order_id UUID := (v_payload->>'order_id')::UUID;
                    v_parent_tx_id TEXT := v_payload->>'parent_order_tx_id';
                BEGIN
                    IF v_target_order_id IS NULL AND v_parent_tx_id IS NOT NULL THEN
                        SELECT id INTO v_target_order_id
                        FROM public.orders
                        WHERE restaurant_id = p_restaurant_id
                          AND client_tx_id = v_parent_tx_id;
                    END IF;

                    IF v_target_order_id IS NULL THEN
                        RAISE EXCEPTION 'Parent order not found for offline payment sync.';
                    END IF;

                    v_result := public.record_order_payment(
                        p_restaurant_id,
                        v_target_order_id,
                        v_payload->>'payment_method_code',
                        (v_payload->>'amount_minor')::BIGINT,
                        (v_payload->>'tendered_amount_minor')::BIGINT,
                        v_payload->>'transaction_reference',
                        COALESCE(v_payload->>'notes', ''),
                        v_payload->>'idempotency_key',
                        v_client_tx_id
                    );

                    IF (v_result->>'is_replay')::BOOLEAN THEN
                        v_replayed := v_replayed || jsonb_build_object('client_tx_id', v_client_tx_id, 'result', v_result);
                    ELSE
                        v_acknowledged := v_acknowledged || jsonb_build_object('client_tx_id', v_client_tx_id, 'result', v_result);
                    END IF;
                END;

            ELSE
                RAISE EXCEPTION 'Unsupported operation type: %', v_op_type;
            END IF;

        EXCEPTION WHEN OTHERS THEN
            -- Record conflict or failure
            INSERT INTO public.sync_conflicts (
                restaurant_id,
                entity_type,
                entity_id,
                client_tx_id,
                conflict_reason,
                client_payload,
                status
            ) VALUES (
                p_restaurant_id,
                v_op_type,
                COALESCE(v_client_tx_id, 'unknown'),
                v_client_tx_id,
                SQLERRM,
                v_payload,
                'PENDING_REVIEW'
            );

            v_conflicted := v_conflicted || jsonb_build_object(
                'client_tx_id', v_client_tx_id,
                'error', SQLERRM
            );
        END;
    END LOOP;

    -- Write audit log of batch synchronization
    INSERT INTO public.sync_audit_logs (
        restaurant_id,
        device_id,
        operation_type,
        status,
        details,
        processed_by
    ) VALUES (
        p_restaurant_id,
        p_device_id,
        'BATCH_SYNC',
        'PROCESSED',
        jsonb_build_object(
            'acknowledged_count', jsonb_array_length(v_acknowledged),
            'replayed_count', jsonb_array_length(v_replayed),
            'conflicted_count', jsonb_array_length(v_conflicted)
        ),
        v_caller_id
    );

    RETURN jsonb_build_object(
        'acknowledged', v_acknowledged,
        'replayed', v_replayed,
        'conflicted', v_conflicted,
        'success', (jsonb_array_length(v_conflicted) = 0)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.reconcile_offline_sync_batch TO authenticated, anon;

-- ----------------------------------------------------------------------------
-- 7. Realtime Publication Extensions
-- ----------------------------------------------------------------------------
DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sync_conflicts;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

