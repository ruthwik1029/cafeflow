# CafeFlow — Offline-First Architecture

## 1. High-Level Architectural Vision

CafeFlow's offline-first architecture is designed to make café operations resilient to unreliable internet connectivity, network blackouts, and server latency. Front-of-house cashier operations and kitchen order fulfillment must never stop due to cloud connectivity issues.

```
+-------------------------------------------------------------------------+
|                              FLUTTER UI LAYER                           |
|       (POS Page, Kitchen Display, Orders View, Settings, Cart)         |
+------------------------------------+------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|                            RIVERPOD PROVIDERS                           |
|  (ordersProvider, catalogProvider, syncServiceProvider, authController) |
+------------------+----------------------------------+-------------------+
                   |                                  |
                   v                                  v
+------------------------------------+  +---------------------------------+
|         SYNC SERVICE & QUEUE       |  |       LOCAL PERSISTENT DB       |
|    - Durable SyncQueue             |  |   - CafeLocalDatabase           |
|    - Reachability Probe            |  |   - Structured Document Store   |
|    - Dependency Ordering           |<---> - SharedPreferences Adapter   |
|    - Exponential Backoff           |  |   - Atomic Local Transactions   |
|    - Conflict Detection            |  |   - Tenant Cache Isolation      |
+------------------+-----------------+  +---------------------------------+
                   |
     (When Online & Reconciled)
                   v
+-------------------------------------------------------------------------+
|                             CLOUD GATEWAY                               |
|       - Supabase Database Gateway (PostgREST RPC / Postgres Tables)     |
|       - Server Idempotency with client_tx_id                            |
|       - CafeRealtimeService (Postgres Changes Subscriptions)           |
+-------------------------------------------------------------------------+
```

## 2. Core Principles

1. **Local-First Writes**: When the POS terminal creates an order or records a payment, the data is immediately staged and persisted to the local document store with an assigned `client_tx_id` and initial `sync_status = PENDING`. The operation succeeds without waiting for remote server roundtrips.
2. **Crash & Restart Resilience**: The synchronization queue is persisted directly in `CafeLocalDatabase` (`sync_queue` collection). If the app crashes, is closed, or the device loses power, all pending operations survive and resume upon restart.
3. **Multi-Platform Portability**: Unlike SQLite plugins (`sqflite` or FFI) that require platform-specific C++ binary dynamic libraries (`sqlite3.dll` on Windows) and fail entirely on Flutter Web, `CafeLocalDatabase` uses a portable JSON-backed document storage adapter (`SharedPreferencesStorageAdapter` in production and `MemoryStorageAdapter` in unit tests). It works uniformly across Windows, Android, and Web without native toolchain friction.
4. **Server-Side Idempotency**: All mutating remote RPCs (`create_order_with_items`, `record_order_payment`, `reconcile_offline_sync_batch`) accept a `p_client_tx_id` parameter backed by database-level partial unique indexes. Replaying an identical sync operation returns the existing record (`is_replay = true`) without duplicating orders or payments.
5. **Separation of Cash vs. Digital Offline Payments**: Cash payments can be finalized locally because tender and change are physically handled at the register. Digital payments (UPI, Cards) cannot be bank-verified without connectivity and are strictly marked as `PENDING_RECONCILIATION`—preventing false-positive verification.

## 3. Storage Engine (`CafeLocalDatabase`)

The storage engine implements a structured document collection model:
- **Collections**: `orders`, `order_items`, `payments`, `menu_categories`, `menu_items`, `dining_tables`, `restaurant_settings`, `payment_methods`, `customers`, `sync_queue`, `sync_conflicts`.
- **Atomic Transactions**: `LocalTransaction` supports staging multiple document inserts and updates across collections, committing them atomically or rolling back completely on error.
- **Tenant Isolation**: `clearTenantCache(restaurantId)` purges tenant-scoped data on logout or restaurant switch without contaminating other cached environments.
- **Schema Evolution**: `LocalDatabaseMigrationManager` verifies the local schema version (currently `1`) on startup and executes forward schema migrations safely.

## 4. Read Fallback and Catalog Caching

When online, `catalogProvider` fetches live categories and menu items from Supabase and simultaneously caches them locally in `CafeLocalDatabase`. If a network outage occurs:
1. `catalogProvider` detects remote fetch failures and immediately serves the cached categories and items from `CafeLocalDatabase`.
2. Cashiers can continue to browse the catalog, view variants and addons, search items, and add them to the cart without disruption.
3. `ordersProvider` merges pending local offline tickets with cloud tickets so that offline-created orders appear instantly on POS and Kitchen screens.

