# CafeFlow — Conflict Resolution Policy

## 1. Conflict Classification & Resolution Strategies

In an offline-first cafe system, data mutations can happen simultaneously on multiple devices while disconnected from the cloud. CafeFlow employs deterministic domain-specific resolution strategies rather than generic "last write wins".

| Entity Type | Conflict Trigger | Resolution Strategy | System Action |
|:---|:---|:---|:---|
| **Orders** | Duplicate `client_tx_id` | **Idempotent Replay** | Return existing `order_id` and `order_number` without re-inserting lines. |
| **Orders** | Menu item deleted or archived while device was offline | **Server Preserves / Audit Flag** | Order is preserved in cloud with warning flag; audit record logged in `sync_conflicts`. |
| **Orders** | Price change occurred while device was offline | **Client Contract Authority** | Cashier agreed to the offline menu price with the customer; cloud accepts historical billed amount and logs the variance. |
| **Payments** | Duplicate payment attempt (`client_tx_id`) | **Idempotent Replay** | Return existing payment record; no duplicate charge. |
| **Payments** | Order already marked `PAID` or `CANCELLED` by another cashier | **Conflict Review Required** | Payment is staged; status set to `REQUIRES_REVIEW` and recorded in `sync_conflicts`. |
| **Catalog** | Price or category edited offline concurrently | **Server Authority / Optimistic Lock** | Server version increments; conflicting offline edit flagged for manager review. |

## 2. The `sync_conflicts` Schema

When a non-idempotent conflict occurs, the record is durably preserved in PostgreSQL:

```sql
CREATE TABLE public.sync_conflicts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    client_tx_id TEXT,
    client_version INT NOT NULL DEFAULT 1,
    server_version INT NOT NULL DEFAULT 1,
    conflict_type TEXT NOT NULL,
    conflict_reason TEXT NOT NULL,
    client_payload JSONB NOT NULL,
    server_payload JSONB,
    status TEXT NOT NULL DEFAULT 'PENDING_REVIEW',
    resolved_by UUID REFERENCES auth.users(id),
    resolved_at TIMESTAMPTZ,
    resolution_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);
```

## 3. Manager Conflict Resolution Workflow

1. **Detection**: When an item encounters a conflict, `SyncQueue.markConflict(...)` writes the conflict details locally and updates the queue item status to `SyncStatus.conflict`.
2. **Notification**: The `SyncStatusBadge` highlights in deep orange with label `N Conflicts`.
3. **Manager Review**: Clicking the badge opens the `SyncManagementDialog`.
4. **Resolution Actions**:
   - **Accept Client Version**: Forces the cloud database to adopt the client's submitted price or data.
   - **Accept Server Version**: Discards the local variation and updates the local cache to match the cloud state.
   - **Manual Correction**: Allows the manager to adjust quantities or amounts and re-submit the queue operation.

