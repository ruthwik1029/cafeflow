import '../../../core/routing/workspace.dart';

/// Employment status classifications.
enum EmploymentStatus {
  fullTime,
  partTime,
  casual,
  terminated;

  String get label => switch (this) {
    EmploymentStatus.fullTime => 'Full-time',
    EmploymentStatus.partTime => 'Part-time',
    EmploymentStatus.casual => 'Casual / Hourly',
    EmploymentStatus.terminated => 'Terminated',
  };

  String get dbValue => switch (this) {
    EmploymentStatus.fullTime => 'FULL_TIME',
    EmploymentStatus.partTime => 'PART_TIME',
    EmploymentStatus.casual => 'CASUAL',
    EmploymentStatus.terminated => 'TERMINATED',
  };

  static EmploymentStatus fromDb(String? raw) => switch (raw?.toUpperCase()) {
    'FULL_TIME' => EmploymentStatus.fullTime,
    'PART_TIME' => EmploymentStatus.partTime,
    'CASUAL' => EmploymentStatus.casual,
    'TERMINATED' => EmploymentStatus.terminated,
    _ => EmploymentStatus.fullTime,
  };
}

/// Operational staff profile.
class StaffProfileRecord {
  const StaffProfileRecord({
    required this.id,
    required this.userId,
    required this.restaurantId,
    required this.fullName,
    this.username = '',
    required this.role,
    this.department = 'Front of House',
    this.employmentStatus = EmploymentStatus.fullTime,
    required this.joiningDate,
    this.phone = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.notes = '',
    this.isActive = true,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String restaurantId;
  final String fullName;
  final String username;
  final WorkspaceRole role;
  final String department;
  final EmploymentStatus employmentStatus;
  final DateTime joiningDate;
  final String phone;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String notes;
  final bool isActive;
  final DateTime? createdAt;

  factory StaffProfileRecord.fromMap(
    Map<String, dynamic> map, {
    String? name,
    String? userTag,
    WorkspaceRole role = WorkspaceRole.staff,
    String? phoneNum,
    bool active = true,
  }) => StaffProfileRecord(
    id: map['id'] as String,
    userId: map['user_id'] as String,
    restaurantId: map['restaurant_id'] as String,
    fullName: name ?? (map['full_name'] as String?) ?? 'Staff Member',
    username: userTag ?? (map['username'] as String?) ?? '',
    role: role,
    department: (map['department'] as String?) ?? 'Front of House',
    employmentStatus: EmploymentStatus.fromDb(
      map['employment_status'] as String?,
    ),
    joiningDate: map['joining_date'] != null
        ? DateTime.tryParse(map['joining_date'] as String) ?? DateTime.now()
        : DateTime.now(),
    phone: phoneNum ?? (map['phone'] as String?) ?? '',
    emergencyContactName: (map['emergency_contact_name'] as String?) ?? '',
    emergencyContactPhone: (map['emergency_contact_phone'] as String?) ?? '',
    notes: (map['notes'] as String?) ?? '',
    isActive: active,
    createdAt: map['created_at'] != null
        ? DateTime.tryParse(map['created_at'] as String)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'restaurant_id': restaurantId,
    'department': department,
    'employment_status': employmentStatus.dbValue,
    'joining_date': joiningDate.toIso8601String().substring(0, 10),
    'emergency_contact_name': emergencyContactName,
    'emergency_contact_phone': emergencyContactPhone,
    'notes': notes,
  };
}

/// Work shift definition.
class ShiftRecord {
  const ShiftRecord({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.department = 'General',
    this.isActive = true,
    this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String startTime; // HH:mm:ss format
  final String endTime; // HH:mm:ss format
  final String department;
  final bool isActive;
  final DateTime? createdAt;

  String get timeRangeLabel => '$startTime - $endTime';

  factory ShiftRecord.fromMap(Map<String, dynamic> map) => ShiftRecord(
    id: map['id'] as String,
    restaurantId: map['restaurant_id'] as String,
    name: map['name'] as String,
    startTime: (map['start_time'] as String?) ?? '08:00:00',
    endTime: (map['end_time'] as String?) ?? '16:00:00',
    department: (map['department'] as String?) ?? 'General',
    isActive: (map['is_active'] as bool?) ?? true,
    createdAt: map['created_at'] != null
        ? DateTime.tryParse(map['created_at'] as String)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'name': name,
    'start_time': startTime,
    'end_time': endTime,
    'department': department,
    'is_active': isActive,
  };
}

/// Attendance session state.
enum AttendanceStatus {
  clockedIn,
  onBreak,
  clockedOut;

  String get label => switch (this) {
    AttendanceStatus.clockedIn => 'Clocked In',
    AttendanceStatus.onBreak => 'On Break',
    AttendanceStatus.clockedOut => 'Clocked Out',
  };

  String get dbValue => switch (this) {
    AttendanceStatus.clockedIn => 'CLOCKED_IN',
    AttendanceStatus.onBreak => 'ON_BREAK',
    AttendanceStatus.clockedOut => 'CLOCKED_OUT',
  };

  static AttendanceStatus fromDb(String? raw) => switch (raw?.toUpperCase()) {
    'CLOCKED_IN' => AttendanceStatus.clockedIn,
    'ON_BREAK' => AttendanceStatus.onBreak,
    'CLOCKED_OUT' => AttendanceStatus.clockedOut,
    _ => AttendanceStatus.clockedIn,
  };
}

/// Clock-in/Clock-out attendance record.
class StaffAttendanceRecord {
  const StaffAttendanceRecord({
    required this.id,
    required this.restaurantId,
    required this.userId,
    this.userName = 'Staff Member',
    this.shiftId,
    this.shiftName,
    required this.clockIn,
    this.clockOut,
    this.totalBreakMinutes = 0,
    this.status = AttendanceStatus.clockedIn,
    this.isLate = false,
    this.notes = '',
  });

  final String id;
  final String restaurantId;
  final String userId;
  final String userName;
  final String? shiftId;
  final String? shiftName;
  final DateTime clockIn;
  final DateTime? clockOut;
  final int totalBreakMinutes;
  final AttendanceStatus status;
  final bool isLate;
  final String notes;

  Duration get duration => (clockOut ?? DateTime.now()).difference(clockIn);

  String get formattedDuration {
    final m = duration.inMinutes;
    if (m < 60) return '${m}m';
    return '${duration.inHours}h ${m % 60}m';
  }

  factory StaffAttendanceRecord.fromMap(
    Map<String, dynamic> map, {
    String? staffName,
    String? sName,
  }) => StaffAttendanceRecord(
    id: map['id'] as String,
    restaurantId: map['restaurant_id'] as String,
    userId: map['user_id'] as String,
    userName: staffName ?? (map['user_name'] as String?) ?? 'Staff Member',
    shiftId: map['shift_id'] as String?,
    shiftName: sName ?? (map['shift_name'] as String?),
    clockIn: DateTime.parse(map['clock_in'] as String),
    clockOut: map['clock_out'] != null
        ? DateTime.tryParse(map['clock_out'] as String)
        : null,
    totalBreakMinutes: (map['total_break_minutes'] as num?)?.toInt() ?? 0,
    status: AttendanceStatus.fromDb(map['status'] as String?),
    isLate: (map['is_late'] as bool?) ?? false,
    notes: (map['notes'] as String?) ?? '',
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'user_id': userId,
    'shift_id': shiftId,
    'clock_in': clockIn.toIso8601String(),
    'clock_out': clockOut?.toIso8601String(),
    'total_break_minutes': totalBreakMinutes,
    'status': status.dbValue,
    'is_late': isLate,
    'notes': notes,
  };
}

/// Authorized workforce activity audit event.
class StaffAuditEventRecord {
  const StaffAuditEventRecord({
    required this.id,
    required this.restaurantId,
    required this.eventType,
    this.targetUserId,
    this.targetUserName,
    this.performedBy,
    this.performedByName,
    this.details = const {},
    required this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String eventType;
  final String? targetUserId;
  final String? targetUserName;
  final String? performedBy;
  final String? performedByName;
  final Map<String, dynamic> details;
  final DateTime createdAt;

  String get humanDescription => switch (eventType) {
    'STAFF_PROVISIONED' => 'Staff account provisioned',
    'ROLE_CHANGED' => 'Role updated to ${details['new_role'] ?? ''}',
    'STAFF_ACTIVATED' => 'Staff member activated',
    'STAFF_DEACTIVATED' => 'Staff member deactivated',
    'SHIFT_ASSIGNED' => 'Assigned to shift: ${details['shift_name'] ?? ''}',
    'ATTENDANCE_RECORDED' => 'Attendance: ${details['action'] ?? ''}',
    'INVENTORY_ADJUSTED' => 'Stock adjusted: ${details['movement_type'] ?? ''}',
    'PURCHASE_RECEIVED' =>
      'Purchase Order received: ${details['purchase_number'] ?? ''}',
    'WASTAGE_RECORDED' => 'Wastage reported: ${details['reason'] ?? ''}',
    _ => eventType,
  };

  factory StaffAuditEventRecord.fromMap(
    Map<String, dynamic> map, {
    String? targetName,
    String? actorName,
  }) => StaffAuditEventRecord(
    id: map['id'] as String,
    restaurantId: map['restaurant_id'] as String,
    eventType: map['event_type'] as String,
    targetUserId: map['target_user_id'] as String?,
    targetUserName: targetName ?? (map['target_user_name'] as String?),
    performedBy: map['performed_by'] as String?,
    performedByName: actorName ?? (map['performed_by_name'] as String?),
    details: map['details'] is Map
        ? Map<String, dynamic>.from(map['details'] as Map)
        : const {},
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'event_type': eventType,
    'target_user_id': targetUserId,
    'performed_by': performedBy,
    'details': details,
    'created_at': createdAt.toIso8601String(),
  };
}
