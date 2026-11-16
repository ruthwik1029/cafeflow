# CAFEFLOW — ROW LEVEL SECURITY & RBAC SPECIFICATION

**Version:** 1.0.0  
**Target:** Supabase PostgreSQL 17 Row Level Security  
**Guiding Principle:** Zero-Trust Client Architecture — RLS enforces authorization boundaries, never the client application.

---

## 1. Multi-Tenant Isolation Architecture

CafeFlow implements strict restaurant-level tenancy isolation. Every query against business data is scoped by `restaurant_id`. A user can only access records belonging to a restaurant where they possess an active, non-deleted membership record in `restaurant_memberships`.

Public website visitors (unauthenticated anonymous users) are restricted exclusively to published, active catalog items and cafe public details.

```mermaid
flowchart TD
    Client[Client Request] --> RLS[PostgreSQL RLS Engine]
    RLS --> CheckPublic{Is Public Table & Action?}
    CheckPublic -- Yes --> PubRule[Filter: is_active=true AND deleted_at IS NULL]
    CheckPublic -- No --> CheckAuth{Is Authenticated?}
    CheckAuth -- No --> Deny[42501 Access Denied]
    CheckAuth -- Yes --> EvalRole{Evaluate has_role() / is_restaurant_member()}
    EvalRole -- Match Allowed Role --> Allow[Execute SQL Query]
    EvalRole -- Role Mismatch --> Deny
```

---

## 2. Supported Roles

1. **`OWNER`**: Cafe proprietor with total operational, financial, and organizational control. Can edit cafe profile, manage memberships, adjust settings, and view all audit logs.
2. **`ADMIN`**: General manager or head of operations. Manages menus, categories, inventory, table layouts, staff duty, customer records, and reports. Cannot modify owner's role.
3. **`CASHIER`**: Front-of-house operator. Fires orders, applies discounts, records payments, seats tables, and looks up customer loyalty profiles.
4. **`KITCHEN`**: Back-of-house chef or barista. Views incoming KOT tickets, transitions ticket statuses (`NEW` -> `PREPARING` -> `READY`), monitors stock levels, and logs ingredient usage.
5. **`STAFF`**: Floor waitstaff. Views active menus, takes table orders, tracks active ticket status. Cannot view customer financial history, financial reports, or inventory costs.
6. **`PUBLIC`** (Unauthenticated): Customer on the web. Reads only active cafe information, categories, and available non-archived menu items.

---

## 3. Security Definer Helper Functions

To eliminate recursive RLS lookups and protect against search-path hijacking, helper functions are declared with `SECURITY DEFINER` and explicit `SET search_path = public`:

```sql
CREATE OR REPLACE FUNCTION public.has_role(target_restaurant_id UUID, allowed_roles app_role[])
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
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
        FROM restaurant_memberships
        WHERE restaurant_id = target_restaurant_id
          AND user_id = current_uid
          AND role = ANY(allowed_roles)
          AND is_active = true
          AND deleted_at IS NULL
    ) INTO has_match;

    RETURN has_match;
END;
$$;
```

---

## 4. Role Permission Matrix

| Table | Public Read | STAFF | KITCHEN | CASHIER | ADMIN | OWNER |
|---|---|---|---|---|---|---|
| `restaurants` | Active only | Member | Member | Member | Member | Full (Update) |
| `restaurant_settings`| Denied | View | View | View | Full | Full |
| `user_profiles` | Denied | Own+Colleagues| Own+Colleagues| Own+Colleagues| View all | View all |
| `restaurant_memberships`| Denied | View | View | View | Full (No self-promote) | Full |
| `menu_categories` | Active only | View | View | View | Full | Full |
| `menu_items` | Active/Unarchived| View all | View all | View all | Full | Full |
| `menu_item_variants`| Active only | View all | View all | View all | Full | Full |
| `menu_item_addons` | Active only | View all | View all | View all | Full | Full |
| `dining_tables` | Denied | View/Update | View | View/Update | Full | Full |
| `table_sessions` | Denied | View/Manage | View | View/Manage | Full | Full |
| `customers` | Denied | Denied | Denied | View/Create/Edit | Full | Full |
| `orders` | Denied | Create/View | View/Prep/Ready | Create/Pay/Cancel| Full | Full |
| `order_items` | Denied | Create/View | View | Create/View | Full | Full |
| `order_status_history`| Denied | View/Log | View/Log | View/Log | Full | Full |
| `payment_methods`| Denied | Denied | Denied | View | Full | Full |
| `payments` | Denied | Denied | Denied | Create/View | Full | Full |
| `inventory_categories`| Denied | Denied | View | Denied | Full | Full |
| `inventory_items`| Denied | Denied | View/Manage | Denied | Full | Full |
| `stock_movements`| Denied | Denied | View/Record | Denied | Full | Full |
| `audit_logs` | Denied | Denied | Denied | Denied | View only | View only |

---

## 5. Critical Security Protections

1. **Authentication Boundary:**
   - Supabase Auth handles identity.
   - Public self-registration is explicitly disabled (`enable_signup = false` in `supabase/config.toml`).
   - Staff accounts are provisioned exclusively by authorized `OWNER` or `ADMIN` roles.
   - Raw passwords or custom hash solutions are never permitted.

2. **Immutable Financial Records:**
   - `DELETE` operations are completely disabled on `payments` and `order_items`.
   - Orders can only be soft-cancelled (`status = 'CANCELLED'`) by authorized cashiers or administrators, preserving the audit trail.
   - Line items freeze item names and unit prices at creation time so future catalog adjustments do not rewrite previous receipts.

3. **Storage Security:**
   - Bucket `menu-images` allows public read access for menu rendering.
   - Mutation (`INSERT`, `UPDATE`, `DELETE`) is restricted by RLS to users possessing active `OWNER` or `ADMIN` memberships.

