# CafeFlow — Database Deployment Guide

This guide details the procedure for applying database migrations (000001 through 000011) to a remote Supabase PostgreSQL database.

> [!IMPORTANT]
> **Environment Audit Limitation Notice:**  
> The Supabase CLI is not installed on this local developer workstation. In accordance with release engineering standards, remote migration execution **must not be assumed or claimed** until completed via one of the verified deployment methods documented below.

---

## 1. Migration Overview & Sequence

All migration files are located in `supabase/migrations/` and must be applied in strict chronological order:

1. `20261114000001_initial_schema.sql` — Core tables (`restaurants`, `user_profiles`, `categories`, `products`, `orders`).
2. `20261114000002_rls_policies.sql` — Tenant isolation policies for core entities.
3. `20261114000003_seed_data.sql` — System bootstrap and reference records.
4. `20261114000004_auth_and_rbac.sql` — RBAC helper functions (`current_app_role()`, `resolve_username_to_email()`).
5. `20261115000005_realtime_and_operations.sql` — Realtime publication triggers.
6. `20261115000006_billing_and_payments.sql` — Payments, refunds, minor-unit calculations, and checkout RPCs.
7. `20261115000007_offline_sync.sql` — Offline queue, batch reconciliation, and client transaction deduplication.
8. `20261115000008_tables_and_kot.sql` — Floor sections, dining tables, sessions, and kitchen display routing.
9. `20261116000009_inventory_and_staff.sql` — Inventory stock, purchase orders, recipes, shifts, and attendance.
10. `20261116000010_reporting_and_analytics.sql` — Daily sales rollups, category performance, and restaurant settings.
11. `20261116000011_production_hardening.sql` — SEC-01 RPC anonymous lockouts, financial immutability triggers, and privilege escalation guards.

---

## 2. Deployment Procedures

### Method A — Supabase Dashboard SQL Editor (Recommended for Initial Cutover)

1. Log in to the [Supabase Dashboard](https://supabase.com/dashboard) and select your target production project.
2. Navigate to **Database** -> **Backups** and create a manual pre-deployment backup.
3. Open the **SQL Editor** from the left navigation.
4. For each migration file from `20261114000001` through `20261116000011`:
   - Copy the SQL content from `supabase/migrations/<file>.sql`.
   - Paste into the SQL Editor.
   - Click **Run** and verify execution completes with `"Success. No rows returned"`.
5. Run the post-deployment verification queries detailed in Section 3.

---

### Method B — CI/CD Pipeline Deployment (GitHub Actions)

The repository includes a production workflow in `.github/workflows/ci.yml`.

1. Ensure the following secrets are configured in GitHub Repository Settings:
   - `SUPABASE_ACCESS_TOKEN` (from Supabase Account Settings)
   - `SUPABASE_PROJECT_ID` (from Project General Settings)
   - `SUPABASE_DB_PASSWORD` (database master password)
2. Trigger the deployment workflow via git tag or workflow dispatch.
3. The workflow installs the Supabase CLI in an ephemeral Linux runner and executes:
   ```bash
   supabase link --project-ref $SUPABASE_PROJECT_ID
   supabase db push
   ```

---

### Method C — Local CLI Deployment (Once Supabase CLI is Installed)

If you install the Supabase CLI locally via `scoop install supabase`, `brew install supabase/tap/supabase`, or `npm install -g supabase`:

```powershell
# 1. Login to Supabase account
supabase login

# 2. Link your local workspace to remote project
supabase link --project-ref <your-project-ref>

# 3. Apply all pending migrations
supabase db push
```

---

## 3. Post-Deployment Verification Queries

Execute the following queries in the Supabase SQL Editor to verify the deployed schema:

### 3.1 Verify All Tables Exist and RLS is Enabled
```sql
SELECT 
  tablename, 
  rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;
```
*Expected Result:* All 20+ tables present with `rowsecurity = true`.

### 3.2 Verify RPC Execution Lockdown (SEC-01)
```sql
SELECT 
  p.proname, 
  r.rolname, 
  has_function_privilege(r.rolname, p.oid, 'EXECUTE') as can_execute
FROM pg_proc p
CROSS JOIN (SELECT 'anon'::name as rolname UNION ALL SELECT 'authenticated'::name) r
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'create_order_with_items',
    'record_order_payment',
    'reconcile_offline_sync_batch',
    'deduct_order_recipe_stock',
    'receive_purchase_order',
    'resolve_username_to_email'
  )
ORDER BY p.proname, r.rolname;
```
*Expected Result:*
- `resolve_username_to_email`: `anon = true`, `authenticated = true`
- All other operational RPCs: `anon = false`, `authenticated = true`

### 3.3 Verify Financial Immutability Triggers
```sql
SELECT 
  event_object_table, 
  trigger_name, 
  action_timing, 
  event_manipulation 
FROM information_schema.triggers 
WHERE trigger_name LIKE '%prevent_%'
ORDER BY event_object_table;
```
*Expected Result:*
- `orders` -> `trg_prevent_order_deletion`
- `payments` -> `trg_prevent_payment_deletion`
- `refunds` -> `trg_prevent_refund_deletion`

---

## 4. Rollback & Emergency Recovery

In the event of an unexpected schema migration failure:
1. **Point-in-Time Recovery (PITR):** In Supabase Dashboard, select **Database** -> **Backups** -> **Restore** to roll back to the exact minute prior to migration execution.
2. **Idempotent Fixes:** Every migration uses `CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`, and `CREATE OR REPLACE FUNCTION`, allowing failed migrations to be safely corrected and re-run.

