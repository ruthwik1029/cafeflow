# CafeFlow — Staff Management & RBAC Architecture

## 1. Overview & Security Foundation
CafeFlow implements an enterprise-grade Role-Based Access Control (RBAC) architecture hardened under SEC-01 security specifications. Staff administration, credential lifecycle, role modifications, and workspace routing are governed by database-enforced policies and client-side guards.

---

## 2. Role Hierarchy & Access Matrix

| Capability / Workspace | OWNER | ADMIN | CASHIER | KITCHEN | STAFF |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Manage Cafe & Settings** | **Yes** | No | No | No | No |
| **Staff Provisioning** | **Yes** | **Yes** *(SEC-01 Guard)* | No | No | No |
| **Role Assignment** | **Yes** | **Yes** *(SEC-01 Guard)* | No | No | No |
| **Menu & Catalog Editor** | **Yes** | **Yes** | No | No | No |
| **POS & Order Placement** | **Yes** | **Yes** | **Yes** | No | **Yes** |
| **Billing & Payments** | **Yes** | **Yes** | **Yes** | No | No |
| **Tables & Floor Management** | **Yes** | **Yes** | **Yes** | No | **Yes** |
| **Kitchen Display (KDS / KOT)** | **Yes** | **Yes** | No | **Yes** | **Yes** |
| **Stock Adjustments & Wastage**| **Yes** | **Yes** | No | **Yes** | No |
| **Purchase Orders & Receiving** | **Yes** | **Yes** | No | No | No |
| **Financial Reports & Analytics**| **Yes** | **Yes** | No | No | No |

---

## 3. SEC-01 Security Guards & Privilege Escalation Defenses

### Guard 1: Admins Cannot Provision Owner Accounts
Admins attempting to create or provision an account with `role = 'OWNER'` are blocked at both client repository and database RPC levels:
```dart
if (callerRole == WorkspaceRole.admin && role == WorkspaceRole.owner) {
  throw const AppFailure(
    'Privilege escalation violation: Admins cannot provision an OWNER account.',
  );
}
```

### Guard 2: Admins Cannot Modify or Deactivate Owners
Admins cannot modify the role of an Owner, nor can they deactivate an Owner's restaurant membership:
```dart
if (callerRole == WorkspaceRole.admin && targetCurrentRole == WorkspaceRole.owner) {
  throw const AppFailure(
    'Security violation: Admins cannot modify an Owner account.',
  );
}
```

### Guard 3: Anti-Self-Promotion
Users cannot alter their own role, preventing elevation of privileges from within an active session:
```dart
if (callerUserId == targetUserId) {
  throw const AppFailure(
    'Security violation: users cannot change their own role.',
  );
}
```

### Guard 4: Credential Administration
Staff members cannot self-service reset passwords or change usernames. Credential lifecycle is strictly controlled by authorized cafe administrators under SEC-01 RBAC policies.

---

## 4. Operational Staff Profiles (`staff_profiles`)
To separate authentication identity (`user_profiles`) from restaurant employment details, CafeFlow stores employment metadata in `staff_profiles`:
- `department`: E.g., 'Management', 'Front of House', 'Kitchen', 'Barista', 'Floater'.
- `employment_status`: `FULL_TIME`, `PART_TIME`, `CASUAL`, `TERMINATED`.
- `joining_date`: Date employee commenced active employment.
- `emergency_contact_name` & `emergency_contact_phone`: Stored for workforce safety.
- `notes`: Operational performance notes or shift agreements.

---

## 5. Workforce Audit Ledger (`staff_audit_events`)
All significant workforce and administrative activities are written to an append-only audit trail:
- Events logged: `STAFF_PROVISIONED`, `ROLE_CHANGED`, `STAFF_DEACTIVATED`, `SHIFT_CREATED`, `ATTENDANCE_RECORDED`, `STOCK_ADJUSTED`, `PURCHASE_RECEIVED`.
- Records `restaurant_id`, `actor_id` (via `auth.uid()`), `target_user_id`, structured `details` JSONB, and server timestamp.

