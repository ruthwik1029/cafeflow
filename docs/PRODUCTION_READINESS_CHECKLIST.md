# CafeFlow — Production Readiness Checklist

This checklist defines the mandatory operational gates and verification steps required before transitioning CafeFlow into live production.

---

## 1. Environment & Secrets Setup

- [ ] **Production Supabase Project Created:** Dedicated production instance with high-availability and point-in-time recovery (PITR) enabled.
- [ ] **Environment Variables Configured:**
  - [ ] `SUPABASE_URL` set to production HTTPS endpoint (`https://<project-ref>.supabase.co`).
  - [ ] `SUPABASE_ANON_KEY` configured with production public key.
  - [ ] Service role key stored securely in CI/CD secrets (never in client applications).
- [ ] **Custom Domain & SSL:**
  - [ ] Web customer storefront mapped to production domain (e.g., `cafe.yourbrand.com`).
  - [ ] Strict HTTPS enforced with automatic TLS cert renewal.
- [ ] **Repository Hygiene:**
  - [ ] Verify `.env` is absent from git staging.
  - [ ] Verify `android/key.properties` is absent from git staging.

---

## 2. Database Migration & Security Verification

- [ ] **Apply Database Migrations (000001 through 000011):**
  - [ ] Execute `20261114000001_initial_schema.sql`
  - [ ] Execute `20261114000002_rls_policies.sql`
  - [ ] Execute `20261114000003_seed_data.sql` (or clean production seed)
  - [ ] Execute `20261114000004_auth_and_rbac.sql`
  - [ ] Execute `20261115000005_realtime_and_operations.sql`
  - [ ] Execute `20261115000006_billing_and_payments.sql`
  - [ ] Execute `20261115000007_offline_sync.sql`
  - [ ] Execute `20261115000008_tables_and_kot.sql`
  - [ ] Execute `20261116000009_inventory_and_staff.sql`
  - [ ] Execute `20261116000010_reporting_and_analytics.sql`
  - [ ] Execute `20261116000011_production_hardening.sql`
- [ ] **Security Triggers Active:**
  - [ ] Verify `prevent_financial_deletion()` prevents `DELETE` on `orders`, `payments`, `refunds`.
  - [ ] Verify `check_membership_privilege_escalation()` prevents self-promotion.
  - [ ] Verify `audit_restaurant_settings_change()` captures configuration modifications.
- [ ] **RPC Access Restrictions (SEC-01):**
  - [ ] Verify `anon` role cannot execute `create_order_with_items` or other operational RPCs.
  - [ ] Verify only `resolve_username_to_email` is callable by `anon`.

---

## 3. Platform Build & Packaging Verification

- [ ] **Windows Desktop Distribution:**
  - [ ] Compile Release runner: `flutter build windows --release`.
  - [ ] Generate Inno Setup installer: `iscc windows/installer/cafeflow_installer.iss`.
  - [ ] Verify output: `build/installer/CafeFlow-Setup-1.0.0.exe`.
  - [ ] Test install, desktop shortcut creation, launch, and uninstall cycle.
  - [ ] *(Optional for corporate deployment)* Apply EV Code Signing certificate to executable and installer.
- [ ] **Android Mobile Distribution:**
  - [ ] Populate `android/key.properties` with release keystore credentials.
  - [ ] Compile Release APK: `powershell -File tool/build_android.ps1`.
  - [ ] Compile App Bundle for Play Store: `powershell -File tool/build_android.ps1 -AppBundle`.
  - [ ] Verify APK install on physical POS tablet / mobile terminal.
- [ ] **Web SPA Distribution:**
  - [ ] Build web bundle: `flutter build web --release`.
  - [ ] Verify `vercel.json` rewrite configuration (`"source": "/(.*)", "destination": "/index.html"`).
  - [ ] Verify HTTP security headers (`nosniff`, `DENY`, `strict-origin-when-cross-origin`).

---

## 4. Operational Smoke Testing (Pre-Launch)

- [ ] **Account Onboarding:**
  - [ ] Register initial Owner account.
  - [ ] Configure Restaurant Profile (Name, Address, Tax Number, Currency, Timezone).
- [ ] **Catalog & Pricing Setup:**
  - [ ] Create categories (e.g., Beverages, Food, Retail).
  - [ ] Add menu products with prices in minor units (e.g., ₹250.00 = 25000 paise).
  - [ ] Configure ingredients and link recipes for auto-depletion.
- [ ] **Floor & Tables Setup:**
  - [ ] Add dining sections and layout tables with seating capacities.
- [ ] **Staff Accounts & Pin Codes:**
  - [ ] Create cashier, kitchen, and service staff accounts with appropriate roles.
  - [ ] Verify staff can log in using username and password.

---

## 5. End-to-End Live Workflow Validation

- [ ] **Dine-In Flow:**
  - [ ] Open table session -> table status changes to `OCCUPIED`.
  - [ ] Add items to cart -> send KOT -> ticket appears on Kitchen Display.
  - [ ] Kitchen marks ticket as `PREPARING` then `READY`.
  - [ ] Cashier generates bill and tenders payment (Cash/Card/UPI).
  - [ ] Close table session -> table status resets to `AVAILABLE`.
- [ ] **Takeaway / Quick Service Flow:**
  - [ ] Direct counter order entry -> immediate payment collection.
  - [ ] Receipt print preview formats cleanly in currency minor units.
- [ ] **Offline Resilience Test:**
  - [ ] Disconnect network / disable Wi-Fi.
  - [ ] Create order and process payment in offline mode.
  - [ ] Reconnect network -> verify sync queue automatically reconciles without duplicate orders.
- [ ] **Inventory & Purchase Order Receiving:**
  - [ ] Receive stock against a Purchase Order -> verify inventory counts increment.
  - [ ] Fulfill an order with recipe items -> verify inventory automatically decrements.
- [ ] **Reports & BI Verification:**
  - [ ] Open Owner Reports workspace.
  - [ ] Verify daily sales snapshot matches sum of settled orders.
  - [ ] Test CSV export generation for sales and inventory.

---

## 6. Post-Launch Operations & Monitoring

- [ ] **Realtime Event Monitoring:** Confirm Supabase Realtime latency is under 250ms on POS and KDS.
- [ ] **Backup Schedule:** Verify daily automated database snapshots and 7-day retention.
- [ ] **Audit Logs Review:** Periodically inspect `restaurant_settings` change log.

