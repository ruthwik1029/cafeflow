# CafeFlow — Billing Architecture Specification

## 1. Architectural Overview

CafeFlow implements an end-to-end, multi-tenant billing and settlement architecture designed for restaurant and cafe point-of-sale environments. The system guarantees financial integrity, strict tenant isolation via PostgreSQL Row Level Security (RLS), ACID-compliant transactional settlement, safe fixed-precision monetary math, and realtime multi-station synchronization across Windows Cashier/Owner terminals, Android Staff devices, and Kitchen Display Systems (KDS).

```mermaid
flowchart TD
    subgraph UI ["Client Presentation Layer (Flutter Desktop & Mobile)"]
        POS["POS Cashier Register\n(pos_page.dart)"]
        Orders["Orders Management\n(orders_page.dart)"]
        Reports["Financial Analytics\n(reports_page.dart)"]
        Settings["Tax & Methods Settings\n(settings_page.dart)"]
    end

    subgraph State ["State Management Layer (Riverpod 2.x)"]
        Cart["CartController\n(cart_controller.dart)"]
        PayProv["PaymentProviders\n(payment_provider.dart)"]
        OrdProv["OrdersProvider\n(orders_provider.dart)"]
    end

    subgraph DomainRepo ["Domain & Repository Layer"]
        Domain["Domain Models & Enums\n(payment_models.dart, cafe_order.dart)"]
        PayRepo["PaymentRepository\n(supabase_payment_repository.dart)"]
        OrdRepo["OrderRepository\n(supabase_order_repository.dart)"]
    end

    subgraph Gateway ["Infrastructure & Network Layer"]
        DBGate["DatabaseGateway (Read-Only)"]
        RTGate["CafeRealtimeService (Postgres Changes)"]
        SupaClient["SupabaseClient (Transactional RPCs)"]
    end

    subgraph DB ["PostgreSQL Database (Supabase Cloud / Local)"]
        Tables["Tables: orders, order_items, payments, refunds, payment_methods, restaurant_settings"]
        RPC1["RPC: create_order_with_items"]
        RPC2["RPC: record_order_payment"]
        RPC3["RPC: refund_order_payment"]
        RPC4["RPC: get_financial_report"]
        RLS["Row Level Security & Tenant Isolation"]
    end

    POS --> Cart
    Cart --> PayProv
    Orders --> OrdProv
    Reports --> PayProv
    Settings --> PayProv

    PayProv --> PayRepo
    OrdProv --> OrdRepo
    PayRepo --> SupaClient
    PayRepo --> DBGate
    PayRepo --> RTGate
    OrdRepo --> SupaClient
    OrdRepo --> DBGate

    SupaClient --> RPC1
    SupaClient --> RPC2
    SupaClient --> RPC3
    SupaClient --> RPC4
    DBGate --> Tables
    RTGate --> Tables
    RPC1 --> Tables
    RPC2 --> Tables
    RPC3 --> Tables
    RPC4 --> Tables
    Tables --> RLS
```

---

## 2. Core Billing Principles

### 2.1 Fixed-Precision Monetary Representation
Floating-point numbers (`double` or `float`) are strictly forbidden in CafeFlow financial calculations to prevent IEEE 754 rounding drift, off-by-one errors, and ledger discrepancies.
- All monetary values in PostgreSQL and Flutter are stored and calculated as 64-bit integer minor units (paise in India, cents in US/EU):
  $$\text{Amount}_{\text{minor}} = \text{Amount}_{\text{major}} \times 100$$
- Database schema uses `BIGINT` for all `*_minor` columns.
- Display formatting formats minor units with explicit two-decimal precision:
  $$\text{Formatted} = \text{₹} + \frac{\text{minor}}{100.0}$$
- Text input parsing uses string integer decomposition:
  $$\text{minor} = (\text{integral} \times 100) + \text{fractional}$$

### 2.2 Server-Validated Financial Calculations
Client-submitted line totals, taxes, and grand totals are treated as untrusted user input.
- Flutter `CartController` performs live client-side calculations solely for instant cashier feedback and user interface reactivity.
- When an order is submitted, `create_order_with_items` fetches authentic menu item prices directly from `public.menu_items`, verifies that each item belongs to the caller's restaurant tenant, reads authentic tax rate and inclusive flags from `public.restaurant_settings`, and calculates:
  - Line totals: $\text{quantity} \times \text{price\_minor}$
  - Order subtotal: $\sum \text{line\_total}$
  - Taxable subtotal: $\max(0, \text{subtotal} - \text{discount\_minor})$
  - Service charge: $(\text{taxable} \times \text{service\_charge\_bps} + 5000) / 10000$
  - Exclusive tax (if configured): $(\text{taxable} \times \text{tax\_rate\_bps} + 5000) / 10000$
  - Inclusive tax (if configured): $(\text{taxable} \times \text{tax\_rate\_bps}) / (10000 + \text{tax\_rate\_bps})$
  - Grand total: $\text{taxable} + \text{tax}_{\text{exclusive}} + \text{service\_charge}$
- This design prevents malicious price tampering, unauthorized discounts, or stale cached prices.

### 2.3 Decoupling Kitchen Status from Financial Status
To reflect physical restaurant workflows accurately, operational food preparation is cleanly decoupled from financial billing settlement:
1. **Operational Order Status (`order_status` enum)**:
   - `NEW`: Order ticket created at register or table.
   - `PREPARING`: Kitchen staff has accepted and begun preparing tickets.
   - `READY`: Kitchen pass has finished; ready for plating or counter pickup.
   - `COMPLETED`: Food delivered to guest and table vacated.
   - `CANCELLED`: Order aborted.
