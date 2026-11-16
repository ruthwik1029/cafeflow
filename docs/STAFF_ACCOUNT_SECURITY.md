# CafeFlow — Staff Account Security & Credential Management

**Document Version:** 1.0.0  
**Phase:** 04 — Authentication, RBAC & Security Hardening  

---

## 1. Principles of Staff Account Management

1. **No Public Registration**: Public self-registration is permanently disabled.
2. **Administrative Provisioning Only**: Only authenticated users holding `OWNER` or `ADMIN` roles can provision staff accounts.
3. **No Self-Service Password or Username Changes**: Staff members (`CASHIER`, `KITCHEN`, `STAFF`) cannot change their own username or reset their password through the application. All credential lifecycles and recovery workflows are controlled by cafe management.
4. **Tenant-Bound Memberships**: A staff account is only authorized to act within restaurants where an active `restaurant_memberships` record exists.
5. **Anti-Self-Promotion**: A user cannot modify their own role, escalate privileges, or reactivate a revoked status.

---

## 2. Server-Side Hardening: `enforce_membership_security()` (SEC-01)

To prevent privilege escalation attacks where an `ADMIN` could promote themselves or a confederate to `OWNER`, or tamper with an existing `OWNER`'s membership, a `BEFORE INSERT OR UPDATE OR DELETE` PostgreSQL trigger is attached to `public.restaurant_memberships`:

```sql
CREATE OR REPLACE FUNCTION public.enforce_membership_security()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_role TEXT;
    v_caller_id UUID;
BEGIN
    v_caller_id := auth.uid();
    
    -- When called via migrations or service role, allow operation
    IF v_caller_id IS NULL THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    -- Anti-self-promotion: A user cannot modify or delete their own membership record
    IF (TG_OP IN ('UPDATE', 'DELETE') AND OLD.user_id = v_caller_id) THEN
        RAISE EXCEPTION 'Security violation: Users cannot modify their own membership (anti-self-promotion).'
            USING ERRCODE = '42501';
    END IF;

    -- Determine caller role in this restaurant
    SELECT role INTO v_caller_role
    FROM public.restaurant_memberships
    WHERE restaurant_id = COALESCE(NEW.restaurant_id, OLD.restaurant_id)
      AND user_id = v_caller_id
      AND is_active = TRUE;

    IF v_caller_role IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: Caller has no active membership in this restaurant.'
            USING ERRCODE = '42501';
    END IF;

    -- Only OWNER or ADMIN can insert, update, or delete memberships
    IF v_caller_role NOT IN ('OWNER', 'ADMIN') THEN
        RAISE EXCEPTION 'Unauthorized: Only OWNER and ADMIN may modify memberships.'
            USING ERRCODE = '42501';
    END IF;

    -- SEC-01 Guard: ADMIN cannot grant or revoke OWNER role
    IF v_caller_role = 'ADMIN' THEN
        -- Cannot assign OWNER role on INSERT
        IF TG_OP = 'INSERT' AND NEW.role = 'OWNER' THEN
            RAISE EXCEPTION 'Privilege escalation violation: ADMIN cannot provision an OWNER account.'
                USING ERRCODE = '42501';
        END IF;

        -- Cannot assign OWNER role or modify an existing OWNER on UPDATE
        IF TG_OP = 'UPDATE' THEN
            IF NEW.role = 'OWNER' AND OLD.role != 'OWNER' THEN
                RAISE EXCEPTION 'Privilege escalation violation: ADMIN cannot promote any user to OWNER.'
                    USING ERRCODE = '42501';
            END IF;
            IF OLD.role = 'OWNER' THEN
                RAISE EXCEPTION 'Security violation: ADMIN cannot modify an OWNER account.'
                    USING ERRCODE = '42501';
            END IF;
        END IF;

        -- Cannot delete an OWNER membership
        IF TG_OP = 'DELETE' AND OLD.role = 'OWNER' THEN
            RAISE EXCEPTION 'Security violation: ADMIN cannot remove an OWNER account.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;
```

---

## 3. Provisioning RPC: `provision_staff_member()`

Staff provisioning is executed via a controlled PostgreSQL RPC function:

```sql
CREATE OR REPLACE FUNCTION public.provision_staff_member(
    p_restaurant_id UUID,
    p_user_id UUID,
    p_role TEXT,
    p_full_name TEXT,
    p_phone TEXT DEFAULT NULL,
    p_username TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
...
```

### Verification Pipeline:
1. Validates that `p_role` is a recognized role (`OWNER`, `ADMIN`, `CASHIER`, `KITCHEN`, `STAFF`).
2. Checks that the caller holds an active `OWNER` or `ADMIN` membership in `p_restaurant_id`.
3. Verifies that an `ADMIN` caller is not attempting to create an `OWNER` account.
4. Validates that `p_user_id` exists in `auth.users`.
5. Creates or updates the `user_profiles` row (setting `full_name`, `phone`, and optional unique `username`).
6. Inserts the `restaurant_memberships` record linking the user to the restaurant with `is_active = TRUE`.

---

## 4. UI-Layer Credential Policy & Guards

In `StaffPage` (`lib/features/staff/presentation/staff_page.dart`):

- **Adaptive Role Selector**: If the caller's active role is `admin`, the `OWNER` option is filtered out of the role dropdown, preventing invalid provisioning requests.
- **Protected Actions on Owner Accounts**: For staff members holding the `OWNER` role, action buttons (Edit Role, Deactivate) are disabled when viewed by an `ADMIN`, displaying an explicit tooltip: `SEC-01 Guard: Admins cannot modify Owner accounts`.
- **Anti-Self-Promotion**: Action buttons on the caller's own card are disabled, preventing accidental or malicious self-demotion or self-elevation.
- **Security Notice Card**: Explicitly displays to all users that credential maintenance is centralized and self-service credential tampering is impossible.

