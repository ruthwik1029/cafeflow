-- ============================================================================
-- CafeFlow Phase 06 Migration: Payment Processing, Billing & Financial Workflows
-- Version: 20261115000006
-- Scope:
--   1. Financial status ENUM & order payment tracking
--   2. Tax & Service Charge configuration in restaurant_settings
--   3. Enhanced payments table & refunds table
--   4. RLS policies for payments & refunds
--   5. Transactional RPC: record_order_payment
--   6. Transactional RPC: refund_order_payment
--   7. Transactional RPC: update_payment_method_status
--   8. Updated RPC: create_order_with_items (inclusive/exclusive tax & service charges)
--   9. Transactional RPC: get_financial_report
--  10. Realtime publication additions for payments and refunds
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Financial Status ENUM & Order Extensions
-- ----------------------------------------------------------------------------
DO $$ BEGIN
    CREATE TYPE order_financial_status AS ENUM (
        'UNPAID',
        'PARTIALLY_PAID',
        'PAID',
        'REFUNDED',
        'PARTIALLY_REFUNDED',
        'PAYMENT_FAILED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- Add financial tracking and snapshot columns to orders
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS financial_status order_financial_status NOT NULL DEFAULT 'UNPAID';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS paid_amount_minor BIGINT NOT NULL DEFAULT 0 CHECK (paid_amount_minor >= 0);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS refunded_amount_minor BIGINT NOT NULL DEFAULT 0 CHECK (refunded_amount_minor >= 0);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS tax_name TEXT DEFAULT 'GST';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS tax_rate_basis_points INT DEFAULT 500;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS tax_is_inclusive BOOLEAN DEFAULT false;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS service_charge_minor BIGINT DEFAULT 0 CHECK (service_charge_minor >= 0);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS discount_reason TEXT DEFAULT '';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS discount_authorized_by UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_orders_financial_status ON orders(restaurant_id, financial_status, created_at DESC);

-- ----------------------------------------------------------------------------
-- 2. Restaurant Settings Extensions for Tax & Additional Charges
-- ----------------------------------------------------------------------------
ALTER TABLE public.restaurant_settings ADD COLUMN IF NOT EXISTS tax_name TEXT NOT NULL DEFAULT 'GST';
ALTER TABLE public.restaurant_settings ADD COLUMN IF NOT EXISTS tax_is_inclusive BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.restaurant_settings ADD COLUMN IF NOT EXISTS service_charge_basis_points INT NOT NULL DEFAULT 0 CHECK (service_charge_basis_points >= 0);
ALTER TABLE public.restaurant_settings ADD COLUMN IF NOT EXISTS service_charge_name TEXT NOT NULL DEFAULT 'Service Charge';

-- ----------------------------------------------------------------------------
-- 3. Payments Table Enhancements & Refunds Table
-- ----------------------------------------------------------------------------
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS restaurant_id UUID REFERENCES restaurants(id) ON DELETE CASCADE;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS processed_by UUID REFERENCES user_profiles(id) ON DELETE SET NULL;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS tendered_amount_minor BIGINT CHECK (tendered_amount_minor >= 0);
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS change_due_minor BIGINT DEFAULT 0 CHECK (change_due_minor >= 0);
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS notes TEXT DEFAULT '';
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS is_refunded BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS refunded_amount_minor BIGINT NOT NULL DEFAULT 0 CHECK (refunded_amount_minor >= 0);
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

-- Backfill restaurant_id on payments from orders where missing
UPDATE public.payments p
SET restaurant_id = o.restaurant_id
FROM public.orders o
WHERE p.order_id = o.id
  AND p.restaurant_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_payments_restaurant_created ON payments(restaurant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(restaurant_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_idempotency 
    ON payments(restaurant_id, idempotency_key) 
    WHERE idempotency_key IS NOT NULL;

-- Create Refunds Table
CREATE TABLE IF NOT EXISTS public.refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
    payment_id UUID NOT NULL REFERENCES payments(id) ON DELETE RESTRICT,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    reason TEXT NOT NULL,
    refunded_by UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
    refunded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    idempotency_key TEXT,
    CONSTRAINT unique_refund_idempotency UNIQUE (restaurant_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_refunds_restaurant ON refunds(restaurant_id, refunded_at DESC);
CREATE INDEX IF NOT EXISTS idx_refunds_order ON refunds(order_id);
CREATE INDEX IF NOT EXISTS idx_refunds_payment ON refunds(payment_id);

-- ----------------------------------------------------------------------------
-- 4. Row Level Security for Payments & Refunds
-- ----------------------------------------------------------------------------
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;

-- Drop prior payments policies to establish clean, role-checked boundaries
DROP POLICY IF EXISTS "Cashiers and Admins can view payments" ON payments;
DROP POLICY IF EXISTS "Cashiers can record payments" ON payments;
DROP POLICY IF EXISTS "payments_select_policy" ON payments;
DROP POLICY IF EXISTS "payments_insert_policy" ON payments;

-- Payments: Only Cashier, Admin, Owner can view payments of their restaurant
CREATE POLICY "payments_select_policy" ON public.payments
FOR SELECT TO authenticated
USING (
    has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role])
);

-- Payments: Cashier, Admin, Owner can insert payments
CREATE POLICY "payments_insert_policy" ON public.payments
FOR INSERT TO authenticated
WITH CHECK (
    has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role, 'CASHIER'::app_role])
);

