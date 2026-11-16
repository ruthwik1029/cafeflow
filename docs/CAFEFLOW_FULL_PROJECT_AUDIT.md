# CAFEFLOW — COMPLETE PROJECT AUDIT & RECOVERY REPORT

**Date:** 14 November 2026  
**Auditor:** Antigravity IDE Development Agent  
**Environment:** Windows (PowerShell), Flutter 3.47.9, Dart 3.13.7  
**Repository Location:** `C:\Users\Administrator\OneDrive\Desktop\CafeFlow`  
**Target Backend:** Supabase (`https://ierqwjxypkyehrhcrkbl.supabase.co`)

---

## EXECUTIVE SUMMARY

CafeFlow is an enterprise cafe management application unifying Windows desktop (Owner/Admin, Cashier/POS, Kitchen/KOT), Android mobile (Owner, Staff in a single role-switched APK), and Flutter Web (public customer cafe site).

Prior to this audit, development in OpenAI Codex was halted mid-stream due to an Azure OpenAI resource mismatch error. Codex reported editing 16 files and adding approximately 646 lines.

Our complete inspection confirms:
1. **The 16 Codex Files Were Located and Audited:** Exactly 16 files were modified/added (15 Dart files, 1 `pubspec.yaml` asset entry), plus 4 image assets in `assets/images/`.
2. **The Disconnection Defect:** While the 15 Dart files implement functional UI components and in-memory controllers for POS, Menu Management, Orders, and Kitchen, **none of them were wired into the application's router (`internal_router.dart`) or workspace views (`workspace_page.dart`)**. As a result, running the app on Windows or Android only shows the static Phase 01 placeholder screens.
3. **Database & Realtime Status (Phase 03):** 0 of the 19 required database tables exist. There are no SQL migrations, no RLS policies, no storage buckets, and no active remote deployment to the Supabase instance.
4. **Build Health:** Flutter builds for Windows Release, Android Release APK (via `./tool/build_android.ps1`), and Flutter Web Release all compile and succeed. All 28 existing Phase 01 tests pass.
5. **Code Quality:** 1 minor analyzer info lint exists (`use_null_aware_elements` in `section_heading.dart`), and formatting discrepancies exist across the 15 Codex files due to compressed one-liner formatting.

---

## 1. OVERALL PROJECT CONDITION

| Category | Status | Details |
| :--- | :--- | :--- |
| **Project Foundation** | **COMPLETE** | Monorepo structure, theme engine, router skeleton, and platform runners established. |
| **Phase 01 Foundation** | **COMPLETE** | Shared Flutter architecture, design system, theme persistence, Supabase configuration checks. |
| **Phase 01.1 Android Recovery**| **COMPLETE** | Java 25 Unix-domain socket workaround (`tool/build_android.ps1`) operational and verified. |
| **Phase 02 Workspaces UI** | **PARTIALLY COMPLETE** | Standalone widgets created for POS, KOT, and Menu, but 100% disconnected from navigation. Admin and Android Owner screens are missing. |
| **Phase 03 Database & Realtime** | **NOT IMPLEMENTED** | 0 migrations, 0 tables created, 0 RLS policies, 0 remote deployment. |
| **Windows Build** | **COMPLETE** | Release binary compiles cleanly (`cafeflow.exe`). |
| **Android APK Build** | **COMPLETE** | Release APK builds cleanly (`app-release.apk`, 53.1MB). |
| **Flutter Web Build** | **COMPLETE** | Release web bundle builds cleanly (`build/web`). |
| **Automated Tests** | **PARTIALLY COMPLETE** | 28 tests pass; covers Phase 01 only. 0 tests cover new Phase 02 code. |
| **Static Analysis** | **PARTIALLY COMPLETE** | 1 info warning in `lib/shared/components/section_heading.dart:15:11`. |
| **Code Formatting** | **PARTIALLY COMPLETE** | 15 new Dart files have formatting discrepancies. |

---

## 2. EXISTING ARCHITECTURE

