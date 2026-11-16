# Database and access strategy

## Phase 01 state

The existing hosted project is `https://ierqwjxypkyehrhcrkbl.supabase.co`. Its URL is
documented in `.env.example`; no real key was supplied in this task. No remote
connection, schema migration, RLS policy, bucket, user, or business record was
created or modified. The seed file is intentionally comments-only.

`supabase/config.toml` is a local CLI scaffold. Its PostgreSQL 17 setting describes
a future local container, not an assertion about the hosted database's version.
The Supabase CLI/Docker workflow was not started or verified in this phase. Do not
reconfigure the hosted project from this file without reviewing it separately.

## Client boundaries

`AppConfig` accepts only a valid environment, HTTPS origin without user info/query,
and a modern `sb_publishable_` key. Invalid values are rejected before initialization.
All-empty values leave the backend unavailable without preventing UI preview.
The provider throws a safe failure when a caller tries to use an unavailable client.
No arbitrary credentials are logged or displayed. Synthetic test strings cannot
authenticate and are used only to validate rejection/acceptance rules.

Build defines can be extracted from binaries. Obfuscation does not turn them into
secret storage. Secret/service-role credentials and database passwords belong only
in approved server-side/administration environments. Client access is authorized
by Supabase Auth JWTs plus PostgreSQL privileges and RLS, never by hiding a key.

Authentication workflows are deferred. Session persistence, automatic refresh and
URL session detection are disabled for this phase using Supabase client options;
this also prevents public startup from restoring an unrelated authenticated session.
Future internal Auth work must define secure device/session storage and callback
routing explicitly. Theme preferences are the only application-persisted state.

`DatabaseGateway` provides bounded read access with safe errors. Its relation names
and equality filters will be chosen by concrete repositories. It does not grant
permissions or bypass RLS. No generic write adapter is provided before transaction
and authorization rules are designed. Menu/order contracts have no concrete backend
binding yet. Storage and Auth are available through the Supabase client, but no
bucket operations or sign-in flows are implemented.

## Later schema design requirements

- Model businesses/outlets and trusted user memberships before operational tables.
- Keep role assignment server-controlled; clients must not update their own role.
- Enable RLS and restricted grants in the same migration that creates each exposed table.
- Scope internal rows by business/outlet membership and least privilege.
- Expose only approved public menu fields, availability, and published business details.
- Deny anonymous access to staff, sales, inventory, orders and settings by default.
- Treat order creation, state transitions, inventory changes and billing as validated transactions.
- Use server timestamps, monetary minor units/currency, constraints and idempotency keys where appropriate.
- Review Realtime publication scope alongside RLS. A subscription filter is not authorization.
- Separate public menu imagery from private files. Enforce Storage policies and signed URLs for private assets.

These are design requirements, not claims that policies already exist. Before any
operational feature is released, add database integration tests for anonymous,
authenticated, wrong-role, cross-business and revoked-membership access. Test grants,
RLS and Storage separately from Flutter router tests.

## Migration workflow, after approval

Use versioned SQL under `supabase/migrations`, reviewed alongside policy tests.
Create and test migrations locally before linking/pushing to the hosted project.
Do not put credentials in migration/seed files. Destructive schema changes require
an explicit data preservation and rollout plan. No migration command should be run
against the hosted project merely to make this foundation appear connected.
