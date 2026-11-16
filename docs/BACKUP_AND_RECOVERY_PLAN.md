# CafeFlow — Backup and Disaster Recovery Plan

This plan outlines data protection protocols, backup frequencies, Point-in-Time Recovery (PITR) procedures, and business continuity safeguards for CafeFlow.

---

## 1. Objectives & Service Level Indicators

In a restaurant or cafe environment, system downtime during lunch/dinner rushes directly translates to lost revenue and customer frustration. CafeFlow is engineered to guarantee continuous operations even under complete cloud disconnection.

| Metric | Target Objective | Technical Implementation |
| :--- | :--- | :--- |
| **Recovery Point Objective (RPO)** | **< 5 minutes** | Supabase Write-Ahead Log (WAL) archiving + Drift local offline queue |
| **Recovery Time Objective (RTO)** | **< 15 minutes** | Automated failover to local offline POS + Instant cloud PITR restoration |
| **Data Retention** | **7 Years** | Financial audit records (`orders`, `payments`, `refunds`) immutable by trigger |

---

## 2. Backup Architecture

### 2.1 Cloud Database Backups (Supabase / PostgreSQL)
1. **Automated Daily Backups:** Supabase performs automatic daily physical backups of the PostgreSQL database, retained for 7 days on Pro plans and 30 days on Enterprise plans.
2. **Point-in-Time Recovery (PITR):** Continuous Write-Ahead Log (WAL) archiving enables restoring database state to any specific second within the retention window.
3. **Manual Ad-Hoc Dumps:** Before applying schema migrations or major menu/pricing restructuring, an ad-hoc logical backup must be captured:
   ```bash
   pg_dump -h db.<project-ref>.supabase.co -U postgres -d postgres -F c -b -v -f "cafeflow_backup_$(date +%Y%m%d_%H%M%S).dump"
   ```

### 2.2 Client-Side Terminal Backups (Offline-First Layer)
1. **Local SQLite Database (`drift`):** Every POS and waiter terminal maintains a local transactional database.
2. **Storage Paths:**
   - **Windows:** `%APPDATA%\CafeFlow\cafeflow_local.db`
   - **Android:** `/data/user/0/com.cafeflow.app/databases/cafeflow_local.db`
3. **Preservation Guarantee:** The Windows Inno Setup installer and uninstaller are explicitly configured to preserve this directory during upgrades, preventing offline queue loss.

---

## 3. Disaster Recovery Scenarios & Procedures

### Scenario A — Cloud Infrastructure Outage (Network / Supabase Down)
- **Impact:** Terminals cannot communicate with the central Supabase server.
- **Immediate Response:**
  1. CafeFlow seamlessly switches to **Offline Mode** with a visual indicator in the top app bar.
  2. Cashiers continue taking orders, collecting payments, and printing KOTs locally.
  3. Every transaction is appended to the local SQLite `offline_operation_queue` with a unique UUID `client_tx_id`.
- **Restoration:**
  1. Once network connectivity is restored, the `SyncEngine` initiates an automatic reconciliation batch.
  2. Server RPC `reconcile_offline_sync_batch()` processes queued operations idempotently.
  3. Real-time subscriptions re-establish and UI state reconciles.

---

### Scenario B — Terminal Hardware Failure (Tablet or POS PC Drops / Breaks)
- **Impact:** Single workstation becomes inoperable.
- **Immediate Response:**
  1. Procure a replacement Windows PC or Android tablet.
  2. Install CafeFlow from the release installer (`CafeFlow-Setup-1.0.0.exe` or `app-release.apk`).
  3. Log in with staff credentials.
- **Restoration:**
  1. The application immediately pulls active restaurant catalog, floor plan, open tables, and unfulfilled kitchen tickets from Supabase.
  2. Workstation is operational within 5 minutes.

---

### Scenario C — Accidental Data Deletion or Malicious Tampering
- **Protection Layer:**
  1. Deletion of financial records (`orders`, `payments`, `refunds`) is strictly blocked at the database engine level by triggers `trg_prevent_order_deletion`, `trg_prevent_payment_deletion`, and `trg_prevent_refund_deletion`.
  2. Unauthorized role changes or owner takeovers are blocked by `trg_prevent_privilege_escalation`.
- **Restoration via PITR (if required for non-financial entities):**
  1. Navigate to the Supabase Dashboard -> **Database** -> **Backups**.
  2. Select **Point in Time Restore**.
  3. Specify the timestamp immediately prior to the unintended modification (e.g. `2026-11-16 11:45:00 UTC`).
  4. Complete restore into a temporary clone, verify data integrity, and merge.

---

## 4. Quarterly Recovery Drill Schedule

To ensure operational preparedness, restaurant management and technical leads should perform a quarterly simulation:
- **Q1 Drill:** Simulate Wi-Fi outage during service; take 5 orders in offline mode; restore Wi-Fi and verify sync.
- **Q2 Drill:** Replace terminal hardware with fresh installation; confirm time to first order is under 5 minutes.
- **Q3 Drill:** Execute manual `pg_dump` and restore into staging environment; verify row counts across all 20+ tables.
- **Q4 Drill:** Test PITR recovery on Supabase staging project.

