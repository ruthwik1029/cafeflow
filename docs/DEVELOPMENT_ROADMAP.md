# Development roadmap

## Phase 01 — implemented foundation

Shared Flutter application, Windows/Android/Web runners, target-isolated routing,
five internal workspace shells, public customer preview, design system, persistent
themes, Supabase configuration, data/Realtime adapters, domain interfaces, tests
and architecture documentation. Business screens explicitly describe the deferred
feature instead of pretending to operate. No database schema or auth flow is added.

## Approval gate

Stop here. Do not proceed to Phase 02 until the developer approves the Phase 01
implementation and resolves any platform verification issues recorded in the report.

## Proposed later sequence (planning only)

1. Identity and data authorization: business/outlet memberships, Auth lifecycle,
   trusted roles, RLS/Storage policies and database security tests.
2. Shared menu: categories, products, availability, approved public read surface,
   actual repositories and tested cross-platform menu invalidation.
3. Tables and orders: validated order transactions, staff entry, kitchen tickets,
   preparation transitions, cashier order views and idempotent retries.
4. Billing: price/tax snapshots, payments, settlement and receipt design; protect
   totals and status transitions with database transactions and authorization.
5. Inventory, staff administration and reporting with verified business metrics.
6. Customer ordering, final café content, responsive/accessibility review, release
   signing, Windows installer, public hosting and production operations.

These are dependency-based proposals, not an approved Phase 02 scope. Authentication,
full admin dashboards, POS/KOT operations, inventory logic, analytics, customer
ordering and deployment have not been implemented or started.