The application implements a clean multi-tier structure designed around strict platform and role isolation:

```
lib/
├── core/
│   ├── bootstrap/          # Entrypoints, environment initialization, ProviderScope setup
│   ├── config/             # AppConfig (URL validation, publishable key regex check)
│   ├── database/           # DatabaseGateway interface & Supabase adapter
│   ├── errors/             # AppFailure sanitized error envelope
│   ├── routing/            # Internal GoRouter, workspace targets, target role isolation
│   ├── services/           # BackendState, SupabaseClient provider, RealtimeGateway
│   ├── theme/              # CafeColors, CafeTheme (Light/Dark), ThemeController, PreferencesStore
│   └── widgets/            # Core design system components (CafeCard, CafeButton, StatusPill, etc.)
├── features/
│   ├── billing/            # CartController, CartState, PosPage (CODEX - DISCONNECTED)
│   ├── customer_website/   # Public customer web app (CustomerHome, CustomerShell, CustomerRouter)
│   ├── demo/               # In-memory DemoCatalogController, DemoOrdersController, fixtures
│   ├── design_system/      # Visual component gallery
│   ├── menu/               # MenuProduct, MenuCategory, CatalogBrowser, MenuManagementPage, MenuEditor
│   ├── orders/             # CafeOrder, OrderLine, OrderStatus, OrdersPage, KitchenPage
│   └── workspaces/         # WorkspaceCatalog, WorkspaceShell, WorkspacePage (Phase 01 placeholder)
└── shared/
    └── components/         # ProductCard, ProductImage, SectionHeading, DemoNotice
```

### Architectural Principles Verified:
- **No Node.js / React / Next.js:** Verified 100% Pure Flutter and Dart.
- **Centralized Supabase Integration:** Single backend gateway configured via `AppConfig` and `DatabaseGateway`.
- **Target Role Boundaries:**
  - **Windows Desktop:** `admin`, `cashier`, `kitchen`.
  - **Android APK:** `owner`, `staff` (single APK, role-switchable).
  - **Flutter Web:** Public customer website only. Internal routes `/admin`, `/cashier`, `/kitchen`, `/owner`, `/staff` are strictly rejected by `createCustomerRouter()`.

---

## 3. PHASE 01 VERIFICATION

| Requirement | Status | Verification Evidence |
| :--- | :--- | :--- |
| **Shared Flutter Architecture** | **COMPLETE** | Clean domain/presentation separation, Riverpod state, GoRouter navigation. |
| **Workspace Separation** | **COMPLETE** | Windows, Android, and Web separate entrypoints and route graphs. |
| **Design System** | **COMPLETE** | Inter & Space Grotesk fonts, CafeColors palette, custom buttons/cards/pills/inputs. |
| **Light/Dark Theme** | **COMPLETE** | Persistent `ThemeMode` with `SharedPreferences`, immediate switching, serialized storage. |
| **Supabase Foundation** | **COMPLETE** | `AppConfig` validates HTTPS origin and rejects non-publishable keys. |
| **Platform Entry Points** | **COMPLETE** | `main.dart` (conditional import), `main_windows.dart`, `main_android.dart`, `main_public.dart`. |
| **Documentation** | **COMPLETE** | 6 architecture docs in `docs/` (`PROJECT_ARCHITECTURE.md`, `DESIGN_SYSTEM.md`, etc.). |
| **Existing Tests** | **COMPLETE** | 28 automated tests covering config, themes, gateway bounds, and router isolation. |
| **Windows Build** | **COMPLETE** | Verified via `flutter build windows` (exit code 0). |
| **Android Build** | **COMPLETE** | Verified via `./tool/build_android.ps1` (exit code 0). |
| **Web Build** | **COMPLETE** | Verified via `flutter build web` (exit code 0). |

---

## 4. PHASE 01.1 VERIFICATION (ANDROID BUILD RECOVERY)

