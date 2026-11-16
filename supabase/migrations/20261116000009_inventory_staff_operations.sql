-- ============================================================================
-- Migration: 20261116000009_inventory_staff_operations.sql
-- Combined Phase 09: Inventory Management, Stock Control, Suppliers,
--                     Staff Management & Workforce Operations
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Extend stock_movement_type Enum
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    ALTER TYPE public.stock_movement_type ADD VALUE IF NOT EXISTS 'SALE_CONSUMPTION';
    ALTER TYPE public.stock_movement_type ADD VALUE IF NOT EXISTS 'MANUAL_ADJUSTMENT';
    ALTER TYPE public.stock_movement_type ADD VALUE IF NOT EXISTS 'DAMAGE';
    ALTER TYPE public.stock_movement_type ADD VALUE IF NOT EXISTS 'RETURN';
    ALTER TYPE public.stock_movement_type ADD VALUE IF NOT EXISTS 'TRANSFER';
    ALTER TYPE public.stock_movement_type ADD VALUE IF NOT EXISTS 'REVERSAL';
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- ----------------------------------------------------------------------------
-- 2. Suppliers Table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    contact_name TEXT,
    email TEXT,
    phone TEXT,
    address TEXT,
    notes TEXT DEFAULT '',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_suppliers_restaurant ON public.suppliers(restaurant_id, is_active);

-- ----------------------------------------------------------------------------
-- 3. Enhance inventory_items Table
-- ----------------------------------------------------------------------------
ALTER TABLE public.inventory_items
    ADD COLUMN IF NOT EXISTS sku TEXT,
    ADD COLUMN IF NOT EXISTS minimum_stock NUMERIC(12, 3) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS storage_location TEXT,
    ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_inventory_items_sku ON public.inventory_items(restaurant_id, sku) WHERE sku IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_items_supplier ON public.inventory_items(supplier_id);

