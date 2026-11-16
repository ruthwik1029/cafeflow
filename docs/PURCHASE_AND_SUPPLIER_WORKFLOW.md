# CafeFlow — Purchase Orders & Supplier Receiving Workflow

## 1. Overview
The purchase and supplier subsystem enables cafe operators to track supplier contracts, draft purchase orders, calculate tax and delivery charges, and receive inventory shipments with atomic stock replenishment.

---

## 2. Supplier Lifecycle
1. **Registration**:
   - Authorized roles (`OWNER`, `ADMIN`) create supplier profiles with contact name, phone, email, delivery terms, and address.
2. **Item Linkage**:
   - Inventory items reference a primary `supplier_id` for automated reorder suggestions.
3. **Status Control**:
   - Inactive suppliers are flagged (`is_active = FALSE`) and filtered out from new purchase orders while preserving historical orders.

---

## 3. Purchase Order Lifecycle

```
[ DRAFT / ORDERED ]  -- (Delivery Arrives) --> [ RECEIVING WORKFLOW ] --> [ RECEIVED ]
        |                                                                      |
        v                                                                      v
  (Stock Unchanged)                                                      (Stock Increment +
                                                                         Immutable Ledger Entry)
```

1. **Order Creation (`status = 'ORDERED'`)**:
   - PO generated with line items (`purchase_items`), target quantities, and agreed unit costs in minor units (`unit_cost_minor`).
   - **Crucial Rule**: Physical inventory stock is **NOT** incremented when a purchase order is created.
2. **Receiving Workflow (`receive_purchase_order`)**:
   - Triggered when shipment physically arrives at the cafe.
   - Invokes transactional RPC `receive_purchase_order(p_restaurant_id, p_purchase_id, p_received_by)`.
   - Checks that purchase order is not already received:
     ```sql
     IF v_purchase.status = 'RECEIVED' THEN
         RAISE EXCEPTION 'Purchase order has already been received.';
     END IF;
     ```
   - Loops through each line item in `purchase_items`:
     - Updates `quantity_received = quantity`.
     - Acquires `FOR UPDATE` lock on `inventory_items`.
     - Increments `current_stock = current_stock + item.quantity`.
     - Inserts `stock_movements` row with `movement_type = 'PURCHASE'`, `reference = purchase_number`.
   - Updates purchase header: `status = 'RECEIVED'`, `received_at = NOW()`, `received_by = auth.uid()`.
   - Inserts `staff_audit_events` row: `event_type = 'PURCHASE_RECEIVED'`.

---

## 4. Financial Calculations in Minor Units
All financial values across purchase orders and inventory costs are strictly stored as 64-bit integer minor currency units:
- `subtotal_minor`: Sum of line item quantities multiplied by unit costs.
- `tax_minor`: Applicable vendor tax (e.g., 5% GST/VAT).
- `additional_charges_minor`: Freight, shipping, packaging, or handling fees.
- `total_minor`: $\text{subtotal\_minor} + \text{tax\_minor} + \text{additional\_charges\_minor}$.
- Zero floating-point rounding errors or precision discrepancies.