| Item | Status | Verification Evidence |
| :--- | :--- | :--- |
| **Root Cause Analysis** | **COMPLETE** | Documented in `docs/PHASE_01_1_ANDROID_BUILD.md`. Java 25 selector creates Unix-domain sockets that fail under Windows default `%TEMP%`. |
| **Build Helper Script** | **COMPLETE** | `tool/build_android.ps1` scopes `JAVA_TOOL_OPTIONS` `-Djdk.net.unixdomain.tmpdir` to `build/java-sockets`. |
| **APK Generation** | **COMPLETE** | Ran `powershell .\tool\build_android.ps1`. Result: `build\app\outputs\flutter-apk\app-release.apk` (53.1MB, exit code 0). |

---

## 5. PHASE 02 AUDIT — APPLICATION SHELLS & WORKSPACE UI

### A. Audit of the 16 Files Modified During Codex Session
During the previous Codex session, 16 files were created or modified:
1. `pubspec.yaml` (Declared `assets/images/` path) — **COMPLETE**
2. `lib/shared/components/section_heading.dart` (SectionHeading & DemoNotice) — **COMPLETE** (1 lint warning)
3. `lib/shared/components/product_card.dart` (ProductCard & ProductImage) — **COMPLETE**
4. `lib/features/billing/application/cart_controller.dart` (CartState, CartController, tax/discount calculation) — **COMPLETE**
5. `lib/features/billing/presentation/pos_page.dart` (PosPage UI) — **COMPLETE** (but disconnected)
6. `lib/features/demo/application/demo_catalog_controller.dart` (DemoCatalogController) — **COMPLETE**
7. `lib/features/demo/application/demo_orders_controller.dart` (DemoOrdersController) — **COMPLETE**
8. `lib/features/demo/data/demo_catalog.dart` (In-memory products and categories) — **COMPLETE**
9. `lib/features/demo/data/demo_operations.dart` (In-memory orders, inventory, staff fixtures) — **COMPLETE**
10. `lib/features/menu/application/catalog_provider.dart` (AsyncValue catalog provider) — **COMPLETE**
11. `lib/features/menu/domain/catalog.dart` (MenuProduct, MenuCategory, CatalogSnapshot, money/parseMoney) — **COMPLETE**
12. `lib/features/menu/presentation/catalog_browser.dart` (Search & category grid) — **COMPLETE**
13. `lib/features/menu/presentation/menu_editor.dart` (Add/edit product dialog) — **COMPLETE**
14. `lib/features/menu/presentation/menu_management_page.dart` (Catalog management & category editing) — **COMPLETE** (but disconnected)
15. `lib/features/orders/domain/cafe_order.dart` (CafeOrder, OrderLine, OrderStatus) — **COMPLETE**
16. `lib/features/orders/presentation/orders_page.dart` (OrdersPage, OrderTicket, KitchenPage) — **COMPLETE** (but disconnected)

Plus 4 bundled JPEG assets: `assets/images/{bowl, coffee, pastry, sandwich}.jpg`.

### B. Detailed Workspace Screen Audit

#### 1. Windows Owner/Admin Workspace (Completion: 20%)
- **Dashboard:** **NOT IMPLEMENTED** (renders Phase 01 static card)
- **Orders:** **PARTIALLY COMPLETE** (`OrdersPage` in `orders_page.dart` implemented, but not connected to `/admin/orders`)
- **Menu management:** **PARTIALLY COMPLETE** (`MenuManagementPage` implemented, but not connected to `/admin/menu`)
- **Categories:** **PARTIALLY COMPLETE** (`MenuManagementPage(categoriesOnly: true)` implemented, but not connected to router)
- **Inventory:** **NOT IMPLEMENTED** (mock tuples exist in `demo_operations.dart`, no UI)
- **Tables:** **NOT IMPLEMENTED** (no table management UI)
- **Staff:** **NOT IMPLEMENTED** (mock tuples exist in `demo_operations.dart`, no UI)
- **Customers:** **NOT IMPLEMENTED**
- **Reports:** **NOT IMPLEMENTED**
- **Settings:** **NOT IMPLEMENTED**