-- ----------------------------------------------------------------------------
-- 4. Enhance stock_movements Table
-- ----------------------------------------------------------------------------
ALTER TABLE public.stock_movements
    ADD COLUMN IF NOT EXISTS restaurant_id UUID REFERENCES public.restaurants(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS unit TEXT,
    ADD COLUMN IF NOT EXISTS reference TEXT,
    ADD COLUMN IF NOT EXISTS client_tx_id TEXT;

-- Backfill restaurant_id on stock_movements if null
UPDATE public.stock_movements sm
SET restaurant_id = ii.restaurant_id
FROM public.inventory_items ii
WHERE sm.inventory_item_id = ii.id AND sm.restaurant_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_stock_movements_restaurant ON public.stock_movements(restaurant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_movements_reference ON public.stock_movements(reference);
CREATE INDEX IF NOT EXISTS idx_stock_movements_client_tx ON public.stock_movements(restaurant_id, client_tx_id) WHERE client_tx_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 5. Purchases & Purchase Items Tables
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.purchases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    purchase_number TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ORDERED' CHECK (status IN ('DRAFT', 'ORDERED', 'RECEIVED', 'CANCELLED')),
    purchase_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expected_delivery_date DATE,
    subtotal_minor BIGINT NOT NULL DEFAULT 0,
    tax_minor BIGINT NOT NULL DEFAULT 0,
    additional_charges_minor BIGINT NOT NULL DEFAULT 0,
    total_minor BIGINT NOT NULL DEFAULT 0,
    notes TEXT DEFAULT '',
    received_at TIMESTAMPTZ,
    received_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    created_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    client_tx_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_purchases_restaurant ON public.purchases(restaurant_id, purchase_date DESC);
CREATE INDEX IF NOT EXISTS idx_purchases_supplier ON public.purchases(supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchases_status ON public.purchases(restaurant_id, status);

CREATE TABLE IF NOT EXISTS public.purchase_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_id UUID NOT NULL REFERENCES public.purchases(id) ON DELETE CASCADE,
    inventory_item_id UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE RESTRICT,
    quantity NUMERIC(12, 3) NOT NULL CHECK (quantity > 0),
    unit TEXT NOT NULL,
    unit_cost_minor BIGINT NOT NULL DEFAULT 0,
    total_cost_minor BIGINT NOT NULL DEFAULT 0,
    quantity_received NUMERIC(12, 3) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON public.purchase_items(purchase_id);
CREATE INDEX IF NOT EXISTS idx_purchase_items_item ON public.purchase_items(inventory_item_id);

-- ----------------------------------------------------------------------------
-- 6. Menu Item Ingredients / Recipes Table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.menu_item_ingredients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    menu_item_id UUID NOT NULL REFERENCES public.menu_items(id) ON DELETE CASCADE,
    inventory_item_id UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE RESTRICT,
    quantity NUMERIC(12, 3) NOT NULL CHECK (quantity > 0),
    unit TEXT NOT NULL,
    notes TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_menu_item_ingredient UNIQUE (menu_item_id, inventory_item_id)
);

CREATE INDEX IF NOT EXISTS idx_recipe_menu_item ON public.menu_item_ingredients(menu_item_id);
CREATE INDEX IF NOT EXISTS idx_recipe_inventory_item ON public.menu_item_ingredients(inventory_item_id);

-- ----------------------------------------------------------------------------
-- 7. Staff Operations: Profiles, Shifts, Attendance & Audit
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    department TEXT NOT NULL DEFAULT 'Front of House',
    employment_status TEXT NOT NULL DEFAULT 'FULL_TIME' CHECK (employment_status IN ('FULL_TIME', 'PART_TIME', 'CASUAL', 'TERMINATED')),
    joining_date DATE NOT NULL DEFAULT CURRENT_DATE,
    emergency_contact_name TEXT,
    emergency_contact_phone TEXT,
    notes TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_staff_profile UNIQUE (restaurant_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_staff_profiles_restaurant ON public.staff_profiles(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_staff_profiles_user ON public.staff_profiles(user_id);

CREATE TABLE IF NOT EXISTS public.shifts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    department TEXT NOT NULL DEFAULT 'General',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_shifts_restaurant ON public.shifts(restaurant_id, is_active);

CREATE TABLE IF NOT EXISTS public.staff_attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    shift_id UUID REFERENCES public.shifts(id) ON DELETE SET NULL,
    clock_in TIMESTAMPTZ NOT NULL DEFAULT now(),
    clock_out TIMESTAMPTZ,
    total_break_minutes INT NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'CLOCKED_IN' CHECK (status IN ('CLOCKED_IN', 'ON_BREAK', 'CLOCKED_OUT')),
    is_late BOOLEAN NOT NULL DEFAULT false,
    notes TEXT DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_attendance_restaurant ON public.staff_attendance(restaurant_id, clock_in DESC);
CREATE INDEX IF NOT EXISTS idx_attendance_user ON public.staff_attendance(user_id, clock_in DESC);

-- Partial Unique Index: Prevent duplicate active clock-in sessions per user per restaurant
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_clock_in
    ON public.staff_attendance(restaurant_id, user_id)
    WHERE status IN ('CLOCKED_IN', 'ON_BREAK');

CREATE TABLE IF NOT EXISTS public.staff_audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    target_user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    performed_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_staff_audit_restaurant ON public.staff_audit_events(restaurant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_staff_audit_target ON public.staff_audit_events(target_user_id);

-- ----------------------------------------------------------------------------
-- 8. Updated At Triggers
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_suppliers_updated_at
    BEFORE UPDATE ON public.suppliers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE OR REPLACE TRIGGER trg_purchases_updated_at
    BEFORE UPDATE ON public.purchases
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE OR REPLACE TRIGGER trg_menu_item_ingredients_updated_at
    BEFORE UPDATE ON public.menu_item_ingredients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE OR REPLACE TRIGGER trg_staff_profiles_updated_at
    BEFORE UPDATE ON public.staff_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE OR REPLACE TRIGGER trg_shifts_updated_at
    BEFORE UPDATE ON public.shifts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE OR REPLACE TRIGGER trg_staff_attendance_updated_at
    BEFORE UPDATE ON public.staff_attendance
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ----------------------------------------------------------------------------
-- 9. Transactional RPC: adjust_inventory_stock_v2
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.adjust_inventory_stock_v2(
    p_restaurant_id UUID,
    p_inventory_item_id UUID,
    p_movement_type TEXT,
    p_quantity_change NUMERIC(12, 3),
    p_reason TEXT DEFAULT '',
    p_reference TEXT DEFAULT '',
    p_client_tx_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_caller_role app_role;
    v_prev_stock NUMERIC(12, 3);
    v_new_stock NUMERIC(12, 3);
    v_unit TEXT;
    v_movement_id UUID;
    v_clean_type TEXT := upper(trim(p_movement_type));
BEGIN
    -- Check client_tx_id for idempotency
    IF p_client_tx_id IS NOT NULL THEN
        SELECT id, previous_stock, new_stock INTO v_movement_id, v_prev_stock, v_new_stock
        FROM public.stock_movements
        WHERE restaurant_id = p_restaurant_id AND client_tx_id = p_client_tx_id;

        IF v_movement_id IS NOT NULL THEN
            RETURN jsonb_build_object(
                'movement_id', v_movement_id,
                'inventory_item_id', p_inventory_item_id,
                'previous_stock', v_prev_stock,
                'new_stock', v_new_stock,
                'is_replay', true
            );
        END IF;
    END IF;

    -- Verify caller authorization: OWNER, ADMIN, KITCHEN
    IF v_caller_id IS NOT NULL THEN
        SELECT role INTO v_caller_role
        FROM public.restaurant_memberships
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_caller_id
          AND is_active = true
          AND deleted_at IS NULL;

        IF v_caller_role IS NULL OR v_caller_role NOT IN ('OWNER'::app_role, 'ADMIN'::app_role, 'KITCHEN'::app_role) THEN
            RAISE EXCEPTION 'Unauthorized: Caller cannot adjust inventory stock.' USING ERRCODE = '42501';
        END IF;
    END IF;

    -- Lock and retrieve current inventory item
    SELECT current_stock, unit INTO v_prev_stock, v_unit
    FROM public.inventory_items
    WHERE id = p_inventory_item_id
      AND restaurant_id = p_restaurant_id
      AND deleted_at IS NULL
    FOR UPDATE;

    IF v_prev_stock IS NULL THEN
        RAISE EXCEPTION 'Inventory item % does not exist in restaurant %.', p_inventory_item_id, p_restaurant_id;
    END IF;

    -- Calculate resulting stock (clamped at 0 for subtractions)
    v_new_stock := v_prev_stock + p_quantity_change;
    IF v_new_stock < 0 THEN
        v_new_stock := 0;
    END IF;

    -- Update inventory item
    UPDATE public.inventory_items
    SET current_stock = v_new_stock,
        updated_at = now()
    WHERE id = p_inventory_item_id;

    -- Record immutable stock movement ledger entry
    INSERT INTO public.stock_movements (
        restaurant_id,
        inventory_item_id,
        movement_type,
        quantity_change,
        previous_stock,
        new_stock,
        unit,
        reference,
        reason,
        performed_by,
        client_tx_id,
        created_at
    ) VALUES (
        p_restaurant_id,
        p_inventory_item_id,
        v_clean_type::public.stock_movement_type,
        p_quantity_change,
        v_prev_stock,
        v_new_stock,
        v_unit,
        p_reference,
        p_reason,
        v_caller_id,
        p_client_tx_id,
        now()
    ) RETURNING id INTO v_movement_id;

    -- Log audit event
    INSERT INTO public.staff_audit_events (
        restaurant_id,
        event_type,
        performed_by,
        details
    ) VALUES (
        p_restaurant_id,
        'INVENTORY_ADJUSTED',
        v_caller_id,
        jsonb_build_object(
            'item_id', p_inventory_item_id,
            'movement_type', v_clean_type,
            'quantity_change', p_quantity_change,
            'previous_stock', v_prev_stock,
            'new_stock', v_new_stock,
            'reason', p_reason
        )
    );

    RETURN jsonb_build_object(
        'movement_id', v_movement_id,
        'inventory_item_id', p_inventory_item_id,
        'previous_stock', v_prev_stock,
        'new_stock', v_new_stock,
        'is_replay', false
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.adjust_inventory_stock_v2 TO authenticated, anon;

-- ----------------------------------------------------------------------------
-- 10. Transactional RPC: deduct_order_recipe_stock (Idempotent Recipe Deduction)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.deduct_order_recipe_stock(
    p_restaurant_id UUID,
    p_order_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_order_num TEXT;
    v_item RECORD;
    v_ing RECORD;
    v_prev_stock NUMERIC(12, 3);
    v_new_stock NUMERIC(12, 3);
    v_total_deduction NUMERIC(12, 3);
    v_deducted_count INT := 0;
BEGIN
    -- Retrieve order
    SELECT order_number INTO v_order_num
    FROM public.orders
    WHERE id = p_order_id AND restaurant_id = p_restaurant_id;

    IF v_order_num IS NULL THEN
        RAISE EXCEPTION 'Order % not found in restaurant %.', p_order_id, p_restaurant_id;
    END IF;

    -- Idempotency check: if this order already had recipe deductions recorded, return cleanly
    IF EXISTS (
        SELECT 1 FROM public.stock_movements
        WHERE restaurant_id = p_restaurant_id
          AND reference = p_order_id::text
          AND movement_type = 'SALE_CONSUMPTION'::public.stock_movement_type
    ) THEN
        RETURN jsonb_build_object(
            'order_id', p_order_id,
            'deducted_items_count', 0,
            'already_deducted', true
        );
    END IF;

    -- Iterate through each order item and find recipes
    FOR v_item IN
        SELECT menu_item_id, quantity
        FROM public.order_items
        WHERE order_id = p_order_id
    LOOP
        FOR v_ing IN
            SELECT inventory_item_id, quantity AS ing_qty, unit
            FROM public.menu_item_ingredients
            WHERE menu_item_id = v_item.menu_item_id
              AND restaurant_id = p_restaurant_id
        LOOP
            v_total_deduction := v_item.quantity * v_ing.ing_qty;

            -- Lock inventory item
            SELECT current_stock INTO v_prev_stock
            FROM public.inventory_items
            WHERE id = v_ing.inventory_item_id AND restaurant_id = p_restaurant_id
            FOR UPDATE;

            IF v_prev_stock IS NOT NULL THEN
                v_new_stock := v_prev_stock - v_total_deduction;
                IF v_new_stock < 0 THEN
                    v_new_stock := 0;
                END IF;

                UPDATE public.inventory_items
                SET current_stock = v_new_stock,
                    updated_at = now()
                WHERE id = v_ing.inventory_item_id;

                INSERT INTO public.stock_movements (
                    restaurant_id,
                    inventory_item_id,
                    movement_type,
                    quantity_change,
                    previous_stock,
                    new_stock,
                    unit,
                    reference,
                    reason,
                    performed_by,
                    created_at
                ) VALUES (
                    p_restaurant_id,
                    v_ing.inventory_item_id,
                    'SALE_CONSUMPTION'::public.stock_movement_type,
                    -v_total_deduction,
                    v_prev_stock,
                    v_new_stock,
                    v_ing.unit,
                    p_order_id::text,
                    'Recipe consumption for Order #' || v_order_num,
                    auth.uid(),
                    now()
                );

                v_deducted_count := v_deducted_count + 1;
            END IF;
        END LOOP;
    END LOOP;

    RETURN jsonb_build_object(
        'order_id', p_order_id,
        'deducted_items_count', v_deducted_count,
        'already_deducted', false
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.deduct_order_recipe_stock TO authenticated, anon;

-- ----------------------------------------------------------------------------
-- 11. Transactional RPC: receive_purchase_order
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.receive_purchase_order(
    p_restaurant_id UUID,
    p_purchase_id UUID,
    p_notes TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_caller_role app_role;
    v_purchase RECORD;
    v_item RECORD;
    v_prev_stock NUMERIC(12, 3);
    v_new_stock NUMERIC(12, 3);
    v_received_count INT := 0;
BEGIN
    -- Role authorization: OWNER or ADMIN
    IF v_caller_id IS NOT NULL THEN
        SELECT role INTO v_caller_role
        FROM public.restaurant_memberships
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_caller_id
          AND is_active = true
          AND deleted_at IS NULL;

        IF v_caller_role IS NULL OR v_caller_role NOT IN ('OWNER'::app_role, 'ADMIN'::app_role) THEN
            RAISE EXCEPTION 'Unauthorized: only Owners and Admins may receive purchase orders.' USING ERRCODE = '42501';
        END IF;
    END IF;

    -- Lock purchase
    SELECT id, purchase_number, status INTO v_purchase
    FROM public.purchases
    WHERE id = p_purchase_id AND restaurant_id = p_restaurant_id
    FOR UPDATE;

    IF v_purchase.id IS NULL THEN
        RAISE EXCEPTION 'Purchase order % not found.', p_purchase_id;
    END IF;

    IF v_purchase.status = 'RECEIVED' THEN
        RAISE EXCEPTION 'Purchase order % has already been received.', v_purchase.purchase_number;
    END IF;

    IF v_purchase.status = 'CANCELLED' THEN
        RAISE EXCEPTION 'Cannot receive cancelled purchase order %.', v_purchase.purchase_number;
    END IF;

    -- For each purchase item, increment inventory item stock
    FOR v_item IN
        SELECT inventory_item_id, quantity, unit
        FROM public.purchase_items
        WHERE purchase_id = p_purchase_id
    LOOP
        SELECT current_stock INTO v_prev_stock
        FROM public.inventory_items
        WHERE id = v_item.inventory_item_id AND restaurant_id = p_restaurant_id
        FOR UPDATE;

        IF v_prev_stock IS NOT NULL THEN
            v_new_stock := v_prev_stock + v_item.quantity;

            UPDATE public.inventory_items
            SET current_stock = v_new_stock,
                updated_at = now()
            WHERE id = v_item.inventory_item_id;

            -- Record stock movement ledger
            INSERT INTO public.stock_movements (
                restaurant_id,
                inventory_item_id,
                movement_type,
                quantity_change,
                previous_stock,
                new_stock,
                unit,
                reference,
                reason,
                performed_by,
                created_at
            ) VALUES (
                p_restaurant_id,
                v_item.inventory_item_id,
                'PURCHASE'::public.stock_movement_type,
                v_item.quantity,
                v_prev_stock,
                v_new_stock,
                v_item.unit,
                v_purchase.purchase_number,
                'Received PO: ' || v_purchase.purchase_number,
                v_caller_id,
                now()
            );

            v_received_count := v_received_count + 1;
        END IF;
    END LOOP;

    -- Update purchase status
    UPDATE public.purchases
    SET status = 'RECEIVED',
        received_at = now(),
        received_by = v_caller_id,
        notes = CASE WHEN p_notes <> '' THEN p_notes ELSE notes END,
        updated_at = now()
    WHERE id = p_purchase_id;

    -- Record audit event
    INSERT INTO public.staff_audit_events (
        restaurant_id,
        event_type,
        performed_by,
        details
    ) VALUES (
        p_restaurant_id,
        'PURCHASE_RECEIVED',
        v_caller_id,
        jsonb_build_object(
            'purchase_id', p_purchase_id,
            'purchase_number', v_purchase.purchase_number,
            'items_received', v_received_count
        )
    );

    RETURN jsonb_build_object(
        'purchase_id', p_purchase_id,
        'purchase_number', v_purchase.purchase_number,
        'items_received', v_received_count,
        'received_at', now()
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.receive_purchase_order TO authenticated, anon;

-- ----------------------------------------------------------------------------
-- 12. Transactional RPCs: staff_clock_in & staff_clock_out
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.staff_clock_in(
    p_restaurant_id UUID,
    p_target_user_id UUID DEFAULT NULL,
    p_shift_id UUID DEFAULT NULL,
    p_notes TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_user_id UUID := COALESCE(p_target_user_id, v_caller_id);
    v_attendance_id UUID;
    v_shift RECORD;
    v_is_late BOOLEAN := false;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User ID is required for clock-in.' USING ERRCODE = '42501';
    END IF;

    -- Check if already clocked in
    IF EXISTS (
        SELECT 1 FROM public.staff_attendance
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_user_id
          AND status IN ('CLOCKED_IN', 'ON_BREAK')
    ) THEN
        RAISE EXCEPTION 'Staff member already has an active clock-in session.';
    END IF;

    -- Check shift timing if provided
    IF p_shift_id IS NOT NULL THEN
        SELECT start_time INTO v_shift
        FROM public.shifts
        WHERE id = p_shift_id AND restaurant_id = p_restaurant_id;

        IF v_shift.start_time IS NOT NULL AND CURRENT_TIME > (v_shift.start_time + INTERVAL '10 minutes') THEN
            v_is_late := true;
        END IF;
    END IF;

    INSERT INTO public.staff_attendance (
        restaurant_id,
        user_id,
        shift_id,
        clock_in,
        status,
        is_late,
        notes,
        created_at,
        updated_at
    ) VALUES (
        p_restaurant_id,
        v_user_id,
        p_shift_id,
        now(),
        'CLOCKED_IN',
        v_is_late,
        p_notes,
        now(),
        now()
    ) RETURNING id INTO v_attendance_id;

    -- Record audit event
    INSERT INTO public.staff_audit_events (
        restaurant_id,
        event_type,
        target_user_id,
        performed_by,
        details
    ) VALUES (
        p_restaurant_id,
        'ATTENDANCE_RECORDED',
        v_user_id,
        v_caller_id,
        jsonb_build_object(
            'action', 'CLOCK_IN',
            'attendance_id', v_attendance_id,
            'is_late', v_is_late
        )
    );

    RETURN jsonb_build_object(
        'attendance_id', v_attendance_id,
        'user_id', v_user_id,
        'status', 'CLOCKED_IN',
        'clock_in', now(),
        'is_late', v_is_late
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.staff_clock_in TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.staff_clock_out(
    p_restaurant_id UUID,
    p_attendance_id UUID,
    p_notes TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_attendance RECORD;
    v_duration INTERVAL;
BEGIN
    SELECT id, user_id, clock_in, status INTO v_attendance
    FROM public.staff_attendance
    WHERE id = p_attendance_id AND restaurant_id = p_restaurant_id
    FOR UPDATE;

    IF v_attendance.id IS NULL THEN
        RAISE EXCEPTION 'Attendance record % not found.', p_attendance_id;
    END IF;

    IF v_attendance.status = 'CLOCKED_OUT' THEN
        RAISE EXCEPTION 'Staff member is already clocked out.';
    END IF;

    v_duration := now() - v_attendance.clock_in;

    UPDATE public.staff_attendance
    SET clock_out = now(),
        status = 'CLOCKED_OUT',
        notes = CASE WHEN p_notes <> '' THEN p_notes ELSE notes END,
        updated_at = now()
    WHERE id = p_attendance_id;

    -- Record audit event
    INSERT INTO public.staff_audit_events (
        restaurant_id,
        event_type,
        target_user_id,
        performed_by,
        details
    ) VALUES (
        p_restaurant_id,
        'ATTENDANCE_RECORDED',
        v_attendance.user_id,
        v_caller_id,
        jsonb_build_object(
            'action', 'CLOCK_OUT',
            'attendance_id', p_attendance_id,
            'duration_minutes', EXTRACT(EPOCH FROM v_duration) / 60
        )
    );

    RETURN jsonb_build_object(
        'attendance_id', p_attendance_id,
        'status', 'CLOCKED_OUT',
        'clock_out', now(),
        'duration_minutes', EXTRACT(EPOCH FROM v_duration) / 60
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.staff_clock_out TO authenticated, anon;

-- ----------------------------------------------------------------------------
-- 13. Row-Level Security (RLS) Policies
-- ----------------------------------------------------------------------------
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_item_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_audit_events ENABLE ROW LEVEL SECURITY;

-- suppliers
CREATE POLICY "Suppliers read by tenant members"
    ON public.suppliers FOR SELECT
    USING (public.is_restaurant_member(restaurant_id));

CREATE POLICY "Suppliers manage by Owner and Admin"
    ON public.suppliers FOR ALL
    USING (public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role))
    WITH CHECK (public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role));

-- purchases
CREATE POLICY "Purchases read by Owner and Admin"
    ON public.purchases FOR SELECT
    USING (public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role));

CREATE POLICY "Purchases manage by Owner and Admin"
    ON public.purchases FOR ALL
    USING (public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role))
    WITH CHECK (public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role));

-- purchase_items
CREATE POLICY "Purchase items read by Owner and Admin"
    ON public.purchase_items FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.purchases p
            WHERE p.id = purchase_id
              AND public.has_restaurant_role(p.restaurant_id, 'ADMIN'::app_role)
        )
    );

CREATE POLICY "Purchase items manage by Owner and Admin"
    ON public.purchase_items FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.purchases p
            WHERE p.id = purchase_id
              AND public.has_restaurant_role(p.restaurant_id, 'ADMIN'::app_role)
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.purchases p
            WHERE p.id = purchase_id
              AND public.has_restaurant_role(p.restaurant_id, 'ADMIN'::app_role)
        )
    );

-- menu_item_ingredients
CREATE POLICY "Recipes read by tenant members"
    ON public.menu_item_ingredients FOR SELECT
    USING (public.is_restaurant_member(restaurant_id));

CREATE POLICY "Recipes manage by Owner, Admin and Kitchen"
    ON public.menu_item_ingredients FOR ALL
    USING (
        public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role)
        OR public.has_restaurant_role(restaurant_id, 'KITCHEN'::app_role)
    )
    WITH CHECK (
        public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role)
        OR public.has_restaurant_role(restaurant_id, 'KITCHEN'::app_role)
    );

-- staff_profiles
CREATE POLICY "Staff profiles read by Owner, Admin or self"
    ON public.staff_profiles FOR SELECT
    USING (
        public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role)
        OR user_id = auth.uid()
    );

CREATE POLICY "Staff profiles manage by Owner and Admin"
    ON public.staff_profiles FOR ALL
    USING (public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role))
    WITH CHECK (public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role));

-- shifts
CREATE POLICY "Shifts read by tenant members"
    ON public.shifts FOR SELECT
    USING (public.is_restaurant_member(restaurant_id));

CREATE POLICY "Shifts manage by Owner and Admin"
    ON public.shifts FOR ALL
    USING (public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role))
    WITH CHECK (public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role));

