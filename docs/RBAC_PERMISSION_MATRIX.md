# CafeFlow — Role-Based Access Control (RBAC) Matrix

**Document Version:** 1.0.0  
**Phase:** 04 — Authentication, RBAC & Security Hardening  

---

## 1. Role Definitions

CafeFlow implements five distinct operational and administrative roles:

| Role | Classification | Description |
|---|---|---|
| **`OWNER`** | Primary Executive | The legal proprietor of the restaurant entity. Has absolute control over restaurant profile, billing accounts, staff provisioning, and ownership management. |
| **`ADMIN`** | Operations Manager | Operational general manager. Controls inventory, menus, tables, reporting, and staff provisioning. Cannot grant or revoke `OWNER` status (SEC-01). |
| **`CASHIER`** | Front of House / Billing | Counter cashier and point-of-sale operator. Creates orders, applies approved discounts, processes payments, and views table statuses. |
| **`KITCHEN`** | Back of House / Kitchen | Kitchen Display System (KDS) and KOT operator. Receives tickets, updates order prep status (`new` -> `prep` -> `ready`), and checks ingredient levels. |
| **`STAFF`** | Floor Staff / Server | Table attendants and waitstaff. Takes table orders, reviews menus, checks order statuses, and monitors table occupancy. |

---

## 2. Centralized Permission Matrix

All authorization checks in Dart code use the centralized `CafePermission` enum (`lib/features/auth/domain/permissions.dart`) evaluated through `RolePermissions.hasPermission(role, permission)`:

| Permission | Description | `OWNER` | `ADMIN` | `CASHIER` | `KITCHEN` | `STAFF` |
|---|---|:---:|:---:|:---:|:---:|:---:|
| `viewDashboard` | Access executive summary & KPIs | Yes | Yes | No | No | No |
| `viewMenu` | Browse available catalog & categories | Yes | Yes | Yes | No | Yes |
| `manageMenu` | Create, edit, and archive menu items | Yes | Yes | No | No | No |
| `createOrders` | Initiate customer tickets & add items | Yes | Yes | Yes | No | Yes |
| `viewOrders` | View incoming and active tickets | Yes | Yes | Yes | Yes | Yes |
| `updateKitchenOrders` | Advance order status (`prep`, `ready`) | Yes | Yes | No | Yes | No |
| `processPayments` | Settle bills and collect payments | Yes | Yes | Yes | No | No |
| `manageTables` | Manage table seating, layout & status | Yes | Yes | Yes | No | Yes |
| `manageInventory` | Update stock counts & alert levels | Yes | Yes | No | Yes | No |
| `viewReports` | Access financial audits & sales analytics | Yes | Yes | No | No | No |
| `manageStaff` | Provision team members & assign roles | Yes | Yes | No | No | No |
| `manageSettings` | Adjust cafe configuration & hardware | Yes | Yes | No | No | No |
| **`manageOwnership`** | **Transfer or assign OWNER role (SEC-01)** | **Yes** | **NO** | **No** | **No** | **No** |

---

## 3. Database RLS Role Enforcement

PostgreSQL Row-Level Security (RLS) mirrors this matrix at the database layer using PostgreSQL helper functions:

```sql
-- Role detection helpers defined in 20261114000002_rls_policies.sql
app_user_has_role(restaurant_id, 'OWNER')
app_user_has_role(restaurant_id, 'ADMIN')
app_user_has_role(restaurant_id, 'CASHIER')
app_user_has_role(restaurant_id, 'KITCHEN')
app_user_has_role(restaurant_id, 'STAFF')
```

### Table Access Boundaries

| Table | `OWNER` / `ADMIN` | `CASHIER` | `KITCHEN` | `STAFF` | Public Visitor |
|---|---|---|---|---|---|
| `restaurants` | Full Read/Update | Read Only | Read Only | Read Only | Active Only |
| `restaurant_memberships` | Managed (SEC-01) | Read Own | Read Own | Read Own | None |
| `user_profiles` | Read Tenant Profiles | Read Own | Read Own | Read Own | None |
| `menu_categories` | Full CRUD | Read Only | None | Read Only | Active Only |
| `menu_items` | Full CRUD | Read Active | None | Read Active | Active Only |
| `menu_item_variants` (SEC-02)| Full CRUD | Read Active | None | Read Active | Active Only |
| `menu_item_addons` (SEC-02)  | Full CRUD | Read Active | None | Read Active | Active Only |
| `dining_tables` | Full CRUD | Read/Update | Read Only | Read Only | None |
| `orders` (SEC-03) | Full CRUD | Insert/Read | Read/RPC | Insert/Read | None |
| `order_items` | Full CRUD | Insert/Read | Read Only | Insert/Read | None |
| `payments` | Full CRUD | Insert/Read | None | None | None |
| `inventory_items` | Full CRUD | Read Only | Read/Update | Read Only | None |
| `inventory_transactions` | Full CRUD | None | Insert/Read | None | None |

---

## 4. Tenant Isolation

All multi-tenant tables feature `restaurant_id UUID REFERENCES restaurants(id)`. 
RLS policies unconditionally enforce that `restaurant_id` must match a membership held by the authenticated user (`auth.uid()`):

```sql
CREATE POLICY "orders_tenant_isolation" ON public.orders
FOR ALL TO authenticated
USING (
    restaurant_id IN (
        SELECT restaurant_id FROM public.restaurant_memberships
        WHERE user_id = auth.uid() AND is_active = TRUE
    )
);
```

Cross-tenant reads, modifications, or injections are rejected at the PostgreSQL kernel level.