#### 2. Windows Cashier/POS Workspace (Completion: 45%)
- **Menu categories:** **PARTIALLY COMPLETE** (in `CatalogBrowser`, disconnected)
- **Product search:** **PARTIALLY COMPLETE** (in `CatalogBrowser`, disconnected)
- **Product selection:** **PARTIALLY COMPLETE** (in `pos_page.dart`, disconnected)
- **Cart:** **PARTIALLY COMPLETE** (`CartController` & cart sidebar in `pos_page.dart`, disconnected)
- **Quantity adjustment:** **PARTIALLY COMPLETE** (increment/decrement/remove in `pos_page.dart`, disconnected)
- **Remove items:** **PARTIALLY COMPLETE** (delete button in `pos_page.dart`, disconnected)
- **Subtotal, tax, discount & total:** **PARTIALLY COMPLETE** (5% tax, discount clamping, integer minor math in `cart_controller.dart`, disconnected)
- **Payment method interface:** **PARTIALLY COMPLETE** (preview dropdown for Cash/Card/UPI in `pos_page.dart`, disconnected)

#### 3. Windows Kitchen/KOT Workspace (Completion: 50%)
- **New orders:** **PARTIALLY COMPLETE** (`KitchenPage` column, disconnected)
- **Preparing orders:** **PARTIALLY COMPLETE** (`KitchenPage` column, disconnected)
- **Ready orders:** **PARTIALLY COMPLETE** (`KitchenPage` column, disconnected)
- **Order tickets:** **PARTIALLY COMPLETE** (`OrderTicket` with number, table, time, items, disconnected)
- **Items and quantities:** **PARTIALLY COMPLETE** (`OrderTicket` renders `line.quantity × line.name`, disconnected)
- **Special instructions:** **PARTIALLY COMPLETE** (`OrderTicket` renders customer instructions, disconnected)
- **Status controls:** **PARTIALLY COMPLETE** (Advance button transitions New -> Preparing -> Ready, disconnected)

#### 4. Android Owner Workspace (Completion: 0%)
- **Sales dashboard:** **NOT IMPLEMENTED**
- **Order overview:** **NOT IMPLEMENTED**
- **Recent orders:** **NOT IMPLEMENTED**
- **Popular items:** **NOT IMPLEMENTED**
- **Inventory alerts:** **NOT IMPLEMENTED**
- **Staff overview:** **NOT IMPLEMENTED**

#### 5. Android Staff Workspace (Completion: 40%)
- **Menu browsing:** **PARTIALLY COMPLETE** (`CatalogBrowser` exists, disconnected)
- **Product selection:** **PARTIALLY COMPLETE** (`PosPage(staff: true)` exists, disconnected)
- **Order creation interface:** **PARTIALLY COMPLETE** (`PosPage(staff: true)` with mobile segmented button Menu/Cart, disconnected)
- **Active orders:** **PARTIALLY COMPLETE** (`OrdersPage(activeOnly: true)` exists, disconnected)
- **Order status:** **PARTIALLY COMPLETE** (`OrdersPage(activeOnly: true)` exists, disconnected)

#### 6. Public Flutter Web (Completion: 45%)
- **Navigation:** **COMPLETE** (Header with responsive drawer, brand, theme switcher)
- **Hero section:** **COMPLETE** ("Good coffee. Great company." with typography and brand graphic)
- **Cafe introduction:** **COMPLETE** (3 feature cards)
- **Menu categories:** **NOT IMPLEMENTED** (`/menu` displays placeholder `PublicFoundationPage`)
- **Featured products:** **NOT IMPLEMENTED** (`CatalogBrowser(featuredOnly: true)` not mounted on home)
- **About:** **PARTIALLY COMPLETE** (`/about` displays placeholder `PublicFoundationPage`)
- **Contact:** **PARTIALLY COMPLETE** (`/contact` displays placeholder `PublicFoundationPage`)
- **Location:** **NOT IMPLEMENTED** (placeholder text only)
- **Footer:** **COMPLETE**

