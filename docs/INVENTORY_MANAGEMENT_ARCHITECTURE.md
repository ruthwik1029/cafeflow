# CafeFlow — Inventory Management Architecture

## 1. System Overview & Scope
CafeFlow's Inventory Management engine provides real-time stock visibility, immutable transition ledgering, recipe ingredient binding with automated consumption, multi-vendor supplier registry, and purchase receiving workflows.

The system is designed for high-concurrency cafe environments where inventory must remain reliable across physical registers, kitchen stations, administrative dashboards, and offline mobile clients.

---

## 2. Core Entities & Schema Design

```
+------------------------------------+          +------------------------------------+
|             suppliers              |          |        inventory_categories        |
+------------------------------------+          +------------------------------------+
| id (UUID, PK)                      |          | id (UUID, PK)                      |
| restaurant_id (UUID, FK)           |          | restaurant_id (UUID, FK)           |
| name, contact_name, phone, email   |          | name, description, sort_order      |
| address, notes, is_active          |          +-----------------+------------------+
+-----------------+------------------+                            |
                  |                                               |
                  | 1:N                                           | 1:N
                  v                                               v
+-----------------+-----------------------------------------------+------------------+
|                                  inventory_items                                   |
+------------------------------------------------------------------------------------+
| id (UUID, PK)                                                                      |
| restaurant_id (UUID, FK)                                                           |
| name, sku, unit, storage_location                                                  |
| current_stock, minimum_stock, reorder_level (NUMERIC(12, 3))                       |
| cost_per_unit_minor (INTEGER NOT NULL DEFAULT 0)                                   |
| is_archived (BOOLEAN NOT NULL DEFAULT FALSE)                                       |
+-----------------+-----------------------------------------------+------------------+
                  |                                               |
                  | 1:N                                           | 1:N
                  v                                               v
+-----------------+------------------+          +-----------------+------------------+
|         stock_movements            |          |      menu_item_ingredients         |
+------------------------------------+          +------------------------------------+
| id (UUID, PK)                      |          | id (UUID, PK)                      |
| restaurant_id (UUID, FK)           |          | restaurant_id (UUID, FK)           |
| inventory_item_id (UUID, FK)       |          | menu_item_id (UUID, FK)            |
| movement_type (ENUM)               |          | inventory_item_id (UUID, FK)       |
| quantity_change, previous_stock    |          | quantity (NUMERIC(12, 3))          |
| new_stock, unit, reference, reason |          | unit (TEXT)                        |
| client_tx_id, performed_by         |          | UNIQUE(menu_item_id, inv_item_id)  |
+------------------------------------+          +------------------------------------+
```

### Key Columns & Constraints:
- `cost_per_unit_minor`: Explicit integer representation of currency minor units (cents/paise), eliminating floating-point rounding errors across valuation calculations.
- `current_stock`, `minimum_stock`, `reorder_level`: `NUMERIC(12, 3)` supporting high-precision fractional weights (e.g. 0.018 kg dose for an espresso shot).
- `client_tx_id`: UUID/hash tracking client origin for offline synchronization idempotency.

---

## 3. Stock Thresholds & Dynamic Valuation

1. **Optimal Stock**: `current_stock > reorder_level`
2. **Low Stock Alert**: `current_stock <= reorder_level AND current_stock > 0`
3. **Out of Stock**: `current_stock <= 0`
4. **Stock Valuation Formula**:
   $$\text{Stock Valuation (Minor Units)} = \text{round}(\text{current\_stock} \times \text{cost\_per\_unit\_minor})$$

---

## 4. Workspaces & UI Presentation
- **Items & Stock**: Comprehensive catalog with live stock counts, SKU, category filters, and immediate restock / adjustment dialogs.
- **Stock Ledger**: Immutable chronological transition log with delta, previous/resulting stock, reason, and actor identification.
- **Suppliers**: Vendor database with contact directory, address, and purchase links.
- **Purchase Orders**: Purchase lifecycle management from initial order generation to physical receipt.
- **Recipes & BOM**: Bill of materials linking catalog products to raw inventory ingredients.

---

## 5. Security & Tenant Isolation
- **Row-Level Security (RLS)**: Strictly bound by `restaurant_id = ANY(get_user_restaurant_ids())`.
- **Role Permissions**:
  - `OWNER` & `ADMIN`: Full CRUD on inventory, categories, suppliers, and purchase orders.
  - `KITCHEN`: View inventory, adjust stock, log wastage. Strictly restricted from creating financial purchase orders or editing vendor terms.
  - `CASHIER` & `STAFF`: Read-only stock lookup; cannot modify inventory baselines.

