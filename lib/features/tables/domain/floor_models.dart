/// Extended operational status for dining tables.
enum TableStatus {
  available,
  occupied,
  reserved,
  billRequested,
  cleaning,
  outOfService,
}

extension TableStatusX on TableStatus {
  String get label => switch (this) {
    TableStatus.available => 'Available',
    TableStatus.occupied => 'Occupied',
    TableStatus.reserved => 'Reserved',
    TableStatus.billRequested => 'Bill Requested',
    TableStatus.cleaning => 'Cleaning',
    TableStatus.outOfService => 'Out of Service',
  };

  String get dbValue => switch (this) {
    TableStatus.available => 'AVAILABLE',
    TableStatus.occupied => 'OCCUPIED',
    TableStatus.reserved => 'RESERVED',
    TableStatus.billRequested => 'BILL_REQUESTED',
    TableStatus.cleaning => 'CLEANING',
    TableStatus.outOfService => 'OUT_OF_SERVICE',
  };

  static TableStatus fromDb(String? value) => switch (value?.toUpperCase()) {
    'AVAILABLE' => TableStatus.available,
    'OCCUPIED' => TableStatus.occupied,
    'RESERVED' => TableStatus.reserved,
    'BILL_REQUESTED' => TableStatus.billRequested,
    'CLEANING' => TableStatus.cleaning,
    'OUT_OF_SERVICE' => TableStatus.outOfService,
    _ => TableStatus.available,
  };
}

