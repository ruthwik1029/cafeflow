import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/database_gateway.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/routing/workspace.dart';
import '../../../core/services/backend.dart';
import '../domain/staff_models.dart';

export '../domain/staff_models.dart';

class StaffMemberRecord {
  const StaffMemberRecord({
    required this.id,
    required this.name,
    required this.role,
    this.username = '',
    this.email = '',
    this.phone = '',
    this.active = true,
    this.department = 'Front of House',
    this.employmentStatus = EmploymentStatus.fullTime,
    this.joiningDate,
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.createdAt,
  });

  final String id;
  final String name;
  final WorkspaceRole role;
  final String username;
  final String email;
  final String phone;
  final bool active;
  final String department;
  final EmploymentStatus employmentStatus;
  final DateTime? joiningDate;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final DateTime? createdAt;
}

class StaffRepository {
  StaffRepository({required this.gateway, required this.client});

  final DatabaseGateway gateway;
  final SupabaseClient? client;

  Future<List<StaffMemberRecord>> listStaff(String restaurantId) async {
    final membershipRows = await gateway.readRows(
      'restaurant_memberships',
      equals: {'restaurant_id': restaurantId},
      limit: 100,
    );

    // Fetch operational staff profiles if present
    Map<String, Map<String, dynamic>> profileMap = {};
    try {
      final profRows = await gateway.readRows(
        'staff_profiles',
        equals: {'restaurant_id': restaurantId},
        limit: 100,
      );
      for (final p in profRows) {
        profileMap[p['user_id'] as String] = p;
      }
    } catch (_) {}

    final List<StaffMemberRecord> members = [];
    for (final m in membershipRows) {
      final userId = m['user_id'] as String;
      final rawRole = (m['role'] as String? ?? 'STAFF').toUpperCase();
      final role = switch (rawRole) {
        'OWNER' => WorkspaceRole.owner,
        'ADMIN' => WorkspaceRole.admin,
        'CASHIER' => WorkspaceRole.cashier,
        'KITCHEN' => WorkspaceRole.kitchen,
        'STAFF' => WorkspaceRole.staff,
        _ => WorkspaceRole.staff,
      };

      String name = 'Staff Member';
      String phone = '';
      String username = '';

      try {
        final profileRows = await gateway.readRows(
          'user_profiles',
          equals: {'id': userId},
          limit: 1,
        );
        if (profileRows.isNotEmpty) {
          final p = profileRows.first;
          name = (p['full_name'] as String?) ?? name;
          phone = (p['phone'] as String?) ?? '';
          username = (p['username'] as String?) ?? '';
        }
      } catch (_) {}

      final opProf = profileMap[userId];

      members.add(
        StaffMemberRecord(
          id: userId,
          name: name,
          role: role,
          username: username,
          phone: phone,
          active: (m['is_active'] as bool?) ?? true,
          department: (opProf?['department'] as String?) ?? 'Front of House',
          employmentStatus: EmploymentStatus.fromDb(
            opProf?['employment_status'] as String?,
          ),
          joiningDate: opProf?['joining_date'] != null
              ? DateTime.tryParse(opProf!['joining_date'] as String)
              : null,
          emergencyContactName:
              (opProf?['emergency_contact_name'] as String?) ?? '',
          emergencyContactPhone:
              (opProf?['emergency_contact_phone'] as String?) ?? '',
          createdAt: DateTime.tryParse(m['created_at'] as String? ?? ''),
        ),
      );
    }
    return members;
  }

