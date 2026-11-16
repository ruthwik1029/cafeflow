# Realtime architecture

## Implemented transport foundation

`RealtimeGateway.watch(ChangefeedSpec)` returns a lazy, single-subscription stream.
No channel exists until something listens. `SupabaseChangefeedTransport` registers
Postgres INSERT/UPDATE/DELETE notifications through `onPostgresChanges`. It emits
an invalidation signal, not a fabricated domain model. Its unique channel names
allow multiple independently owned subscriptions without naming collisions.

The stream emits `subscribed` on initial subscription and every SDK reconnect;
consumers must refetch an authorized database snapshot then. Change notifications
also trigger refetch. Subscription errors, timeout and unexpected closure emit a
safe `AppFailure`. The SDK owns reconnect behavior. No local timer produces demo
events, no fake orders are inserted, and no subscription starts in Phase 01 UI.

Cancelling the stream calls `removeChannel` exactly once through an idempotent
closure. Late callbacks are ignored after cancellation. Unit tests verify lazy
creation, event/error forwarding, reconnect signals and cancellation behavior.
These are lifecycle tests, not proof of connectivity to the hosted project.

## Future ownership pattern

One auto-disposed Riverpod stream provider per feature/query identity should watch
the shared gateway. Several widgets watch that provider, not separate raw channels.
When the last listener leaves the screen, Riverpod cancels the stream and its channel.
Include business/outlet and relevant query identity in the provider family key.
Invalidate feature providers on sign-out, business switch or membership revocation.
For a deliberately app-scoped subscription, retain it explicitly only while an
authorized user needs it, then cancel it on sign-out.

The repository, not a widget, maps invalidations into snapshots. Subscribe first,
then fetch on the `subscribed` signal so initial fetches do not miss changes before
the channel is ready. Serialize/coalesce concurrent refreshes, ensuring that an
invalidation during an in-flight read schedules another read. Never let an older
response overwrite a newer result. On error, distinguish stale cached content
from fresh content and provide an explicit refresh path. Lifecycle suspension and
network reconnect should lead to a full authorized refresh.

## Intended event paths

| Change | Subscribers after those features exist |
| --- | --- |
| Published menu item changed/deleted | Customer menu, Android staff, cashier catalog |
| Staff order committed | Kitchen tickets, cashier orders, owner monitoring |
| Kitchen transition committed | Staff order status, cashier orders, owner monitoring |
| Inventory threshold crossed | Owner alerts, admin inventory |

PostgreSQL is authoritative. Clients do not directly broadcast a successful payment
or order transition. Business transactions commit first, then subscribers refetch.
Menu deletes need special care: Postgres delete payloads and filters have constraints,
and historic row content must not be assumed available. A scoped invalidation and
authorized refetch handles removal without relying on deleted payload fields.
Published-menu/public-feed design must be reviewed with RLS before enabling it.

The supplied filter reduces traffic; it does not establish access rights. Publication
membership, grants, RLS policies, JWT identity and channel behavior must be tested
against a real database. Do not expose internal order/staff data to anonymous web
clients through either a publication or Storage. Integration/load tests, background
delivery guarantees and offline synchronization remain future work.
