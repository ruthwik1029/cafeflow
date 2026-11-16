# CAFEFLOW — OFFLINE AND NETWORK BEHAVIOR

**Document Version:** 1.0.0  
**Phase:** 05  
**Date:** November 15, 2026  
**Status:** IMPLEMENTED & VERIFIED  

---

## 1. Network Philosophy & Transparency

CafeFlow is designed with a strict policy regarding network and offline behavior:
1. **Never Falsify Remote Success**: If a network failure occurs while operating in live cloud mode, the system never fabricates a fake successful result or pretends an order reached the cloud database when it didn't.
2. **Transparent Error Surfaces**: All exceptions are converted into clean, human-readable `AppFailure` messages presented via SnackBars, dialogs, or error banners.
3. **Explicit Operational Mode**: The UI clearly communicates whether the application is running in **Live Cloud Connected** mode or **Demo / Offline Fallback** mode.

---

## 2. Visual Mode Identification

To eliminate staff ambiguity:

### Live Cloud Connected Mode
- Displayed when `BackendStatus.initialized` is active and an authenticated user possesses a valid `restaurantId`.
- Features a prominent primary-colored status badge in headers:
  ```
  [●] LIVE CLOUD CONNECTED  (Tenant: rest-001)
  ```
- All operations (POS, KOT, Menu, Inventory, Tables) synchronize through PostgreSQL.

### Demo / Offline Fallback Mode
- Displayed when no network/Supabase configuration is supplied, or when the user has not signed into an active restaurant.
- Renders a warning-accented banner:
  ```
  Demo / Offline Notice: The app is running with local mock fixtures.
  Connect valid Supabase credentials in settings to sync live data.
  ```
- Workspaces remain responsive for testing, demonstrations, and training without corrupting production data.

---

## 3. Network Timeouts & Retry Management

All remote calls are bounded by deterministic timeouts to prevent UI freezes:

| Operation Type | Timeout | Failure Mode |
| :--- | :--- | :--- |
| **RPC Mutations** (`create_order_with_items`, `adjust_inventory_stock`, `update_table_status`) | 15 seconds | `AppFailure('Network timeout during operation. Check connectivity.')` |
| **Direct Queries** (Catalog, Orders, Tables, Customers) | 15 seconds | `AppFailure('Failed to load live data. Displaying cached state.')` |
| **Storage Uploads** (Menu item images) | 30 seconds | `AppFailure('Image upload timed out. Retry with smaller file.')` |
| **Realtime WebSocket Reconnection** | Exponential backoff (1s - 30s) | Emits `RealtimeSignal.subscribed` on reconnect or logs warning |

---

## 4. Error Handling Matrix

| Error Scenario | Supabase / Postgrest Code | UI Behavior |
| :--- | :--- | :--- |
| **Unauthorized Action (RBAC)** | `42501` | SnackBar: "Unauthorized: only Owners and Admins can perform this action." |
| **Unavailable Item during Checkout** | Custom exception | SnackBar: "Cannot create order: one or more items are currently out of stock." |
| **Network Disconnect during Order Submission** | SocketException / Timeout | SnackBar: "Network failure. Your order has not been placed. Please retry." |
| **Duplicate Submit (Idempotency)** | Handled by RPC | Returns existing order without throwing error or creating duplicate. |