2. **Financial Status (`order_financial_status` enum)**:
   - `UNPAID`: Order tab open; balance due equals grand total.
   - `PARTIALLY_PAID`: Deposit or split payment received; remaining balance $> 0$.
   - `PAID`: Full settlement received; outstanding balance $= 0$.
   - `PARTIALLY_REFUNDED`: Authorized refund returned part of paid funds; food order intact.
   - `REFUNDED`: Total paid funds returned to customer.
   - `PAYMENT_FAILED`: Terminal decline or rejected transaction.

This decoupling allows flexible operational models:
- **Fast-Casual / Counter Service**: Pay-now flow (order creation and payment recording execute atomically within the same cashier interaction).
- **Full Dine-In Service**: Pay-later flow (kitchen prepares and serves order while financial status remains `UNPAID`; cashier settles bill at end of dining experience).

---

## 3. Database Schema & Relational Model

```mermaid
erDiagram
    RESTAURANTS ||--o{ RESTAURANT_SETTINGS : "configures"
    RESTAURANTS ||--o{ PAYMENT_METHODS : "offers"
    RESTAURANTS ||--o{ ORDERS : "owns"
    ORDERS ||--|{ ORDER_ITEMS : "contains"
    ORDERS ||--o{ PAYMENTS : "receives"
    ORDERS ||--o{ REFUNDS : "adjusts"
    PAYMENTS ||--o{ REFUNDS : "refunds against"
    RESTAURANTS ||--o{ AUDIT_LOGS : "logs"

    RESTAURANTS {
        uuid id PK
        text name
        text code
    }

    RESTAURANT_SETTINGS {
        uuid id PK
        uuid restaurant_id FK
        text tax_name
        integer gst_rate_basis_points
        boolean tax_is_inclusive
        integer service_charge_basis_points
        text service_charge_name
        text currency
    }

    PAYMENT_METHODS {
        uuid id PK
        uuid restaurant_id FK
        text code
        text display_name
        boolean is_active
    }

    ORDERS {
        uuid id PK
        uuid restaurant_id FK
        text order_number
        order_status status
        order_financial_status financial_status
        bigint subtotal_minor
        bigint discount_minor
        text discount_reason
        uuid discount_authorized_by
        text tax_name
        integer tax_rate_basis_points
        boolean tax_is_inclusive
        bigint tax_minor
        bigint service_charge_minor
        bigint total_minor
        bigint paid_amount_minor
        bigint refunded_amount_minor
        timestamptz created_at
    }

    PAYMENTS {
        uuid id PK
        uuid restaurant_id FK
        uuid order_id FK
        uuid payment_method_id FK
        text payment_method_code
        bigint amount_minor
        text status
        bigint tendered_amount_minor
        bigint change_due_minor
        text transaction_reference
        text idempotency_key
        uuid processed_by FK
        timestamptz created_at
    }

    REFUNDS {
        uuid id PK
        uuid restaurant_id FK
        uuid order_id FK
        uuid payment_id FK
        bigint amount_minor
        text reason
        uuid refunded_by FK
        text idempotency_key
        timestamptz refunded_at
    }
```

---

## 4. Multi-Tenant Isolation & Role-Based Security

### 4.1 Row Level Security (RLS) Policies
Every table in the financial pipeline enforces RLS:
- **`public.payments`**:
  - `SELECT`: Restricted to authenticated members of the restaurant tenant (`tenant_has_active_membership(restaurant_id)`). Kitchen staff is barred by application routing from accessing financial ledger tables.
  - `INSERT / UPDATE`: Must pass through audited `SECURITY DEFINER` stored procedure `record_order_payment`, preventing arbitrary direct table inserts.
- **`public.refunds`**:
  - `SELECT`: Restricted to `OWNER` and `ADMIN` tenant members. Cashiers and kitchen staff cannot read refund audit logs.
  - `INSERT`: Strictly restricted to `OWNER` and `ADMIN` via `refund_order_payment` RPC.
- **`public.payment_methods`**:
  - `SELECT`: Readable by all authenticated restaurant staff (`tenant_has_active_membership(restaurant_id)`).
  - `UPDATE`: Modifiable only by `OWNER` and `ADMIN` via `update_payment_method_status` RPC.

### 4.2 Idempotency & Concurrency Control
Payment and refund operations accept an optional `p_idempotency_key` (UUID v4 or deterministic client transaction hash):
- Before processing a payment, the RPC queries `public.payments` for existing records with the same `(restaurant_id, idempotency_key)`.
- If found, the existing payment result is replayed immediately without incrementing totals or creating duplicate cash entries.
- Concurrent updates to the same order lock the target row via `SELECT ... FROM public.orders WHERE id = p_order_id FOR UPDATE`, eliminating race conditions when multiple cashiers attempt to settle the same bill simultaneously.

---

## 5. Audit Logging & Compliance

All financial actions automatically write immutable entries to `public.audit_logs`:
- **`PAYMENT_RECORDED`**: Records `order_id`, `payment_id`, `amount_minor`, `method_code`, `processed_by`, and change tendered.
- **`PAYMENT_REFUNDED`**: Records `order_id`, `payment_id`, `refund_id`, `refund_amount_minor`, `reason`, and `authorized_by`.
- **`TAX_SETTINGS_UPDATED`**: Records changes to GST rates, inclusive tax mode, or service surcharge basis points.
- **`PAYMENT_METHOD_TOGGLED`**: Records status adjustments to Cash, UPI, or Card acceptance.