-- Payments: Immutability guard - no direct client updates or deletes permitted
-- (All mutations occur via SECURITY DEFINER RPCs)

-- Refunds: Only Owner and Admin can view refunds
CREATE POLICY "refunds_select_policy" ON public.refunds
FOR SELECT TO authenticated
USING (
    has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role])
);

-- Refunds: Only Owner and Admin can insert refunds
CREATE POLICY "refunds_insert_policy" ON public.refunds
FOR INSERT TO authenticated
WITH CHECK (
    has_role(restaurant_id, ARRAY['OWNER'::app_role, 'ADMIN'::app_role])
);

-- ----------------------------------------------------------------------------
-- 5. Transactional RPC: record_order_payment
-- ----------------------------------------------------------------------------
-- Records a payment against an order with balance checks, cash change calculations,
-- idempotency protection, and automatic financial status progression.
CREATE OR REPLACE FUNCTION public.record_order_payment(
    p_restaurant_id UUID,
    p_order_id UUID,
    p_payment_method_code TEXT,
    p_amount_minor BIGINT,
    p_tendered_amount_minor BIGINT DEFAULT NULL,
    p_transaction_reference TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT '',
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role app_role;
    v_order RECORD;
    v_payment_id UUID;
    v_existing_payment RECORD;
    v_method_record RECORD;
    v_outstanding_minor BIGINT;
    v_new_paid_minor BIGINT;
    v_change_due_minor BIGINT := 0;
    v_new_financial_status order_financial_status;
    v_clean_code TEXT;
BEGIN
    v_caller_id := auth.uid();
    v_clean_code := UPPER(TRIM(p_payment_method_code));

    -- 1. Authentication & Role Authorization Check
    IF v_caller_id IS NOT NULL THEN
        SELECT role INTO v_caller_role
        FROM public.restaurant_memberships
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_caller_id
          AND is_active = TRUE
          AND deleted_at IS NULL;

        IF v_caller_role IS NULL OR v_caller_role NOT IN ('OWNER', 'ADMIN', 'CASHIER') THEN
            RAISE EXCEPTION 'Unauthorized: Role cannot record payments.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 2. Idempotency Check
    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) != '' THEN
        SELECT id, amount_minor, status, change_due_minor INTO v_existing_payment
        FROM public.payments
        WHERE restaurant_id = p_restaurant_id
          AND idempotency_key = TRIM(p_idempotency_key);

        IF v_existing_payment.id IS NOT NULL THEN
            SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
            RETURN jsonb_build_object(
                'payment_id', v_existing_payment.id,
                'order_id', p_order_id,
                'amount_minor', v_existing_payment.amount_minor,
                'change_due_minor', v_existing_payment.change_due_minor,
                'financial_status', v_order.financial_status,
                'paid_amount_minor', v_order.paid_amount_minor,
                'total_minor', v_order.total_minor,
                'idempotent_replay', true
            );
        END IF;
    END IF;

    -- 3. Lock & Retrieve Order
    SELECT * INTO v_order
    FROM public.orders
    WHERE id = p_order_id
      AND restaurant_id = p_restaurant_id
      AND deleted_at IS NULL
    FOR UPDATE;

    IF v_order.id IS NULL THEN
        RAISE EXCEPTION 'Order % does not exist in this restaurant.', p_order_id
            USING ERRCODE = '02000';
    END IF;

    IF v_order.status = 'CANCELLED'::public.order_status THEN
        RAISE EXCEPTION 'Cannot record payment for a cancelled order.'
            USING ERRCODE = '22023';
    END IF;

    IF v_order.financial_status = 'PAID'::public.order_financial_status THEN
        RAISE EXCEPTION 'Order is already fully paid.'
            USING ERRCODE = '22023';
    END IF;

    IF v_order.financial_status = 'REFUNDED'::public.order_financial_status THEN
        RAISE EXCEPTION 'Cannot record payment for a refunded order.'
            USING ERRCODE = '22023';
    END IF;

    -- 4. Validate Payment Method
    SELECT id, is_active INTO v_method_record
    FROM public.payment_methods
    WHERE restaurant_id = p_restaurant_id
      AND UPPER(code) = v_clean_code;

    IF v_method_record.id IS NOT NULL AND NOT v_method_record.is_active THEN
        RAISE EXCEPTION 'Payment method % is currently disabled for this restaurant.', v_clean_code
            USING ERRCODE = '22023';
    END IF;

    -- 5. Validate Financial Amounts
    IF p_amount_minor <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than zero.'
            USING ERRCODE = '22023';
    END IF;

    v_outstanding_minor := v_order.total_minor - v_order.paid_amount_minor;

    IF p_amount_minor > v_outstanding_minor THEN
        RAISE EXCEPTION 'Payment amount (% minor) exceeds outstanding balance (% minor).',
            p_amount_minor, v_outstanding_minor
            USING ERRCODE = '22023';
    END IF;

    -- 6. Cash Handling & Change Calculation
    IF v_clean_code = 'CASH' THEN
        IF p_tendered_amount_minor IS NOT NULL THEN
            IF p_tendered_amount_minor < p_amount_minor THEN
                RAISE EXCEPTION 'Tendered amount (% minor) cannot be less than payment amount (% minor).',
                    p_tendered_amount_minor, p_amount_minor
                    USING ERRCODE = '22023';
            END IF;
            v_change_due_minor := p_tendered_amount_minor - p_amount_minor;
        ELSE
            -- Default tendered to exact amount
            p_tendered_amount_minor := p_amount_minor;
            v_change_due_minor := 0;
        END IF;
    END IF;

    -- 7. Insert Payment Record
    INSERT INTO public.payments (
        restaurant_id,
        order_id,
        payment_method_id,
        payment_method_code,
        amount_minor,
        status,
        transaction_reference,
        tendered_amount_minor,
        change_due_minor,
        notes,
        processed_by,
        processed_at,
        idempotency_key
    ) VALUES (
        p_restaurant_id,
        p_order_id,
        v_method_record.id,
        v_clean_code,
        p_amount_minor,
        'COMPLETED'::public.payment_status,
        NULLIF(TRIM(COALESCE(p_transaction_reference, '')), ''),
        p_tendered_amount_minor,
        v_change_due_minor,
        COALESCE(p_notes, ''),
        v_caller_id,
        now(),
        NULLIF(TRIM(COALESCE(p_idempotency_key, '')), '')
    ) RETURNING id INTO v_payment_id;

    -- 8. Compute New Financial Status & Update Order
    v_new_paid_minor := v_order.paid_amount_minor + p_amount_minor;

    IF v_new_paid_minor >= v_order.total_minor THEN
        v_new_financial_status := 'PAID'::public.order_financial_status;
    ELSE
        v_new_financial_status := 'PARTIALLY_PAID'::public.order_financial_status;
    END IF;

    UPDATE public.orders
    SET paid_amount_minor = v_new_paid_minor,
        financial_status = v_new_financial_status,
        updated_at = now()
    WHERE id = p_order_id;

    -- 9. Audit Log
    INSERT INTO public.audit_logs (
        restaurant_id,
        actor_id,
        action,
        target_entity,
        target_id,
        details
    ) VALUES (
        p_restaurant_id,
        v_caller_id,
        'RECORD_PAYMENT',
        'payments',
        v_payment_id,
        jsonb_build_object(
            'order_id', p_order_id,
            'payment_method', v_clean_code,
            'amount_minor', p_amount_minor,
            'tendered_minor', p_tendered_amount_minor,
            'change_due_minor', v_change_due_minor,
            'new_financial_status', v_new_financial_status,
            'reference', p_transaction_reference
        )
    );

    RETURN jsonb_build_object(
        'payment_id', v_payment_id,
        'order_id', p_order_id,
        'amount_minor', p_amount_minor,
        'change_due_minor', v_change_due_minor,
        'financial_status', v_new_financial_status,
        'paid_amount_minor', v_new_paid_minor,
        'total_minor', v_order.total_minor,
        'remaining_minor', v_order.total_minor - v_new_paid_minor,
        'idempotent_replay', false
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_order_payment TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. Transactional RPC: refund_order_payment
-- ----------------------------------------------------------------------------
-- Authorizes Owner and Admin to issue full or partial refunds against settled payments.
CREATE OR REPLACE FUNCTION public.refund_order_payment(
    p_restaurant_id UUID,
    p_order_id UUID,
    p_payment_id UUID,
    p_refund_amount_minor BIGINT,
    p_reason TEXT,
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role app_role;
    v_order RECORD;
    v_payment RECORD;
    v_refund_id UUID;
    v_existing_refund RECORD;
    v_refundable_on_payment BIGINT;
    v_new_payment_refunded BIGINT;
    v_new_order_refunded BIGINT;
    v_new_financial_status order_financial_status;
BEGIN
    v_caller_id := auth.uid();

    -- 1. Role Authorization Check: OWNER or ADMIN only
    IF v_caller_id IS NOT NULL THEN
        SELECT role INTO v_caller_role
        FROM public.restaurant_memberships
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_caller_id
          AND is_active = TRUE
          AND deleted_at IS NULL;

        IF v_caller_role IS NULL OR v_caller_role NOT IN ('OWNER', 'ADMIN') THEN
            RAISE EXCEPTION 'Unauthorized: Only Owners and Admins can process refunds.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 2. Idempotency Check
    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) != '' THEN
        SELECT id, amount_minor INTO v_existing_refund
        FROM public.refunds
        WHERE restaurant_id = p_restaurant_id
          AND idempotency_key = TRIM(p_idempotency_key);

        IF v_existing_refund.id IS NOT NULL THEN
            SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
            RETURN jsonb_build_object(
                'refund_id', v_existing_refund.id,
                'payment_id', p_payment_id,
                'order_id', p_order_id,
                'refund_amount_minor', v_existing_refund.amount_minor,
                'financial_status', v_order.financial_status,
                'idempotent_replay', true
            );
        END IF;
    END IF;

    -- 3. Validate Reason & Amount
    IF TRIM(COALESCE(p_reason, '')) = '' THEN
        RAISE EXCEPTION 'A valid refund reason is required.'
            USING ERRCODE = '22023';
    END IF;

    IF p_refund_amount_minor <= 0 THEN
        RAISE EXCEPTION 'Refund amount must be greater than zero.'
            USING ERRCODE = '22023';
    END IF;

    -- 4. Lock & Verify Order
    SELECT * INTO v_order
    FROM public.orders
    WHERE id = p_order_id
      AND restaurant_id = p_restaurant_id
      AND deleted_at IS NULL
    FOR UPDATE;

    IF v_order.id IS NULL THEN
        RAISE EXCEPTION 'Order % does not exist.', p_order_id
            USING ERRCODE = '02000';
    END IF;

    -- 5. Lock & Verify Payment
    SELECT * INTO v_payment
    FROM public.payments
    WHERE id = p_payment_id
      AND order_id = p_order_id
      AND restaurant_id = p_restaurant_id
    FOR UPDATE;

    IF v_payment.id IS NULL THEN
        RAISE EXCEPTION 'Payment % does not exist for this order.', p_payment_id
            USING ERRCODE = '02000';
    END IF;

    IF v_payment.status != 'COMPLETED'::public.payment_status THEN
        RAISE EXCEPTION 'Cannot refund an incomplete or failed payment.'
            USING ERRCODE = '22023';
    END IF;

    v_refundable_on_payment := v_payment.amount_minor - v_payment.refunded_amount_minor;

    IF p_refund_amount_minor > v_refundable_on_payment THEN
        RAISE EXCEPTION 'Refund amount (% minor) exceeds remaining refundable amount on payment (% minor).',
            p_refund_amount_minor, v_refundable_on_payment
            USING ERRCODE = '22023';
    END IF;

    -- 6. Insert Refund Record
    INSERT INTO public.refunds (
        restaurant_id,
        order_id,
        payment_id,
        amount_minor,
        reason,
        refunded_by,
        refunded_at,
        idempotency_key
    ) VALUES (
        p_restaurant_id,
        p_order_id,
        p_payment_id,
        p_refund_amount_minor,
        TRIM(p_reason),
        v_caller_id,
        now(),
        NULLIF(TRIM(COALESCE(p_idempotency_key, '')), '')
    ) RETURNING id INTO v_refund_id;

    -- 7. Update Payment Record
    v_new_payment_refunded := v_payment.refunded_amount_minor + p_refund_amount_minor;

    UPDATE public.payments
    SET refunded_amount_minor = v_new_payment_refunded,
        is_refunded = (v_new_payment_refunded >= amount_minor),
        status = CASE 
            WHEN v_new_payment_refunded >= amount_minor THEN 'REFUNDED'::public.payment_status
            ELSE status 
        END
    WHERE id = p_payment_id;

    -- 8. Update Order Financial Status
    v_new_order_refunded := v_order.refunded_amount_minor + p_refund_amount_minor;

    IF v_new_order_refunded >= v_order.paid_amount_minor THEN
        v_new_financial_status := 'REFUNDED'::public.order_financial_status;
    ELSE
        v_new_financial_status := 'PARTIALLY_REFUNDED'::public.order_financial_status;
    END IF;

    UPDATE public.orders
    SET refunded_amount_minor = v_new_order_refunded,
        financial_status = v_new_financial_status,
        updated_at = now()
    WHERE id = p_order_id;

    -- 9. Audit Log
    INSERT INTO public.audit_logs (
        restaurant_id,
        actor_id,
        action,
        target_entity,
        target_id,
        details
    ) VALUES (
        p_restaurant_id,
        v_caller_id,
        'PROCESS_REFUND',
        'refunds',
        v_refund_id,
        jsonb_build_object(
            'order_id', p_order_id,
            'payment_id', p_payment_id,
            'amount_minor', p_refund_amount_minor,
            'reason', p_reason,
            'new_financial_status', v_new_financial_status
        )
    );

    RETURN jsonb_build_object(
        'refund_id', v_refund_id,
        'payment_id', p_payment_id,
        'order_id', p_order_id,
        'refund_amount_minor', p_refund_amount_minor,
        'new_financial_status', v_new_financial_status,
        'order_total_refunded_minor', v_new_order_refunded,
        'idempotent_replay', false
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.refund_order_payment TO authenticated;

-- ----------------------------------------------------------------------------
-- 7. Transactional RPC: update_payment_method_status
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_payment_method_status(
    p_restaurant_id UUID,
    p_code TEXT,
    p_is_active BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role app_role;
    v_clean_code TEXT;
BEGIN
    v_caller_id := auth.uid();
    v_clean_code := UPPER(TRIM(p_code));

    IF v_caller_id IS NOT NULL THEN
        SELECT role INTO v_caller_role
        FROM public.restaurant_memberships
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_caller_id
          AND is_active = TRUE
          AND deleted_at IS NULL;

        IF v_caller_role IS NULL OR v_caller_role NOT IN ('OWNER', 'ADMIN') THEN
            RAISE EXCEPTION 'Unauthorized: Only Owners and Admins can configure payment methods.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    UPDATE public.payment_methods
    SET is_active = p_is_active
    WHERE restaurant_id = p_restaurant_id
      AND UPPER(code) = v_clean_code;

    IF NOT FOUND THEN
        -- Insert new method record if not existing
        INSERT INTO public.payment_methods (
            restaurant_id,
            code,
            display_name,
            is_active
        ) VALUES (
            p_restaurant_id,
            v_clean_code,
            v_clean_code,
            p_is_active
        );
    END IF;

    RETURN jsonb_build_object(
        'restaurant_id', p_restaurant_id,
        'code', v_clean_code,
        'is_active', p_is_active
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_payment_method_status TO authenticated;

-- ----------------------------------------------------------------------------
-- 8. Enhanced Order Creation RPC: create_order_with_items
-- ----------------------------------------------------------------------------
-- Updated to support configurable tax behavior (inclusive vs exclusive),
-- configurable tax names, service charges, and initial financial status.
CREATE OR REPLACE FUNCTION public.create_order_with_items(
    p_restaurant_id UUID,
    p_table_name TEXT,
    p_special_instructions TEXT DEFAULT '',
    p_discount_minor BIGINT DEFAULT 0,
    p_items JSONB DEFAULT '[]'::jsonb,
    p_idempotency_key TEXT DEFAULT NULL,
    p_customer_id UUID DEFAULT NULL,
    p_discount_reason TEXT DEFAULT ''
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
BEGIN
    v_caller_id := auth.uid();

    -- Validate idempotency key if provided
    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) != '' THEN
        SELECT id, order_number INTO v_existing_order_id, v_existing_order_number
        FROM public.orders
        WHERE restaurant_id = p_restaurant_id
          AND idempotency_key = TRIM(p_idempotency_key);

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

    -- Validate item list is not empty
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Order validation error: At least one item is required.'
            USING ERRCODE = '22023';
    END IF;

    -- Fetch restaurant tax & service charge settings
    SELECT 
        COALESCE(gst_rate_basis_points, 500) AS tax_bps,
        COALESCE(tax_name, 'GST') AS tax_name,
        COALESCE(tax_is_inclusive, false) AS tax_is_inclusive,
        COALESCE(service_charge_basis_points, 0) AS service_charge_bps
    INTO v_settings
    FROM public.restaurant_settings
    WHERE restaurant_id = p_restaurant_id;

    IF v_settings.tax_bps IS NOT NULL THEN
        v_tax_rate_bps := v_settings.tax_bps;
        v_tax_name := v_settings.tax_name;
        v_tax_is_inclusive := v_settings.tax_is_inclusive;
        v_service_charge_bps := v_settings.service_charge_bps;
    END IF;

    -- Generate sequence-based order number
    SELECT COUNT(*) + 1 INTO v_today_seq
    FROM public.orders
    WHERE restaurant_id = p_restaurant_id
      AND created_at::date = CURRENT_DATE;

    v_order_number := 'CF-' || TO_CHAR(CURRENT_DATE, 'YYMMDD') || '-' || LPAD(v_today_seq::text, 3, '0');

    -- Create order row placeholder
    INSERT INTO public.orders (
        restaurant_id,
        order_number,
        table_name,
        customer_id,
        status,
        financial_status,
        subtotal_minor,
        discount_minor,
        tax_minor,
        service_charge_minor,
        total_minor,
        tax_name,
        tax_rate_basis_points,
        tax_is_inclusive,
        discount_reason,
        discount_authorized_by,
        special_instructions,
        created_by,
        idempotency_key
    ) VALUES (
        p_restaurant_id,
        v_order_number,
        COALESCE(NULLIF(TRIM(p_table_name), ''), 'Takeaway'),
        p_customer_id,
        'NEW'::public.order_status,
        'UNPAID'::public.order_financial_status,
        0,
        GREATEST(0, p_discount_minor),
        0,
        0,
        0,
        v_tax_name,
        v_tax_rate_bps,
        v_tax_is_inclusive,
        COALESCE(p_discount_reason, ''),
        CASE WHEN p_discount_minor > 0 THEN v_caller_id ELSE NULL END,
        COALESCE(p_special_instructions, ''),
        v_caller_id,
        NULLIF(TRIM(COALESCE(p_idempotency_key, '')), '')
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

        -- Insert snapshot item
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

    v_taxable_minor := v_subtotal_minor - p_discount_minor;

    -- Financial Calculations: Inclusive vs Exclusive Tax & Service Charges
    IF v_tax_is_inclusive THEN
        -- Price includes tax: extract tax portion
        v_tax_minor := (v_taxable_minor * v_tax_rate_bps) / (10000 + v_tax_rate_bps);
        v_service_charge_minor := (v_taxable_minor * v_service_charge_bps) / 10000;
        v_total_minor := v_taxable_minor + v_service_charge_minor;
    ELSE
        -- Price excludes tax: tax is added on top
        v_tax_minor := (v_taxable_minor * v_tax_rate_bps) / 10000;
        v_service_charge_minor := (v_taxable_minor * v_service_charge_bps) / 10000;
        v_total_minor := v_taxable_minor + v_tax_minor + v_service_charge_minor;
    END IF;

    -- Update final verified amounts on order
    UPDATE public.orders
    SET subtotal_minor = v_subtotal_minor,
        discount_minor = p_discount_minor,
        tax_minor = v_tax_minor,
        service_charge_minor = v_service_charge_minor,
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
        'service_charge_minor', v_service_charge_minor,
        'total_minor', v_total_minor,
        'financial_status', 'UNPAID',
        'idempotent_replay', false
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_order_with_items TO authenticated, anon;

-- ----------------------------------------------------------------------------
-- 9. Transactional RPC: get_financial_report
-- ----------------------------------------------------------------------------
-- Aggregates real financial metrics (gross sales, net sales, collections by method,
-- taxes, discounts, refunds, outstanding balances) for Owners & Admins.
CREATE OR REPLACE FUNCTION public.get_financial_report(
    p_restaurant_id UUID,
    p_start_date TIMESTAMPTZ DEFAULT (CURRENT_DATE::TIMESTAMPTZ),
    p_end_date TIMESTAMPTZ DEFAULT (now())
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_role app_role;
    v_gross_sales_minor BIGINT := 0;
    v_net_sales_minor BIGINT := 0;
    v_discounts_total_minor BIGINT := 0;
    v_tax_collected_minor BIGINT := 0;
    v_service_charge_minor BIGINT := 0;
    v_total_payments_minor BIGINT := 0;
    v_cash_collected_minor BIGINT := 0;
    v_upi_collected_minor BIGINT := 0;
    v_card_collected_minor BIGINT := 0;
    v_other_collected_minor BIGINT := 0;
    v_refunds_total_minor BIGINT := 0;
    v_outstanding_balance_minor BIGINT := 0;
    v_total_orders_count INT := 0;
    v_paid_orders_count INT := 0;
    v_unpaid_orders_count INT := 0;
BEGIN
    v_caller_id := auth.uid();

    -- Role Authorization: OWNER or ADMIN
    IF v_caller_id IS NOT NULL THEN
        SELECT role INTO v_caller_role
        FROM public.restaurant_memberships
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_caller_id
          AND is_active = TRUE
          AND deleted_at IS NULL;

        IF v_caller_role IS NULL OR v_caller_role NOT IN ('OWNER', 'ADMIN') THEN
            RAISE EXCEPTION 'Unauthorized: Only Owners and Admins can view financial reports.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 1. Order Aggregations
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE financial_status = 'PAID'),
        COUNT(*) FILTER (WHERE financial_status IN ('UNPAID', 'PARTIALLY_PAID')),
        COALESCE(SUM(subtotal_minor) FILTER (WHERE status != 'CANCELLED'), 0),
        COALESCE(SUM(discount_minor) FILTER (WHERE status != 'CANCELLED'), 0),
        COALESCE(SUM(tax_minor) FILTER (WHERE status != 'CANCELLED' AND financial_status IN ('PAID', 'PARTIALLY_PAID')), 0),
        COALESCE(SUM(service_charge_minor) FILTER (WHERE status != 'CANCELLED'), 0),
        COALESCE(SUM(total_minor - paid_amount_minor) FILTER (WHERE status != 'CANCELLED' AND financial_status IN ('UNPAID', 'PARTIALLY_PAID')), 0)
    INTO
        v_total_orders_count,
        v_paid_orders_count,
        v_unpaid_orders_count,
        v_gross_sales_minor,
        v_discounts_total_minor,
        v_tax_collected_minor,
        v_service_charge_minor,
        v_outstanding_balance_minor
    FROM public.orders
    WHERE restaurant_id = p_restaurant_id
      AND created_at >= p_start_date
      AND created_at <= p_end_date
      AND deleted_at IS NULL;

    v_net_sales_minor := v_gross_sales_minor - v_discounts_total_minor;

    -- 2. Payment Collections Aggregations
    SELECT
        COALESCE(SUM(amount_minor), 0),
        COALESCE(SUM(amount_minor) FILTER (WHERE payment_method_code = 'CASH'), 0),
        COALESCE(SUM(amount_minor) FILTER (WHERE payment_method_code = 'UPI'), 0),
        COALESCE(SUM(amount_minor) FILTER (WHERE payment_method_code = 'CARD'), 0),
        COALESCE(SUM(amount_minor) FILTER (WHERE payment_method_code NOT IN ('CASH', 'UPI', 'CARD')), 0)
    INTO
        v_total_payments_minor,
        v_cash_collected_minor,
        v_upi_collected_minor,
        v_card_collected_minor,
        v_other_collected_minor
    FROM public.payments
    WHERE restaurant_id = p_restaurant_id
      AND status = 'COMPLETED'
      AND created_at >= p_start_date
      AND created_at <= p_end_date;

    -- 3. Refunds Aggregation
    SELECT COALESCE(SUM(amount_minor), 0)
    INTO v_refunds_total_minor
    FROM public.refunds
    WHERE restaurant_id = p_restaurant_id
      AND refunded_at >= p_start_date
      AND refunded_at <= p_end_date;

    RETURN jsonb_build_object(
        'start_date', p_start_date,
        'end_date', p_end_date,
        'gross_sales_minor', v_gross_sales_minor,
        'net_sales_minor', v_net_sales_minor,
        'discounts_total_minor', v_discounts_total_minor,
        'tax_collected_minor', v_tax_collected_minor,
        'service_charge_minor', v_service_charge_minor,
        'total_payments_minor', v_total_payments_minor,
        'cash_collected_minor', v_cash_collected_minor,
        'upi_collected_minor', v_upi_collected_minor,
        'card_collected_minor', v_card_collected_minor,
        'other_collected_minor', v_other_collected_minor,
        'refunds_total_minor', v_refunds_total_minor,
        'net_collected_minor', v_total_payments_minor - v_refunds_total_minor,
        'outstanding_balance_minor', v_outstanding_balance_minor,
        'total_orders_count', v_total_orders_count,
        'paid_orders_count', v_paid_orders_count,
        'unpaid_orders_count', v_unpaid_orders_count
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_financial_report TO authenticated;

-- ----------------------------------------------------------------------------
-- 10. Realtime Publication Additions
-- ----------------------------------------------------------------------------
ALTER TABLE public.payments REPLICA IDENTITY FULL;
ALTER TABLE public.refunds REPLICA IDENTITY FULL;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE payments;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE refunds;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

