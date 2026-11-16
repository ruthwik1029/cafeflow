# Project architecture

## One codebase, isolated application surfaces

CafeFlow shares Dart business contracts, providers, backend adapters, themes and
components. It does not share a universal router across public and internal apps.
`main.dart` uses a conditional import: `dart.library.io` chooses the internal
launcher; the web compilation chooses the public launcher. `main_public.dart`
can be used explicitly for web. The public import graph contains no internal
workspace router or role catalog. Tests also reject all internal role URLs.

Windows exposes Admin/Owner, Cashier and Kitchen/KOT. Android exposes Owner and
Staff in the same application package. Native launchers inspect the actual platform,
so changing the filename cannot turn the Android application into an admin console.
The three named entry points retain a single dependency set and shared components.
Only Windows, Android and web runners are generated and supported in Phase 01.

## Layers and dependency direction

```text
Entry point → platform launcher → shared bootstrap → ProviderScope → MaterialApp
                                               ↓
                    isolated GoRouter → feature presentation
                                               ↓
                    Riverpod state → domain repository interface
                                               ↓ (future concrete repositories)
                    database / Realtime adapters → Supabase client
```

Presentation owns layout and navigation; it never calls Supabase queries. The
workspace catalog is immutable navigation metadata, not application business data.
`ThemeController` is real state management with a replaceable persistence interface.
Riverpod supplies backend dependencies and provides seams for deterministic tests.
Menu and order contracts are feature-owned and can be consumed by all targets.
Concrete repositories will map database DTOs into domain models after the schema
is approved. No repository reports a fake successful operation.

Core contains genuinely shared infrastructure. `workspaces` is a deliberate
foundation feature containing all five shells' metadata and common presentation;
creating five near-identical dashboard implementations now would add duplication.
As operational modules arrive, routes will bind to their own feature presentation,
application state, domain and data layers. No empty future-feature directories or
speculative shared-model dumping grounds are included.

## Startup and failure states

1. Initialize Flutter bindings.
2. Load theme preferences before the first application frame; default to system.
3. Parse and validate build defines.
4. Skip backend initialization when unconfigured; preserve explicit invalid/failed states.
5. Initialize Supabase only with a validated public credential. This is not a connection test.
6. Inject theme storage and backend state, then construct the target-specific router.

Preference storage failure keeps the UI usable and reports an unsaved theme change.
Database reads have bounded size and a 15-second timeout, mapping backend details
to safe messages. Realtime reports subscription problems rather than presenting
stale data as current. There are no business reads or writes at startup.

## Navigation and authorization

Every internal role has a route prefix and its own list of sections. The desktop
router has no Owner-mobile/Staff routes; the Android router has no Admin/Cashier/
Kitchen routes. Unknown routes show a recovery screen. Shell navigation adapts to
a side rail at 1000 logical pixels and a drawer below that width.

Demo role switching is only navigation. `APP_ENV=production` disables it regardless
of `DEMO_MODE`; production internal routes redirect to an access-unavailable screen.
Future authorization must use authenticated identity and trusted database membership,
with RLS enforcing access for every request. Never convert the demo selector into
the source of authorization truth.

The public website contains home/menu/about/contact foundation pages only, including
safe unknown-route handling. There are no admin controls, debug backend panels, or
role switches on the public surface. Public route isolation complements, but cannot
replace, backend RLS.

## Lifecycle and ownership

Bootstrap constructs the app-lifetime Supabase client and router once. Widgets do
not recreate them on theme changes. Riverpod owns state; feature-scoped Realtime
providers will own and cancel their stream subscriptions. A theme change rebuilds
the Material theme without restarting the app or replacing its router.

No persistent business cache or offline order queue is implemented. Online ordering,
transactional billing and cross-device conflict rules require explicit later design.
