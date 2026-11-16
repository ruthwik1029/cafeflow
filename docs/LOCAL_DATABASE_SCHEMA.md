# CafeFlow — Local Database Schema Specification

## 1. Overview & Storage Engine

`CafeLocalDatabase` stores structured document collections in key-value format via `LocalStorageAdapter` (`SharedPreferencesStorageAdapter` in production; `MemoryStorageAdapter` for isolated testing).

Key prefix: `cafeflow_db_v1_col_<collection_name>`
Schema Version: `1`

## 2. Collections & Document Structures

### Collection: `orders`
Stores local and cached orders.
- `id` (String): Local or server order ID (e.g. `local_ord_1771178239012`).
- `client_tx_id` (String): Client-generated transaction UUID for cloud deduplication.
- `restaurant_id` (String): Multi-tenant isolation key.
- `order_number` (String): Human-readable ticket number (e.g. `OFFLINE-1284`).
- `table_name` (String): Dining table or takeaway designation.
- `special_instructions` (String): Dietary or prep instructions.
- `subtotal_minor` (int): Total gross sum before discount/tax.
- `discount_minor` (int): Fixed discount in integer minor units.
- `discount_reason` (String): Reason for discount.
- `tax_name` (String): Configured tax label (e.g. `GST`).
- `tax_rate_basis_points` (int): Tax percentage in basis points (e.g. `500` for 5%).
- `tax_is_inclusive` (bool): Whether prices are tax-inclusive.
- `tax_minor` (int): Total computed tax in minor units.
- `service_charge_minor` (int): Additional charges in minor units.
- `total_minor` (int): Final payable grand total.
- `status` (String): `NEW`, `PREPARING`, `READY`, `COMPLETED`, `CANCELLED`.
- `financial_status` (String): `UNPAID`, `PARTIALLY_PAID`, `PAID`, `REFUNDED`.
- `paid_amount_minor` (int): Amount collected so far.
- `refunded_amount_minor` (int): Amount refunded so far.
- `sync_status` (String): `PENDING`, `PROCESSING`, `SYNCED`, `RETRY`, `CONFLICT`, `FAILED`.
- `server_order_id` (String?): Cloud database ID once acknowledged.
- `created_at` (String ISO8601): Creation timestamp.
- `lines` (List<Map>): Array of line item summaries.

### Collection: `order_items`
Individual line item breakdown per order.
- `id` (String): Local order item ID.
- `order_id` (String): Foreign reference to parent order.
- `restaurant_id` (String): Tenant ID.
- `menu_item_id` (String): Cloud catalog item ID.
- `item_name` (String): Display name.
- `unit_price_minor` (int): Price per unit in minor units.
- `quantity` (int): Ordered quantity.
- `subtotal_minor` (int): `unit_price_minor * quantity`.

### Collection: `payments`
Settlement records created offline or cached from cloud.
- `id` (String): Local payment ID (e.g. `local_pay_1771178239012`).
- `client_tx_id` (String): Transaction UUID for cloud idempotency.
- `restaurant_id` (String): Tenant ID.
- `local_order_id` (String): Parent order reference.
- `payment_method_code` (String): `CASH`, `UPI`, `CARD`.
- `amount_minor` (int): Payment amount in minor units.
- `tendered_amount_minor` (int?): Cash amount handed by customer.
- `change_due_minor` (int?): Change returned to customer.
- `transaction_reference` (String?): Reference or authorization code.
- `notes` (String): Settlement notes.
- `status` (String): `PENDING_SYNC` (Cash) or `PENDING_RECONCILIATION` (Digital).
- `sync_status` (String): `PENDING`, `SYNCED`, `FAILED`.
- `requires_reconciliation` (bool?): Flag for offline digital authorizations.
- `created_at` (String ISO8601).

### Collection: `sync_queue`
Durable pending synchronization operations.
- `id` (String): Queue operation ID (`sq_ord_...` or `sq_pay_...`).
- `client_tx_id` (String): Transaction UUID.
- `restaurant_id` (String): Tenant ID.
- `entity_type` (String): `ORDER`, `PAYMENT`, `CATALOG`.
- `entity_id` (String): Local document ID.
- `operation_type` (String): `CREATE_ORDER`, `RECORD_PAYMENT`, `UPDATE_STATUS`.
- `payload` (Map): Serializable parameters sent to the cloud RPC.
- `local_version` (int): Optimistic locking version.
- `base_server_version` (int): Base version when read.
- `status` (String): `PENDING`, `PROCESSING`, `SYNCED`, `RETRY`, `CONFLICT`, `FAILED`.
- `retry_count` (int): Failed attempts count.
- `last_error` (String?): Last error description.
- `next_retry_at` (String ISO8601?): Timestamp before which retry is skipped.
- `created_at` (String ISO8601).

### Collection: `sync_conflicts`
Records of rejected or conflicting transactions requiring manual resolution.
- `id` (String): Conflict UUID.
- `restaurant_id` (String): Tenant ID.
- `entity_type` (String): Target entity.
- `entity_id` (String): Document ID.
- `conflict_reason` (String): Human-readable reason.
- `client_payload` (Map): The payload sent by client.
- `server_payload` (Map?): Conflicting server data.
- `created_at` (String ISO8601).

