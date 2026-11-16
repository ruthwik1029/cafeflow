-- ============================================================================
-- Migration: 20261116000010_reporting_platform_completion.sql
-- Description: Combined Phase 10: Server-side business intelligence, comprehensive
--              reporting aggregations, analytics RPCs, performance indexing,
--              and multi-platform query optimizations under strict SEC-01 RBAC.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Performance Indexes for Analytics & Aggregations
-- ----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_orders_analytics 
ON public.orders(restaurant_id, created_at) 
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_payments_analytics 
ON public.payments(restaurant_id, status, created_at);

CREATE INDEX IF NOT EXISTS idx_order_items_product_lookup 
ON public.order_items(product_name, quantity, total_minor);

CREATE INDEX IF NOT EXISTS idx_refunds_analytics 
ON public.refunds(restaurant_id, refunded_at);

CREATE INDEX IF NOT EXISTS idx_stock_movements_analytics 
ON public.stock_movements(restaurant_id, movement_type, created_at);

CREATE INDEX IF NOT EXISTS idx_staff_attendance_analytics 
ON public.staff_attendance(restaurant_id, status, clock_in);

-- ----------------------------------------------------------------------------
-- 2. Comprehensive Business Intelligence & Analytics RPC
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_comprehensive_business_analytics(
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

    -- Financial Totals
    v_gross_sales_minor BIGINT := 0;
    v_discounts_total_minor BIGINT := 0;
    v_net_sales_minor BIGINT := 0;
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
    v_avg_order_value_minor BIGINT := 0;

    -- Order Types Breakdown
    v_order_types JSONB := '[]'::JSONB;

    -- Daily Trend
    v_daily_trends JSONB := '[]'::JSONB;

    -- Product Performance
    v_top_products JSONB := '[]'::JSONB;
    v_least_products JSONB := '[]'::JSONB;
    v_category_sales JSONB := '[]'::JSONB;

    -- Inventory Metrics
    v_total_items_count INT := 0;
    v_low_stock_count INT := 0;
    v_out_of_stock_count INT := 0;
    v_stock_valuation_minor BIGINT := 0;
    v_wastage_cost_minor BIGINT := 0;

    -- Kitchen Metrics
    v_avg_prep_time_seconds INT := 0;
    v_active_tickets_count INT := 0;
    v_delayed_tickets_count INT := 0;
    v_completed_tickets_count INT := 0;

    -- Table Metrics
    v_total_tables INT := 0;
    v_occupied_tables INT := 0;
    v_occupancy_rate NUMERIC := 0.0;

    -- Staff & Attendance Metrics
    v_clocked_in_count INT := 0;
    v_on_break_count INT := 0;
    v_late_arrivals_count INT := 0;
BEGIN
    v_caller_id := auth.uid();

    -- Role Authorization: OWNER or ADMIN only
    IF v_caller_id IS NOT NULL THEN
        SELECT role INTO v_caller_role
        FROM public.restaurant_memberships
        WHERE restaurant_id = p_restaurant_id
          AND user_id = v_caller_id
          AND is_active = TRUE
          AND deleted_at IS NULL;

        IF v_caller_role IS NULL OR v_caller_role NOT IN ('OWNER', 'ADMIN') THEN
            RAISE EXCEPTION 'Unauthorized: Only Owners and Admins can view comprehensive business analytics.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 1. Financial & Order Aggregations
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE financial_status = 'PAID'),
        COUNT(*) FILTER (WHERE financial_status IN ('UNPAID', 'PARTIALLY_PAID')),
        COALESCE(SUM(total_minor) FILTER (WHERE status != 'CANCELLED'), 0),
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
    IF v_total_orders_count > 0 THEN
        v_avg_order_value_minor := v_gross_sales_minor / v_total_orders_count;
    END IF;

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

    -- 4. Order Type Distribution (Dine-in vs Takeaway vs Delivery)
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'order_type', order_type,
                'order_count', cnt,
                'revenue_minor', rev
            )
        ),
        '[]'::JSONB
    )
    INTO v_order_types
    FROM (
        SELECT 
            CASE 
                WHEN table_name IS NULL OR lower(trim(table_name)) = 'takeaway' THEN 'Takeaway'
                WHEN lower(trim(table_name)) LIKE '%delivery%' THEN 'Delivery'
                ELSE 'Dine-In'
            END AS order_type,
            COUNT(*) AS cnt,
            COALESCE(SUM(total_minor), 0) AS rev
        FROM public.orders
        WHERE restaurant_id = p_restaurant_id
          AND created_at >= p_start_date
          AND created_at <= p_end_date
          AND status != 'CANCELLED'
          AND deleted_at IS NULL
        GROUP BY 1
    ) sub;

    -- 5. Daily Sales Trends
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'date', d_date,
                'gross_sales_minor', gross,
                'net_sales_minor', net,
                'order_count', cnt
            ) ORDER BY d_date ASC
        ),
        '[]'::JSONB
    )
    INTO v_daily_trends
    FROM (
        SELECT 
            to_char(date_trunc('day', created_at), 'YYYY-MM-DD') AS d_date,
            COALESCE(SUM(total_minor), 0) AS gross,
            COALESCE(SUM(total_minor - discount_minor), 0) AS net,
            COUNT(*) AS cnt
        FROM public.orders
        WHERE restaurant_id = p_restaurant_id
          AND created_at >= p_start_date
          AND created_at <= p_end_date
          AND status != 'CANCELLED'
          AND deleted_at IS NULL
        GROUP BY 1
    ) trends;

    -- 6. Product Analytics (Historical order_item snapshots)
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'product_name', product_name,
                'quantity_sold', total_qty,
                'revenue_minor', total_rev
            ) ORDER BY total_qty DESC
        ),
        '[]'::JSONB
    )
    INTO v_top_products
    FROM (
        SELECT 
            oi.product_name,
            SUM(oi.quantity) AS total_qty,
            SUM(oi.total_minor) AS total_rev
        FROM public.order_items oi
        JOIN public.orders o ON o.id = oi.order_id
        WHERE o.restaurant_id = p_restaurant_id
          AND o.created_at >= p_start_date
          AND o.created_at <= p_end_date
          AND o.status != 'CANCELLED'
          AND o.deleted_at IS NULL
        GROUP BY oi.product_name
        ORDER BY total_qty DESC
        LIMIT 10
    ) top_p;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'product_name', product_name,
                'quantity_sold', total_qty,
                'revenue_minor', total_rev
            ) ORDER BY total_qty ASC
        ),
        '[]'::JSONB
    )
    INTO v_least_products
    FROM (
        SELECT 
            oi.product_name,
            SUM(oi.quantity) AS total_qty,
            SUM(oi.total_minor) AS total_rev
        FROM public.order_items oi
        JOIN public.orders o ON o.id = oi.order_id
        WHERE o.restaurant_id = p_restaurant_id
          AND o.created_at >= p_start_date
          AND o.created_at <= p_end_date
          AND o.status != 'CANCELLED'
          AND o.deleted_at IS NULL
        GROUP BY oi.product_name
        ORDER BY total_qty ASC
        LIMIT 5
    ) least_p;

    -- 7. Inventory Summary & Valuation
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE current_stock <= reorder_level AND current_stock > 0),
        COUNT(*) FILTER (WHERE current_stock <= 0),
        COALESCE(SUM(ROUND(current_stock * cost_per_unit_minor)), 0)
    INTO
        v_total_items_count,
        v_low_stock_count,
        v_out_of_stock_count,
        v_stock_valuation_minor
    FROM public.inventory_items
    WHERE restaurant_id = p_restaurant_id
      AND is_archived = FALSE
      AND deleted_at IS NULL;

    -- Wastage cost calculation from stock_movements
    SELECT COALESCE(SUM(ROUND(ABS(sm.quantity_change) * COALESCE(ii.cost_per_unit_minor, 0))), 0)
    INTO v_wastage_cost_minor
    FROM public.stock_movements sm
    LEFT JOIN public.inventory_items ii ON ii.id = sm.inventory_item_id
    WHERE sm.restaurant_id = p_restaurant_id
      AND sm.movement_type IN ('WASTAGE', 'DAMAGE')
      AND sm.created_at >= p_start_date
      AND sm.created_at <= p_end_date;

    -- 8. Kitchen Performance Metrics
    SELECT
        COALESCE(AVG(EXTRACT(EPOCH FROM (updated_at - created_at)))::INT, 0),
        COUNT(*) FILTER (WHERE status IN ('NEW_ORDER', 'PREPARING')),
        COUNT(*) FILTER (WHERE status = 'PREPARING' AND created_at < (now() - INTERVAL '20 minutes')),
        COUNT(*) FILTER (WHERE status IN ('READY', 'DELIVERED'))
    INTO
        v_avg_prep_time_seconds,
        v_active_tickets_count,
        v_delayed_tickets_count,
        v_completed_tickets_count
    FROM public.orders
    WHERE restaurant_id = p_restaurant_id
      AND created_at >= p_start_date
      AND created_at <= p_end_date
      AND status != 'CANCELLED'
      AND deleted_at IS NULL;

    -- 9. Table Floor Occupancy
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE status = 'OCCUPIED')
    INTO
        v_total_tables,
        v_occupied_tables
    FROM public.dining_tables
    WHERE restaurant_id = p_restaurant_id
      AND is_active = TRUE
      AND deleted_at IS NULL;

    IF v_total_tables > 0 THEN
        v_occupancy_rate := ROUND((v_occupied_tables::NUMERIC / v_total_tables::NUMERIC) * 100.0, 1);
    END IF;

    -- 10. Staff Attendance Summary
    SELECT
        COUNT(*) FILTER (WHERE status = 'CLOCKED_IN'),
        COUNT(*) FILTER (WHERE status = 'ON_BREAK'),
        COUNT(*) FILTER (WHERE is_late = TRUE AND clock_in >= p_start_date AND clock_in <= p_end_date)
    INTO
        v_clocked_in_count,
        v_on_break_count,
        v_late_arrivals_count
    FROM public.staff_attendance
    WHERE restaurant_id = p_restaurant_id;

    RETURN jsonb_build_object(
        'start_date', p_start_date,
        'end_date', p_end_date,
        'financial', jsonb_build_object(
            'gross_sales_minor', v_gross_sales_minor,
            'discounts_total_minor', v_discounts_total_minor,
            'net_sales_minor', v_net_sales_minor,
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
            'unpaid_orders_count', v_unpaid_orders_count,
            'avg_order_value_minor', v_avg_order_value_minor
        ),
        'order_types', v_order_types,
        'daily_trends', v_daily_trends,
        'product_analytics', jsonb_build_object(
            'top_selling', v_top_products,
            'least_selling', v_least_products
        ),
        'inventory', jsonb_build_object(
            'total_items_count', v_total_items_count,
            'low_stock_count', v_low_stock_count,
            'out_of_stock_count', v_out_of_stock_count,
            'stock_valuation_minor', v_stock_valuation_minor,
            'wastage_cost_minor', v_wastage_cost_minor
        ),
        'kitchen', jsonb_build_object(
            'avg_prep_time_seconds', v_avg_prep_time_seconds,
            'active_tickets_count', v_active_tickets_count,
            'delayed_tickets_count', v_delayed_tickets_count,
            'completed_tickets_count', v_completed_tickets_count
        ),
        'tables', jsonb_build_object(
            'total_tables', v_total_tables,
            'occupied_tables', v_occupied_tables,
            'occupancy_rate_percent', v_occupancy_rate
        ),
        'workforce', jsonb_build_object(
            'currently_clocked_in', v_clocked_in_count,
            'currently_on_break', v_on_break_count,
            'late_arrivals_count', v_late_arrivals_count
        )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_comprehensive_business_analytics TO authenticated;