-- staff_attendance
CREATE POLICY "Attendance read by Owner, Admin or self"
    ON public.staff_attendance FOR SELECT
    USING (
        public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role)
        OR user_id = auth.uid()
    );

CREATE POLICY "Attendance manage by Owner, Admin or self"
    ON public.staff_attendance FOR ALL
    USING (
        public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role)
        OR user_id = auth.uid()
    )
    WITH CHECK (
        public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role)
        OR user_id = auth.uid()
    );

-- staff_audit_events
CREATE POLICY "Audit events read by Owner and Admin"
    ON public.staff_audit_events FOR SELECT
    USING (public.has_restaurant_role(restaurant_id, 'ADMIN'::app_role));

-- ----------------------------------------------------------------------------
-- 14. Realtime Publications
-- ----------------------------------------------------------------------------
ALTER TABLE public.suppliers REPLICA IDENTITY FULL;
ALTER TABLE public.purchases REPLICA IDENTITY FULL;
ALTER TABLE public.menu_item_ingredients REPLICA IDENTITY FULL;
ALTER TABLE public.shifts REPLICA IDENTITY FULL;
ALTER TABLE public.staff_attendance REPLICA IDENTITY FULL;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.suppliers;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.purchases;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.menu_item_ingredients;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.shifts;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.staff_attendance;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

