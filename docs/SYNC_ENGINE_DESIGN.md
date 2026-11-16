# CafeFlow — Synchronization Engine Design

## 1. Overview

The CafeFlow Synchronization Engine (`CafeSyncService` and `SyncQueue`) orchestrates background synchronization between the local document database and the Supabase cloud backend.

```
       +--------------------------------------------+
       |             CafeSyncService                |
       |  - Periodic or Manual Trigger             |
       |  - Reachability Verification (Ping probe)  |
       +---------------------+----------------------+
                             |
                             v
       +--------------------------------------------+
       |             SyncQueue                      |
       |  - Reads pending items for restaurant      |
       |  - Filters out items awaiting retry delay  |
       |  - Enforces dependency order               |
       +---------------------+----------------------+
                             |
                   +---------+---------+
                   |                   |
                   v                   v
            [Orders First]     [Payments Second]
                   |                   |
                   v                   v
         create_order_with_items  record_order_payment
                   |                   |
                   +---------+---------+
                             |
                             v
           +-----------------------------------+
           |        Process Response           |
           | - Success -> markSynced           |
           | - Network Error -> markRetry      |
           | - Conflict -> markConflict        |
           +-----------------------------------+
```

## 2. Dependency Ordering

A major challenge in offline-first restaurant systems is that payment records depend on the existence of their parent order in the cloud. An offline cashier may create an order and immediately record a cash payment.

The `SyncQueue` guarantees correct dependency order:
1. When querying pending operations via `getPendingOperations({required String restaurantId})`, all `SyncEntityType.order` items are sorted before `SyncEntityType.payment` items.
2. When synchronizing a payment, `_syncRecordPayment` checks if the order was created offline (`local_order_id`). It looks up the local order record to retrieve the newly assigned `server_order_id`.
3. If the parent order has not yet been acknowledged by the cloud, the payment operation is safely deferred until the order succeeds.

## 3. Reachability Probing

Traditional network listeners (`ConnectivityResult.wifi` or `mobile`) only report whether the device is attached to a local access point or cellular tower—not whether Supabase or the wider internet is reachable (e.g. captive portals, router outages, or firewall blocks).

`CafeSyncService.checkCloudReachability()` performs an actual lightweight query:
```dart
await client!
    .from('restaurant_settings')
    .select('id')
    .limit(1)
    .timeout(const Duration(seconds: 4));
```
If this query succeeds within 4 seconds, the device is verified as online. If it times out or throws a socket exception, `isOnline` transitions to false and the sync engine suppresses unnecessary cloud calls.

## 4. Exponential Backoff and Retry Scheduling

When a synchronization attempt fails due to a network or transport issue, `SyncQueue.markRetry(id, error)` handles the failure:
- Increments `retryCount` by 1.
- Computes backoff delay using:
  $$\text{delaySeconds} = \min(300, 2^{\text{retryCount}} \times 3)$$
  - Attempt 1: 6 seconds
  - Attempt 2: 12 seconds
  - Attempt 3: 24 seconds
  - Attempt 4: 48 seconds
  - Attempt 5: 96 seconds
- Sets `nextRetryAt = DateTime.now().add(Duration(seconds: delaySeconds))`.
- If `retryCount >= 5` (max retries), the item transitions to `SyncStatus.failed`, preventing infinite retry loops and allowing the cashier or manager to trigger manual retry.

## 5. Server-Side Idempotency via Client Transaction IDs

Every offline order and payment receives a UUID-based `client_tx_id` upon creation (e.g., `ctx_ord_1771178239012`).

On PostgreSQL:
```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_restaurant_client_tx_id
    ON public.orders(restaurant_id, client_tx_id)
    WHERE client_tx_id IS NOT NULL;
```
The RPC `create_order_with_items` checks:
```sql
SELECT id, order_number INTO v_order_id, v_order_number
FROM public.orders
WHERE restaurant_id = p_restaurant_id AND client_tx_id = p_client_tx_id
LIMIT 1;

IF FOUND THEN
    RETURN jsonb_build_object(
        'order_id', v_order_id,
        'order_number', v_order_number,
        'idempotent_replay', true,
        'status', 'EXISTING'
    );
END IF;
```
This guarantees that dropped packets or duplicate retry attempts never result in double billing or duplicate kitchen tickets.

