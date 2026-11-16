import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/workspace.dart';
import '../../../core/services/backend.dart';
import '../../auth/application/auth_controller.dart';
import '../data/staff_repository.dart';

export '../data/staff_repository.dart';

/// Active staff roster provider.
final staffListProvider = FutureProvider<List<StaffMemberRecord>>((ref) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(staffRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      repo != null &&
      restaurantId != null) {
    try {
      return await repo.listStaff(restaurantId);
    } catch (_) {}
  }

  // Demo fallback team members
  return const [
    StaffMemberRecord(
      id: 'usr-1',
      name: 'Aanya Rao',
      role: WorkspaceRole.owner,
      username: 'aanya.owner',
      phone: '+91 98200 44332',
      department: 'Management',
      employmentStatus: EmploymentStatus.fullTime,
    ),
    StaffMemberRecord(
      id: 'usr-2',
      name: 'Kabir Shah',
      role: WorkspaceRole.admin,
      username: 'kabir.admin',
      phone: '+91 98450 11223',
      department: 'Management',
      employmentStatus: EmploymentStatus.fullTime,
    ),
    StaffMemberRecord(
      id: 'usr-3',
      name: 'Pooja Nair',
      role: WorkspaceRole.cashier,
      username: 'pooja.cashier',
      phone: '+91 98765 43210',
      department: 'Front of House',
      employmentStatus: EmploymentStatus.fullTime,
    ),
    StaffMemberRecord(
      id: 'usr-4',
      name: 'Rohan Mehra',
      role: WorkspaceRole.kitchen,
      username: 'rohan.kitchen',
      phone: '+91 99100 88776',
      department: 'Kitchen',
      employmentStatus: EmploymentStatus.fullTime,
    ),
    StaffMemberRecord(
      id: 'usr-5',
      name: 'Neha Verma',
      role: WorkspaceRole.staff,
      username: 'neha.staff',
      phone: '+91 98111 22334',
      department: 'Barista',
      employmentStatus: EmploymentStatus.partTime,
    ),
  ];
});

/// Configured work shifts provider.
final shiftsProvider = FutureProvider<List<ShiftRecord>>((ref) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(staffRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      repo != null &&
      restaurantId != null) {
    try {
      return await repo.listShifts(restaurantId);
    } catch (_) {}
  }

  return const [
    ShiftRecord(
      id: 'shift-1',
      restaurantId: 'demo-rest',
      name: 'Morning Opening Shift',
      startTime: '07:00:00',
      endTime: '15:00:00',
      department: 'Barista & Front of House',
    ),
    ShiftRecord(
      id: 'shift-2',
      restaurantId: 'demo-rest',
      name: 'Evening Dinner Rush Shift',
      startTime: '15:00:00',
      endTime: '23:00:00',
      department: 'Kitchen & Floor',
    ),
  ];
});

/// Staff attendance log provider.
final attendanceListProvider = FutureProvider<List<StaffAttendanceRecord>>((
  ref,
) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(staffRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      repo != null &&
      restaurantId != null) {
    try {
      return await repo.listAttendance(restaurantId);
    } catch (_) {}
  }

  final now = DateTime.now();
  return [
    StaffAttendanceRecord(
      id: 'att-1',
      restaurantId: 'demo-rest',
      userId: 'usr-3',
      userName: 'Pooja Nair',
      shiftName: 'Morning Opening Shift',
      clockIn: now.subtract(const Duration(hours: 3)),
      status: AttendanceStatus.clockedIn,
    ),
    StaffAttendanceRecord(
      id: 'att-2',
      restaurantId: 'demo-rest',
      userId: 'usr-4',
      userName: 'Rohan Mehra',
      shiftName: 'Morning Opening Shift',
      clockIn: now.subtract(const Duration(hours: 3, minutes: 15)),
      status: AttendanceStatus.clockedIn,
      isLate: true,
      notes: 'Traffic delay on ring road',
    ),
  ];
});

/// Workforce audit events ledger provider.
final staffAuditEventsProvider = FutureProvider<List<StaffAuditEventRecord>>((
  ref,
) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(staffRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      repo != null &&
      restaurantId != null) {
    try {
      return await repo.listAuditEvents(restaurantId);
    } catch (_) {}
  }

  final now = DateTime.now();
  return [
    StaffAuditEventRecord(
      id: 'aud-1',
      restaurantId: 'demo-rest',
      eventType: 'STAFF_PROVISIONED',
      targetUserName: 'Neha Verma',
      performedByName: 'Aanya Rao',
      details: const {'role': 'STAFF', 'department': 'Barista'},
      createdAt: now.subtract(const Duration(days: 1)),
    ),
    StaffAuditEventRecord(
      id: 'aud-2',
      restaurantId: 'demo-rest',
      eventType: 'PURCHASE_RECEIVED',
      performedByName: 'Kabir Shah',
      details: const {'purchase_number': 'PO-2026-001', 'items_received': 2},
      createdAt: now.subtract(const Duration(hours: 5)),
    ),
  ];
});