### C. The Disconnection Defect (Critical Finding)
In `lib/core/routing/internal_router.dart`, routes are generated dynamically from `workspaceCatalog`:
```dart
for (final section in workspace.sections)
  GoRoute(
    path: workspace.path(section.id),
    builder: (_, _) => WorkspacePage(workspace: workspace, section: section),
  ),
```
`WorkspacePage` unconditionally renders the Phase 01 static card saying `"The navigation and visual foundation are ready. This module has no operational data or write actions in Phase 01."`

Because Codex encountered an error before modifying `internal_router.dart` or `workspace_page.dart`:
- `PosPage` is not referenced in any router or workspace.
- `OrdersPage` is not referenced in any router or workspace.
- `KitchenPage` is not referenced in any router or workspace.
- `MenuManagementPage` is not referenced in any router or workspace.
- `CatalogBrowser` is not referenced in any router or workspace.

**Overall Phase 02 Completion Percentage:** **28%**  
(Solid interactive UI widgets created, but 0% connected to navigation; several workspace sections remain unimplemented).

---

## 6. PHASE 03 AUDIT — SUPABASE DATABASE AND REALTIME

### A. Current Implementation State
- **Database Migrations:** **NOT IMPLEMENTED** (`supabase/migrations/` contains only `README.md`).
- **Seed Fixtures:** **NOT IMPLEMENTED** (`supabase/seed.sql` contains only comments).
- **Remote Supabase Deployment:** **NOT VERIFIED / NOT APPLIED**. The project URL `https://ierqwjxypkyehrhcrkbl.supabase.co` is defined in `.env.example`, but no credentials are provided, no tables exist remotely, and no migrations have been applied.
- **Supabase CLI:** Not installed in the local environment.

### B. Required 19 Tables Audit

| # | Table Name | Local Migration | Remote DB | Primary Key | Tenancy (`restaurant_id`) | RLS Policy |
| :-: | :--- | :-: | :-: | :-: | :-: | :-: |
| 1 | `restaurants` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Root Tenant | N/A |
| 2 | `restaurant_settings` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 3 | `user_profiles` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Auth Link | N/A |
| 4 | `restaurant_memberships`| **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Role Mapping | N/A |
| 5 | `menu_categories` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 6 | `menu_items` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 7 | `menu_item_variants` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 8 | `menu_item_addons` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 9 | `orders` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 10 | `order_items` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 11 | `order_status_history` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 12 | `payments` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 13 | `payment_methods` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 14 | `dining_tables` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 15 | `table_sessions` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 16 | `inventory_categories` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 17 | `inventory_items` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 18 | `stock_movements` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| 19 | `customers` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |
| * | `audit_logs` | **NOT IMPLEMENTED** | **NOT APPLIED** | N/A | Missing | N/A |

### C. RLS Security Audit
- **PostgreSQL RLS:** **NOT IMPLEMENTED** (0 policies defined).
- **Client Security Policies in Dart:** **COMPLETE**.
  - `AppConfig` validates publishable key format (`^sb_publishable_[A-Za-z0-9_-]+$`).
  - Service-role or secret keys are completely absent from client code.
  - HTTPS origin is required.
  - `DatabaseGateway` bounds queries to max 1000 rows and sanitizes Postgrest exceptions (`42501` access denied).
  - Web router strictly denies access to internal role paths.

### D. Realtime and Storage Audit
- **Realtime (Dart Client):** **COMPLETE** (`SupabaseChangefeedTransport` and `RealtimeGateway` implemented with unit tests in `test/realtime_test.dart`).
- **Realtime (PostgreSQL Publications):** **NOT IMPLEMENTED** (no tables published).
- **Storage Buckets & Policies:** **NOT IMPLEMENTED** (no buckets created; UI currently falls back to bundled asset images and HTTPS URIs).

