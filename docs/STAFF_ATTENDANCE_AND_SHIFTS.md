# CafeFlow — Staff Attendance & Shift Scheduling Architecture

## 1. Overview
CafeFlow's workforce subsystem provides shift definition, timeclock duty tracking, meal and rest break logging, and attendance auditing.

---

## 2. Shift Definition (`shifts`)
Shifts define recurring or daily duty windows:
- `name`: E.g. 'Morning Opening Shift', 'Mid-day Rush Shift', 'Evening Closing Shift'.
- `start_time` & `end_time`: `TIME` columns formatted as `HH:mm:ss` (e.g. `07:00:00` to `15:00:00`).
- `department`: Departmental allocation (e.g. 'Barista & Front of House', 'Kitchen & Dish').
- `is_active`: Toggle allowing shifts to be retired without breaking historical attendance records.

---

## 3. Database Engine Guard: Partial Unique Index on Active Clock-Ins

In physical restaurant operations, an employee must not be allowed to clock in multiple times concurrently (e.g., from different terminals or due to sync retries).

CafeFlow enforces this safety invariant at the PostgreSQL engine level using a **partial unique index**:

```sql
CREATE UNIQUE INDEX idx_unique_active_clock_in 
ON staff_attendance(restaurant_id, user_id) 
WHERE status IN ('CLOCKED_IN', 'ON_BREAK');
```

### Impact & Guarantees:
- An employee can have unlimited historical records with `status = 'CLOCKED_OUT'`.
- An employee can have at most **one** record with `status IN ('CLOCKED_IN', 'ON_BREAK')` per restaurant.
- Any attempt to clock in a second time while an active session exists triggers an immediate unique constraint violation at the database level (`23505`), completely preventing duplicate active sessions across race conditions and parallel devices.

---

## 4. Clock-In / Clock-Out State Machine

```
              +--------------------------+
              |       CLOCKED_OUT        |
              +-------------+------------+
                            |
                 staff_clock_in()
                            v
              +--------------------------+
    +-------->|        CLOCKED_IN        |
    |         +-------------+------------+
    |                       |
End Break                   | Start Break
    |                       v
    |         +--------------------------+
    +---------+         ON_BREAK         |
              +-------------+------------+
                            |
                 staff_clock_out()
                            v
              +--------------------------+
              |       CLOCKED_OUT        |
              +--------------------------+
```

### Transactional RPCs:
1. `staff_clock_in(p_restaurant_id, p_target_user_id, p_shift_id, p_notes)`:
   - Validates caller permissions (admin or self).
   - Automatically checks for late arrival against shift `start_time`.
   - Inserts record into `staff_attendance` with `status = 'CLOCKED_IN'`.
   - Engine partial unique index prevents concurrent active clock-ins.
   - Logs audit event: `ATTENDANCE_RECORDED` with `action = 'CLOCK_IN'`.

2. `staff_clock_out(p_restaurant_id, p_attendance_id, p_break_minutes, p_notes)`:
   - Sets `clock_out = NOW()`.
   - Computes total duration.
   - Increments `total_break_minutes`.
   - Transitions `status = 'CLOCKED_OUT'`.
   - Logs audit event: `ATTENDANCE_RECORDED` with `action = 'CLOCK_OUT'`.

---

## 5. Offline Attendance Synchronization
- When working offline, tablets record clock-in / clock-out events locally in `staff_attendance`.
- `CafeSyncService.queueOfflineAttendance` creates durable sync queue operations with `SyncOperationType.recordAttendance`.
- When connectivity resumes, the sync queue dispatches attendance transactions to the cloud with client transaction IDs, preserving local timestamps and respecting database engine guards.