/// Represents a configurable floor section (e.g. Main Dining, Terrace, Bar).
class FloorSection {
  const FloorSection({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.description = '',
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String description;
  final int sortOrder;
  final bool isActive;

  factory FloorSection.fromMap(Map<String, dynamic> map) => FloorSection(
    id: map['id'] as String,
    restaurantId: map['restaurant_id'] as String,
    name: map['name'] as String,
    description: (map['description'] as String?) ?? '',
    sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    isActive: (map['is_active'] as bool?) ?? true,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'name': name,
    'description': description,
    'sort_order': sortOrder,
    'is_active': isActive,
  };
}

/// Represents a dining table on the floor.
class DiningTableRecord {
  const DiningTableRecord({
    required this.id,
    required this.restaurantId,
    required this.tableNumber,
    required this.capacity,
    required this.status,
    this.sectionId,
    this.sectionName,
    this.activeSessionId,
    this.currentOrderNumber,
    this.currentOrderId,
    this.occupiedSince,
  });

  final String id;
  final String restaurantId;
  final String tableNumber;
  final int capacity;
  final TableStatus status;
  final String? sectionId;
  final String? sectionName;
  final String? activeSessionId;
  final String? currentOrderNumber;
  final String? currentOrderId;
  final DateTime? occupiedSince;

  DiningTableRecord copyWith({
    TableStatus? status,
    String? sectionId,
    String? sectionName,
    String? activeSessionId,
    String? currentOrderNumber,
    String? currentOrderId,
    DateTime? occupiedSince,
  }) => DiningTableRecord(
    id: id,
    restaurantId: restaurantId,
    tableNumber: tableNumber,
    capacity: capacity,
    status: status ?? this.status,
    sectionId: sectionId ?? this.sectionId,
    sectionName: sectionName ?? this.sectionName,
    activeSessionId: activeSessionId ?? this.activeSessionId,
    currentOrderNumber: currentOrderNumber ?? this.currentOrderNumber,
    currentOrderId: currentOrderId ?? this.currentOrderId,
    occupiedSince: occupiedSince ?? this.occupiedSince,
  );

  factory DiningTableRecord.fromMap(
    Map<String, dynamic> map, {
    String? sectionName,
  }) => DiningTableRecord(
    id: map['id'] as String,
    restaurantId: map['restaurant_id'] as String,
    tableNumber: map['table_number'] as String,
    capacity: (map['capacity'] as num?)?.toInt() ?? 4,
    status: TableStatusX.fromDb(map['status'] as String?),
    sectionId: map['section_id'] as String?,
    sectionName: sectionName ?? (map['section_name'] as String?),
    activeSessionId: map['active_session_id'] as String?,
    currentOrderNumber: map['current_order_number'] as String?,
    currentOrderId: map['current_order_id'] as String?,
    occupiedSince: map['occupied_since'] != null
        ? DateTime.tryParse(map['occupied_since'] as String)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'table_number': tableNumber,
    'capacity': capacity,
    'status': status.dbValue,
    'section_id': sectionId,
    'active_session_id': activeSessionId,
  };
}

/// Lifecycle status for table sessions.
enum TableSessionStatus { active, billRequested, closed, transferred, merged }

extension TableSessionStatusX on TableSessionStatus {
  String get dbValue => switch (this) {
    TableSessionStatus.active => 'ACTIVE',
    TableSessionStatus.billRequested => 'BILL_REQUESTED',
    TableSessionStatus.closed => 'CLOSED',
    TableSessionStatus.transferred => 'TRANSFERRED',
    TableSessionStatus.merged => 'MERGED',
  };

  static TableSessionStatus fromDb(String? value) =>
      switch (value?.toUpperCase()) {
        'ACTIVE' => TableSessionStatus.active,
        'BILL_REQUESTED' => TableSessionStatus.billRequested,
        'CLOSED' => TableSessionStatus.closed,
        'TRANSFERRED' => TableSessionStatus.transferred,
        'MERGED' => TableSessionStatus.merged,
        _ => TableSessionStatus.active,
      };
}

/// Represents an active or historical table dining session.
class TableSession {
  const TableSession({
    required this.id,
    required this.restaurantId,
    required this.tableId,
    required this.tableNumber,
    this.guestCount = 1,
    this.status = TableSessionStatus.active,
    required this.openedAt,
    this.closedAt,
    this.currentOrderId,
    this.openedBy,
    this.closedBy,
    this.notes = '',
  });

  final String id;
  final String restaurantId;
  final String tableId;
  final String tableNumber;
  final int guestCount;
  final TableSessionStatus status;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String? currentOrderId;
  final String? openedBy;
  final String? closedBy;
  final String notes;

  factory TableSession.fromMap(Map<String, dynamic> map, {String? tableNum}) =>
      TableSession(
        id: map['id'] as String,
        restaurantId: map['restaurant_id'] as String,
        tableId: map['table_id'] as String,
        tableNumber: tableNum ?? (map['table_number'] as String? ?? 'Table'),
        guestCount: (map['guest_count'] as num?)?.toInt() ?? 1,
        status: TableSessionStatusX.fromDb(map['status'] as String?),
        openedAt: DateTime.parse(map['opened_at'] as String),
        closedAt: map['closed_at'] != null
            ? DateTime.tryParse(map['closed_at'] as String)
            : null,
        currentOrderId: map['current_order_id'] as String?,
        openedBy: map['opened_by'] as String?,
        closedBy: map['closed_by'] as String?,
        notes: (map['notes'] as String?) ?? '',
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'table_id': tableId,
    'guest_count': guestCount,
    'status': status.dbValue,
    'opened_at': openedAt.toIso8601String(),
    'closed_at': closedAt?.toIso8601String(),
    'current_order_id': currentOrderId,
    'opened_by': openedBy,
    'closed_by': closedBy,
    'notes': notes,
  };

  Duration get duration => (closedAt ?? DateTime.now()).difference(openedAt);

  String get formattedDuration {
    final m = duration.inMinutes;
    if (m < 1) return 'Just seated';
    if (m < 60) return '${m}m';
    return '${duration.inHours}h ${m % 60}m';
  }

  TableSession copyWith({
    String? id,
    String? restaurantId,
    String? tableId,
    String? tableNumber,
    int? guestCount,
    TableSessionStatus? status,
    DateTime? openedAt,
    DateTime? closedAt,
    String? currentOrderId,
    String? openedBy,
    String? closedBy,
    String? notes,
  }) => TableSession(
    id: id ?? this.id,
    restaurantId: restaurantId ?? this.restaurantId,
    tableId: tableId ?? this.tableId,
    tableNumber: tableNumber ?? this.tableNumber,
    guestCount: guestCount ?? this.guestCount,
    status: status ?? this.status,
    openedAt: openedAt ?? this.openedAt,
    closedAt: closedAt ?? this.closedAt,
    currentOrderId: currentOrderId ?? this.currentOrderId,
    openedBy: openedBy ?? this.openedBy,
    closedBy: closedBy ?? this.closedBy,
    notes: notes ?? this.notes,
  );
}
