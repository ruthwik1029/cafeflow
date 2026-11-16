# CafeFlow — Stock Movement Ledger & Recipe Deduction Rules

## 1. Immutable Stock Movement Ledger

Every change to inventory stock levels in CafeFlow is logged as an immutable row in `stock_movements`. Direct updates to `inventory_items.current_stock` without ledger entries are prohibited by database design.

### Canonical Movement Types:
1. `PURCHASE`: Incoming shipments received from suppliers or vendors.
2. `SALE_CONSUMPTION`: Automatic recipe ingredient deduction triggered upon customer order confirmation.
3. `MANUAL_ADJUSTMENT`: Physical stock audit reconciliations or cycle count corrections.
4. `WASTAGE`: Spoilage, expired stock, milk dumping, or kitchen training loss.
5. `DAMAGE`: Dropped bottles, broken packaging, or transit handling damage.
6. `RETURN`: Stock returned to supplier for credit or refund.
7. `TRANSFER`: Inter-branch or inter-station inventory relocations.
8. `REVERSAL`: Compensating transaction reversing an erroneous adjustment or cancelled receipt.

---

## 2. Recipe Ingredient Binding & Bill of Materials (BOM)

Recipes map finished menu items in the digital catalog to one or more raw inventory items via `menu_item_ingredients`:

$$\text{Total Deducted} = \text{Order Item Quantity} \times \text{Recipe Ingredient Quantity}$$

### Example Recipe:
- **Cappuccino (CF-PROD-CAP)**:
  - `House espresso beans`: 0.018 kg (18 grams)
  - `Organic whole milk`: 0.150 L (150 millilitres)

---

## 3. Idempotent Recipe Deduction Engine (`deduct_order_recipe_stock`)

When an order transitions to `CONFIRMED` or is received through offline synchronization, the database invokes the transactional RPC `deduct_order_recipe_stock`:

```sql
CREATE OR REPLACE FUNCTION deduct_order_recipe_stock(
    p_restaurant_id UUID,
    p_order_id UUID
)
```

### Safety & Idempotency Rules:
1. **Zero Double-Counting**:
   Before deducting stock, the function checks if movements with `reference = p_order_id` and `movement_type = 'SALE_CONSUMPTION'` already exist:
   ```sql
   IF EXISTS (
       SELECT 1 FROM stock_movements
       WHERE restaurant_id = p_restaurant_id
         AND reference = p_order_id::TEXT
         AND movement_type = 'SALE_CONSUMPTION'
   ) THEN
       RETURN jsonb_build_object('success', true, 'status', 'ALREADY_DEDUCTED');
   END IF;
   ```
2. **Atomic Row Locks**:
   The function acquires row-level locks on `order_items` and target `inventory_items` using `FOR UPDATE`, preventing race conditions during simultaneous order finalization.
3. **Ledger Integrity**:
   Every deducted ingredient generates a `stock_movements` record with:
   - `quantity_change`: Negative value ($-\Delta$)
   - `previous_stock`: Verified stock level immediately prior to deduction
   - `new_stock`: $\text{previous\_stock} - \Delta$
   - `reference`: `p_order_id`
   - `reason`: 'Recipe deduction for order <order_id>'

---

## 4. Cancellation & Refund Policy
- If an order is cancelled **before preparation**, ingredients may be reversed back to stock using `movement_type = 'REVERSAL'`.
- If an order is cancelled or refunded **after preparation has begun or finished**, the ingredients are already physically consumed or wasted. The stock is **not** restored to sellable inventory; instead, it is classified under `WASTAGE` or remains as `SALE_CONSUMPTION` with financial refund handled at the billing ledger level.

