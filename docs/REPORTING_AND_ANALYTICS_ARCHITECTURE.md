# CafeFlow Reporting & Analytics Architecture

## 1. System Overview

CafeFlow's Business Intelligence and Analytics engine is designed for high-performance, real-time multi-dimensional insight generation across restaurant operations. It aggregates data across six key operational pillars:

1. **Financial Accounting & Revenue**: Gross sales, promotional discounts, net revenue, GST liabilities, service charges, tendered collections, outstanding tabs, and issued refunds.
2. **Payment Reconciliations**: Cash drawer audit, UPI instant settlement records, card terminal collections, and payment discrepancy tracking.
3. **Menu & Product Performance**: Item sales volume, revenue generation, historical product snapshot preservation, best sellers, and low-turnover items.
4. **Inventory Valuation & Wastage**: Stock balance evaluation, inventory asset worth, wastage cost computation, and low-stock replenishment alerts.
5. **Kitchen Throughput**: Average ticket preparation duration, delayed ticket detection (>20 minutes), and queue volume.
6. **Floor & Workforce Utilization**: Dining table occupancy rates, active staff clocked in, scheduled breaks, and punctuality audit records.

---

## 2. Server-Side Aggregation RPC

To eliminate client-side N+1 query bottlenecks, CafeFlow delegates analytical computation to the Supabase PostgreSQL database via a secure, single-roundtrip RPC function:

```sql
public.get_comprehensive_business_analytics(
    p_restaurant_id UUID,
    p_start_date TIMESTAMPTZ,
    p_end_date TIMESTAMPTZ
) RETURNS JSONB
```

### Performance & Security Guarantees:
- **Security Check (SEC-01)**: Enforces that `auth.uid()` has an active membership of `OWNER` or `ADMIN` for the queried `p_restaurant_id`. Unauthorized callers receive a `42501` exception.
- **Dedicated Analytical Indexes**:
  - `idx_orders_restaurant_created_status` on `(restaurant_id, created_at, status)`
  - `idx_orders_financial_status` on `(restaurant_id, financial_status, created_at)`
  - `idx_payments_restaurant_status_created` on `(restaurant_id, status, created_at)`
  - `idx_order_items_product_lookup` on `(order_id, product_name, quantity, total_minor)`
  - `idx_refunds_restaurant_date` on `(restaurant_id, refunded_at)`
  - `idx_stock_movements_wastage` on `(restaurant_id, movement_type, created_at)`
  - `idx_staff_attendance_restaurant_status` on `(restaurant_id, status, clock_in)`

---

## 3. Client Architecture

### Domain Layer (`lib/features/reports/domain/analytics_models.dart`)
- **`ComprehensiveAnalytics`**: Root immutable domain container.
- **`FinancialAnalyticsReport`**: Strictly integer-minor (`_minor`) financial ledger.
- **`OrderTypeMetric`**: Dine-in vs Takeaway vs Delivery volume and sales.
- **`DailyTrendMetric`**: Daily sales and order volume time-series.
- **`ProductSalesMetric`**: Aggregated quantity and revenue by product snapshot name.
- **`InventoryAnalyticsMetric`**: Asset valuation and shrinkage loss metrics.
- **`KitchenAnalyticsMetric`**: Ticket timing and delayed queue metrics.
- **`TableAnalyticsMetric`**: Occupancy count and percentage rate.
- **`WorkforceAnalyticsMetric`**: Clocked-in personnel, break status, and tardiness.
- **`AnalyticsTimePreset`**: Standardized date bounds (Today, Yesterday, Last 7 Days, Last 30 Days, This Month, All Time, Custom).
- **`AnalyticsCsvExporter`**: RFC-4180 compliant CSV serializer with character escaping.

### Data Layer (`lib/features/reports/data/analytics_repository.dart`)
- **`AnalyticsRepository`**: Abstract contract defining `fetchComprehensiveAnalytics` and `watchAnalyticsInvalidations`.
- **`SupabaseAnalyticsRepository`**: Executes the PostgreSQL RPC and subscribes to real-time invalidation channels.
- **`DemoAnalyticsRepository`**: Deterministic fallback engine computing live metrics from in-memory state during demo and offline modes.

### Presentation Layer
- **`ReportsPage`**: Full multi-tab analytical console with 5 segmented dimensions, time-preset filtering, CSV export modal, and printable executive summary preview.
- **`AdminDashboardPage`**: Real-time operations console featuring live revenue, kitchen tickets, table occupancy, inventory alerts, top products, and recent orders.
- **`OwnerOverviewPage`**: Pocket management console optimized for mobile and tablet monitoring with tender breakdown and sync freshness.