  /// Provision a staff account with SEC-01 protections
  Future<void> provisionStaff({
    required String restaurantId,
    required String targetUserId,
    required WorkspaceRole role,
    required String fullName,
    required WorkspaceRole callerRole,
    String? phone,
    String? username,
    String department = 'Front of House',
    EmploymentStatus employmentStatus = EmploymentStatus.fullTime,
  }) async {
    if (callerRole != WorkspaceRole.owner &&
        callerRole != WorkspaceRole.admin) {
      throw const AppFailure(
        'Unauthorized: only Owners and Admins may add staff.',
      );
    }

    // SEC-01: Admin cannot create an Owner
    if (callerRole == WorkspaceRole.admin && role == WorkspaceRole.owner) {
      throw const AppFailure(
        'Privilege escalation violation: Admins cannot provision an OWNER account.',
      );
    }

    if (client == null) {
      throw const AppFailure('Database client is unavailable.');
    }

    final dbRole = switch (role) {
      WorkspaceRole.owner => 'OWNER',
      WorkspaceRole.admin => 'ADMIN',
      WorkspaceRole.cashier => 'CASHIER',
      WorkspaceRole.kitchen => 'KITCHEN',
      WorkspaceRole.staff => 'STAFF',
    };

    try {
      await client!
          .rpc(
            'provision_staff_member',
            params: {
              'p_restaurant_id': restaurantId,
              'p_user_id': targetUserId,
              'p_role': dbRole,
              'p_full_name': fullName.trim(),
              'p_phone': phone?.trim(),
              'p_username': username?.trim(),
            },
          )
          .timeout(const Duration(seconds: 15));

      // Create operational profile
      await client!.from('staff_profiles').upsert({
        'restaurant_id': restaurantId,
        'user_id': targetUserId,
        'department': department,
        'employment_status': employmentStatus.dbValue,
        'joining_date': DateTime.now().toIso8601String().substring(0, 10),
      }, onConflict: 'restaurant_id,user_id');

      // Record audit event
      await client!.from('staff_audit_events').insert({
        'restaurant_id': restaurantId,
        'event_type': 'STAFF_PROVISIONED',
        'target_user_id': targetUserId,
        'details': {
          'role': dbRole,
          'full_name': fullName.trim(),
          'department': department,
        },
      });
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure('Permission denied: cannot provision staff.');
      }
      throw AppFailure(e.message);
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw const AppFailure('Failed to provision staff member.');
    }
  }

  /// Update staff role or status with SEC-01 guards
  Future<void> updateStaffRole({
    required String restaurantId,
    required String targetUserId,
    required WorkspaceRole newRole,
    required WorkspaceRole callerRole,
    required String callerUserId,
    required WorkspaceRole targetCurrentRole,
  }) async {
    // Caller permission
    if (callerRole != WorkspaceRole.owner &&
        callerRole != WorkspaceRole.admin) {
      throw const AppFailure(
        'Unauthorized: only Owners and Admins may modify staff roles.',
      );
    }

    // Anti-self-promotion: user cannot modify own role
    if (callerUserId == targetUserId) {
      throw const AppFailure(
        'Security violation: users cannot change their own role.',
      );
    }

    // SEC-01: Admin cannot modify an Owner
    if (callerRole == WorkspaceRole.admin &&
        targetCurrentRole == WorkspaceRole.owner) {
      throw const AppFailure(
        'Security violation: Admins cannot modify an Owner account.',
      );
    }

    // SEC-01: Admin cannot promote anyone to Owner
    if (callerRole == WorkspaceRole.admin && newRole == WorkspaceRole.owner) {
      throw const AppFailure(
        'Privilege escalation violation: Admins cannot grant the OWNER role.',
      );
    }

    if (client == null) throw const AppFailure('Database client unavailable.');

    final dbRole = switch (newRole) {
      WorkspaceRole.owner => 'OWNER',
      WorkspaceRole.admin => 'ADMIN',
      WorkspaceRole.cashier => 'CASHIER',
      WorkspaceRole.kitchen => 'KITCHEN',
      WorkspaceRole.staff => 'STAFF',
    };

    try {
      await client!
          .from('restaurant_memberships')
          .update({'role': dbRole})
          .eq('restaurant_id', restaurantId)
          .eq('user_id', targetUserId)
          .timeout(const Duration(seconds: 15));

      // Record audit event
      await client!.from('staff_audit_events').insert({
        'restaurant_id': restaurantId,
        'event_type': 'ROLE_CHANGED',
        'target_user_id': targetUserId,
        'details': {
          'previous_role': targetCurrentRole.name,
          'new_role': newRole.name,
        },
      });
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    }
  }

  /// Deactivate staff membership with SEC-01 protections
  Future<void> deactivateStaff({
    required String restaurantId,
    required String targetUserId,
    required WorkspaceRole callerRole,
    required String callerUserId,
    required WorkspaceRole targetCurrentRole,
  }) async {
    if (callerRole != WorkspaceRole.owner &&
        callerRole != WorkspaceRole.admin) {
      throw const AppFailure(
        'Unauthorized: only Owners and Admins may deactivate staff.',
      );
    }

    if (callerRole == WorkspaceRole.admin &&
        targetCurrentRole == WorkspaceRole.owner) {
      throw const AppFailure(
        'Security violation: Admins cannot deactivate an Owner.',
      );
    }

    if (client == null) throw const AppFailure('Database client unavailable.');

    try {
      await client!
          .from('restaurant_memberships')
          .update({'is_active': false})
          .eq('restaurant_id', restaurantId)
          .eq('user_id', targetUserId)
          .timeout(const Duration(seconds: 15));

      // Record audit event
      await client!.from('staff_audit_events').insert({
        'restaurant_id': restaurantId,
        'event_type': 'STAFF_DEACTIVATED',
        'target_user_id': targetUserId,
        'details': {'status': 'inactive'},
      });
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    }
  }

  // --------------------------------------------------------------------------
  // Shifts Management
  // --------------------------------------------------------------------------

  Future<List<ShiftRecord>> listShifts(
    String restaurantId, {
    bool includeInactive = false,
  }) async {
    final equals = <String, Object>{'restaurant_id': restaurantId};
    if (!includeInactive) {
      equals['is_active'] = true;
    }

    final rows = await gateway.readRows('shifts', equals: equals, limit: 50);
    final shifts = rows.map(ShiftRecord.fromMap).toList();
    shifts.sort((a, b) => a.startTime.compareTo(b.startTime));
    return shifts;
  }

  Future<ShiftRecord> createShift({
    required String restaurantId,
    required String name,
    required String startTime,
    required String endTime,
    String department = 'General',
  }) async {
    if (client == null) throw const AppFailure('Database client unavailable.');

    try {
      final res = await client!
          .from('shifts')
          .insert({
            'restaurant_id': restaurantId,
            'name': name.trim(),
            'start_time': startTime.trim(),
            'end_time': endTime.trim(),
            'department': department.trim(),
            'is_active': true,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 15));

      return ShiftRecord.fromMap(res);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    }
  }

  // --------------------------------------------------------------------------
  // Staff Attendance (Clock-In / Clock-Out)
  // --------------------------------------------------------------------------

  Future<Map<String, dynamic>> clockIn({
    required String restaurantId,
    String? targetUserId,
    String? shiftId,
    String notes = '',
  }) async {
    if (client == null) throw const AppFailure('Database client unavailable.');

    try {
      final res = await client!
          .rpc(
            'staff_clock_in',
            params: {
              'p_restaurant_id': restaurantId,
              'p_target_user_id': targetUserId,
              'p_shift_id': shiftId,
              'p_notes': notes.trim(),
            },
          )
          .timeout(const Duration(seconds: 15));

      return Map<String, dynamic>.from(res as Map);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    }
  }

  Future<Map<String, dynamic>> clockOut({
    required String restaurantId,
    required String attendanceId,
    String notes = '',
  }) async {
    if (client == null) throw const AppFailure('Database client unavailable.');

    try {
      final res = await client!
          .rpc(
            'staff_clock_out',
            params: {
              'p_restaurant_id': restaurantId,
              'p_attendance_id': attendanceId,
              'p_notes': notes.trim(),
            },
          )
          .timeout(const Duration(seconds: 15));

      return Map<String, dynamic>.from(res as Map);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    }
  }

  Future<List<StaffAttendanceRecord>> listAttendance(
    String restaurantId, {
    String? userId,
    int limit = 50,
  }) async {
    final equals = <String, Object>{'restaurant_id': restaurantId};
    if (userId != null) {
      equals['user_id'] = userId;
    }

    final rows = await gateway.readRows(
      'staff_attendance',
      equals: equals,
      limit: limit,
    );

    // Map user names and shifts
    Map<String, String> userMap = {};
    Map<String, String> shiftMap = {};
    try {
      final shifts = await listShifts(restaurantId, includeInactive: true);
      for (final s in shifts) {
        shiftMap[s.id] = s.name;
      }
      final staff = await listStaff(restaurantId);
      for (final st in staff) {
        userMap[st.id] = st.name;
      }
    } catch (_) {}

    final records = rows.map((r) {
      final uId = r['user_id'] as String;
      final sId = r['shift_id'] as String?;
      return StaffAttendanceRecord.fromMap(
        r,
        staffName: userMap[uId],
        sName: sId != null ? shiftMap[sId] : null,
      );
    }).toList();

    records.sort((a, b) => b.clockIn.compareTo(a.clockIn));
    return records;
  }

  // --------------------------------------------------------------------------
  // Audit Events Ledger
  // --------------------------------------------------------------------------

  Future<List<StaffAuditEventRecord>> listAuditEvents(
    String restaurantId, {
    String? targetUserId,
    int limit = 100,
  }) async {
    final equals = <String, Object>{'restaurant_id': restaurantId};
    if (targetUserId != null) {
      equals['target_user_id'] = targetUserId;
    }

    final rows = await gateway.readRows(
      'staff_audit_events',
      equals: equals,
      limit: limit,
    );

    final events = rows.map(StaffAuditEventRecord.fromMap).toList();
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return events;
  }
}

final staffRepositoryProvider = Provider<StaffRepository?>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend.status != BackendStatus.initialized) {
    return null;
  }
  return StaffRepository(
    gateway: ref.watch(databaseGatewayProvider),
    client: backend.client,
  );
});
