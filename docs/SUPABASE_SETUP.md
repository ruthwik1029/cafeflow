# CAFEFLOW — SUPABASE SETUP & CONFIGURATION GUIDE

**Version:** 1.0.0  
**Target Project:** `ierqwjxypkyehrhcrkbl.supabase.co`  
**Client SDK:** `supabase_flutter: ^2.8.3`  
**Configuration File:** `.env` / `.env.example`

---

## 1. Credentials & Architecture

CafeFlow is configured to connect to an existing Supabase project.

- **Project URL:** `https://ierqwjxypkyehrhcrkbl.supabase.co`
- **Publishable Key:** `sb_publishable_n6Hxo6rCVc0g8LjSI4125w_Zs351KIC`
- **Auth Strategy:** Supabase Auth (Email / Password managed by Owner/Admin, public signup disabled)
- **Realtime:** Postgres Changes broadcast for operational tables
- **Storage:** Public bucket `menu-images` with RLS upload policies

> [!CAUTION]
> **Credential Boundary:** The Flutter client must NEVER contain service-role keys, master database passwords, or secret tokens. Only the publishable key is compiled into the client. All access controls are strictly enforced at the PostgreSQL RLS layer.

---

## 2. Environment Configuration

The application reads build-time configuration variables using Flutter's native `--dart-define-from-file` flag.

### A. `.env` File
Ensure `.env` exists in the project root (it is git-ignored):

```ini
APP_ENV=development
DEMO_MODE=false
SUPABASE_URL=https://ierqwjxypkyehrhcrkbl.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_n6Hxo6rCVc0g8LjSI4125w_Zs351KIC
```

### B. Validation Rule
`AppConfig.validate()` runs during bootstrap:
- Verifies `APP_ENV` is `development`, `staging`, or `production`.
- Verifies `SUPABASE_URL` is an HTTPS project origin without query parameters.
- Enforces regex `^sb_publishable_[A-Za-z0-9_-]+$` to prevent accidental inclusion of service-role keys.

---

## 3. Database Migration Deployment

All 20 database tables, constraints, RLS policies, Realtime publications, and Storage configurations are version-controlled in the repository under `supabase/migrations/`:

1. `supabase/migrations/20261114000001_initial_schema.sql` (Tables, constraints, indexes, triggers)
2. `supabase/migrations/20261114000002_rls_policies.sql` (RLS enablement, helper functions, role policies)
3. `supabase/migrations/20261114000003_realtime_and_storage.sql` (Realtime publication, storage bucket and policies)
4. `supabase/seed.sql` (Deterministic development fixture data)

### Migration Deployment Options

#### Option 1: Supabase CLI (Recommended for CI/CD & Local Dev)
```bash
# Login to Supabase account
supabase login

# Link repository to remote project
supabase link --project-ref ierqwjxypkyehrhcrkbl

# Push migrations to remote database
supabase db push

# Apply seed fixtures if initializing fresh environment
supabase db reset
```

#### Option 2: Supabase Web Dashboard SQL Editor
If the CLI is not available in the local runner environment:
1. Open the [Supabase Dashboard](https://supabase.com/dashboard/project/ierqwjxypkyehrhcrkbl).
2. Navigate to **SQL Editor**.
3. Execute `20261114000001_initial_schema.sql`.
4. Execute `20261114000002_rls_policies.sql`.
5. Execute `20261114000003_realtime_and_storage.sql`.
6. (Optional for development) Execute `seed.sql`.

> [!IMPORTANT]
> **Audit Deployment Status:** The SQL migrations have been authored, version-controlled, and validated locally. Because the local Windows execution environment does not have the `supabase` CLI installed or direct database administration credentials, the migrations remain local-only until applied to the remote project via the methods above.

---

## 4. Storage Bucket Setup Verification

Migration 03 automatically creates the `menu-images` bucket. In the Supabase Dashboard:
1. Navigate to **Storage**.
2. Verify the `menu-images` bucket exists and is set to **Public**.
3. Under **Policies**, confirm:
   - `Public can view menu images` (SELECT)
   - `Authenticated staff and admins can upload menu images` (INSERT)
   - `Admins can update or delete menu images` (ALL)

---

## 5. Running the Application with Supabase Enabled

To run with live backend configuration:

```bash
# Windows Desktop
flutter run -d windows --dart-define-from-file=.env

# Android
flutter run -d android --dart-define-from-file=.env

# Web
flutter run -d chrome --dart-define-from-file=.env
```

When offline or if remote tables are not yet seeded, the client's `CatalogProvider` automatically falls back to deterministic local demo fixtures, ensuring uninterrupted development and testing.