**Overall Phase 03 Completion Percentage:** **10%**  
(Dart gateway abstraction and architecture documentation complete; schema, RLS, and remote deployment 0%).

---

## 7. VERIFICATION AND BUILD RESULTS

All verification commands were executed directly on this Windows host:

```powershell
1. flutter --version
   Flutter 3.47.9 • channel stable
   Dart 3.13.7 • DevTools 2.60.0
   Result: PASSED

2. dart format --output=none --set-exit-if-changed .
   15 files with formatting differences (Codex compressed syntax)
   Result: FAILED (Exit Code 1)

3. flutter analyze
   1 issue found:
   info - Use the null-aware marker '?' rather than a null check via an 'if'. 
          lib\shared\components\section_heading.dart:15:11 - use_null_aware_elements
   Result: FAILED (Exit Code 1 due to info lint)

4. flutter test
   28 of 28 tests passed (config_test, database_gateway_test, realtime_test, 
   routing_and_layout_test, theme_test)
   Result: PASSED (Exit Code 0)

5. flutter build windows
   Release binary generated: build\windows\x64\runner\Release\cafeflow.exe (in 15.0s)
   Result: PASSED (Exit Code 0)

6. powershell .\tool\build_android.ps1
   Release APK generated: build\app\outputs\flutter-apk\app-release.apk (53.1MB in 10.9s)
   Result: PASSED (Exit Code 0)

7. flutter build web
   Release web bundle generated: build\web (in 72.1s)
   Result: PASSED (Exit Code 0)
```

---

## 8. PROBLEMS DISCOVERED

1. **Routing Disconnection:** The primary functional blocker. `pos_page.dart`, `orders_page.dart`, `menu_management_page.dart`, `menu_editor.dart`, and `catalog_browser.dart` are orphaned and inaccessible in the running app.
2. **Missing Screens in Workspaces:**
   - Admin Workspace: Dashboard overview, inventory management, tables management, staff roster, reports, and settings are empty placeholders.
   - Android Owner Workspace: All 5 sections (Overview, Sales, Revenue, Orders, Inventory Alerts) are empty placeholders.
   - Public Web: Menu, About, and Contact pages are placeholder `PublicFoundationPage` widgets.
3. **Absence of Supabase Migrations (Phase 03 Void):** No SQL migrations exist for the 19 required tables, RLS policies, or realtime publications.
4. **Code Quality & Formatting Discrepancies:** Codex authored the 15 Dart files using ultra-compact one-line statements, violating Dart style guidelines and failing `dart format`.
5. **Static Analysis Warning:** `lib/shared/components/section_heading.dart:15:11` triggers `use_null_aware_elements`.
6. **Riverpod Family Provider Inconsistency:** In `lib/features/billing/application/cart_controller.dart`, `CartController` extends `Notifier<CartState>` with a constructor taking `workspace`, instead of extending `FamilyNotifier<CartState, String>`. While it currently compiles, it is non-standard for Riverpod 3.x.
7. **Zero Tests for Phase 02 Code:** None of the 15 Codex files have automated unit or widget tests.

---

## 9. CRITICAL SECURITY ISSUES

1. **Premature Exposure Risk:** Because demo mode is currently enabled by default (`allowsDemo = demoMode && environment != 'production'`), workspaces can be browsed without login during development. When Supabase Auth is integrated, route guards must enforce strict authenticated session checks.
2. **Missing Database-Level RLS:** If client applications connect to Supabase before RLS policies are applied, tables would be publicly readable/writable. **RLS must be enabled in the exact same SQL migration that creates each table.**
3. **Multi-Tenant Scoping:** Every operational table must enforce `restaurant_id` foreign keys and tenant isolation policies to prevent cross-restaurant data leakage.

---

## 10. FILES THAT NEED REPAIR

| File | Issue | Recommended Action |
| :--- | :--- | :--- |
| `lib/shared/components/section_heading.dart` | `use_null_aware_elements` lint warning | Replace `if (action != null) action!` with `?action` |
| `lib/core/routing/internal_router.dart` | Disconnected routing | Dispatch workspace routes to actual feature pages (`PosPage`, `OrdersPage`, `KitchenPage`, `MenuManagementPage`, etc.) |
| `lib/features/workspaces/presentation/workspace_page.dart` | Static placeholder fallback | Allow rendering concrete section widgets when available, retaining placeholder only for deferred modules |
| `lib/features/billing/application/cart_controller.dart` | FamilyNotifier convention | Clean up Riverpod Notifier implementation and format code |
| `All 15 Codex Dart files` | Formatting | Run `dart format` to restore clean Dart readability |

---

## 11. RECOMMENDED IMPLEMENTATION ORDER (PHASE 02 RECOVERY & PHASE 03)

### STEP 1: Code Quality & Route Integration (Immediate)
1. Fix the single lint in `lib/shared/components/section_heading.dart`.
2. Format the 15 Codex files using `dart format`.
3. Update `internal_router.dart` and `workspace_page.dart` to mount:
   - `/cashier/pos` & `/cashier/billing` -> `PosPage`
   - `/cashier/orders` & `/admin/orders` -> `OrdersPage`
   - `/kitchen/display`, `/kitchen/incoming`, `/kitchen/preparation` -> `KitchenPage`
   - `/admin/menu` & `/admin/categories` -> `MenuManagementPage`
   - `/staff/orders` -> `PosPage(staff: true)`
   - `/staff/menu` -> `CatalogBrowser`
   - `/staff/tables` & `/staff/status` -> `OrdersPage(activeOnly: true)`

### STEP 2: Complete Missing Phase 02 Workspaces
1. **Admin / Owner Dashboard:** Add overview summary cards, quick actions, and demo operational stats.
2. **Android Owner Workspace:** Implement mobile business overview, sales summary, and low stock alert tiles.
3. **Tables & Staff Management:** Create lightweight interactive management shells for tables and staff.
4. **Public Web:** Connect `/menu` to `CatalogBrowser(featuredOnly: false)` and Web Home to featured products.

### STEP 3: Automated Testing for Phase 02
1. Add unit tests for `CartController` (tax calculation, minor unit discounts, bounds).
2. Add unit tests for `DemoCatalogController` and `DemoOrdersController`.
3. Add widget tests for `PosPage`, `OrdersPage`, and `KitchenPage`.

### STEP 4: Phase 03 — Supabase Database Architecture
1. Write versioned SQL migrations under `supabase/migrations/` for all 19 tables:
   - Tenant isolation via `restaurant_id UUID REFERENCES restaurants(id)`
   - UUID primary keys, foreign keys, constraints, and audit timestamps
   - Monetary values stored in minor units (integer cents/paisa)
2. Define row-level security (RLS) policies on every table for public, customer, staff, and admin roles.
3. Configure PostgreSQL Realtime publication for orders and tickets.
4. Define Supabase Storage bucket (`menu-images`) and access policies.

### STEP 5: Supabase Flutter Repository Binding
1. Implement concrete repositories implementing `MenuRepository` and `OrderRepository`.
2. Provide seamless fallback between demo fixtures and real Supabase client based on `AppConfig`.

---

## 12. AUDIT VERDICT

| Phase | Completion | Status | Next Milestone |
| :--- | :-: | :--- | :--- |
| **Phase 01: Architecture & Foundation** | **100%** | **COMPLETE** | Maintain & protect baseline. |
| **Phase 01.1: Android Recovery** | **100%** | **COMPLETE** | Keep `tool/build_android.ps1` in CI/build flow. |
| **Phase 02: Workspaces UI & Shells** | **28%** | **PARTIALLY COMPLETE** | Route existing screens; complete missing shells. |
| **Phase 03: Supabase DB & Realtime** | **10%** | **NOT IMPLEMENTED** | Author SQL migrations for 19 tables + RLS. |

**Audit Complete. Development is halted awaiting user review and authorization to proceed with Step 1.**

