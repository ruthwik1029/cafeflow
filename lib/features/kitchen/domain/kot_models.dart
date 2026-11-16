/// Kitchen Station classification (e.g. Hot Kitchen, Beverage Bar, Bakery).
class KitchenStation {
  const KitchenStation({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.code,
    this.description = '',
    this.printerName = '',
    this.isActive = true,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String code;
  final String description;
  final String printerName;
  final bool isActive;

  factory KitchenStation.fromMap(Map<String, dynamic> map) => KitchenStation(
    id: map['id'] as String,
    restaurantId: map['restaurant_id'] as String,
    name: map['name'] as String,
    code: map['code'] as String,
    description: (map['description'] as String?) ?? '',
    printerName: (map['printer_name'] as String?) ?? '',
    isActive: (map['is_active'] as bool?) ?? true,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'name': name,
    'code': code,
    'description': description,
    'printer_name': printerName,
    'is_active': isActive,
  };
}

/// Item-level and ticket-level kitchen fulfillment states.
enum KotStatus { newOrder, accepted, preparing, ready, served, cancelled }

extension KotStatusX on KotStatus {
  String get label => switch (this) {
    KotStatus.newOrder => 'New',
    KotStatus.accepted => 'Accepted',
    KotStatus.preparing => 'Preparing',
    KotStatus.ready => 'Ready',
    KotStatus.served => 'Served',
    KotStatus.cancelled => 'Cancelled',
  };

  String get dbValue => switch (this) {
    KotStatus.newOrder => 'NEW',
    KotStatus.accepted => 'ACCEPTED',
    KotStatus.preparing => 'PREPARING',
    KotStatus.ready => 'READY',
    KotStatus.served => 'SERVED',
    KotStatus.cancelled => 'CANCELLED',
  };

  static KotStatus fromDb(String? value) => switch (value?.toUpperCase()) {
    'NEW' => KotStatus.newOrder,
    'ACCEPTED' => KotStatus.accepted,
    'PREPARING' => KotStatus.preparing,
    'READY' => KotStatus.ready,
    'SERVED' => KotStatus.served,
    'CANCELLED' => KotStatus.cancelled,
    _ => KotStatus.newOrder,
  };
}

/// Represents an individual item within a Kitchen Order Ticket.
class KotItem {
  const KotItem({
    required this.id,
    required this.kotId,
    this.orderItemId,
    required this.itemName,
    required this.quantity,
    this.selectedVariant,
    this.selectedAddons = const [],
    this.notes = '',
    this.status = KotStatus.newOrder,
    this.preparedAt,
    this.servedAt,
    this.cancelledAt,
    this.cancelReason,
    required this.createdAt,
  });

  final String id;
  final String kotId;
  final String? orderItemId;
  final String itemName;
  final int quantity;
  final String? selectedVariant;
  final List<String> selectedAddons;
  final String notes;
  final KotStatus status;
  final DateTime? preparedAt;
  final DateTime? servedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final DateTime createdAt;

  KotItem copyWith({
    KotStatus? status,
    DateTime? preparedAt,
    DateTime? servedAt,
    DateTime? cancelledAt,
    String? cancelReason,
  }) => KotItem(
    id: id,
    kotId: kotId,
    orderItemId: orderItemId,
    itemName: itemName,
    quantity: quantity,
    selectedVariant: selectedVariant,
    selectedAddons: selectedAddons,
    notes: notes,
    status: status ?? this.status,
    preparedAt: preparedAt ?? this.preparedAt,
    servedAt: servedAt ?? this.servedAt,
    cancelledAt: cancelledAt ?? this.cancelledAt,
    cancelReason: cancelReason ?? this.cancelReason,
    createdAt: createdAt,
  );

  factory KotItem.fromMap(Map<String, dynamic> map) => KotItem(
    id: map['id'] as String,
    kotId: map['kot_id'] as String,
    orderItemId: map['order_item_id'] as String?,
    itemName: map['item_name'] as String,
    quantity: (map['quantity'] as num?)?.toInt() ?? 1,
    selectedVariant: map['selected_variant'] as String?,
    selectedAddons: map['selected_addons'] != null
        ? List<String>.from(map['selected_addons'] as List)
        : const [],
    notes: (map['notes'] as String?) ?? '',
    status: KotStatusX.fromDb(map['status'] as String?),
    preparedAt: map['prepared_at'] != null
        ? DateTime.tryParse(map['prepared_at'] as String)
        : null,
    servedAt: map['served_at'] != null
        ? DateTime.tryParse(map['served_at'] as String)
        : null,
    cancelledAt: map['cancelled_at'] != null
        ? DateTime.tryParse(map['cancelled_at'] as String)
        : null,
    cancelReason: map['cancel_reason'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'kot_id': kotId,
    'order_item_id': orderItemId,
    'item_name': itemName,
    'quantity': quantity,
    'selected_variant': selectedVariant,
    'selected_addons': selectedAddons,
    'notes': notes,
    'status': status.dbValue,
    'prepared_at': preparedAt?.toIso8601String(),
    'served_at': servedAt?.toIso8601String(),
    'cancelled_at': cancelledAt?.toIso8601String(),
    'cancel_reason': cancelReason,
    'created_at': createdAt.toIso8601String(),
  };
}

/// Represents a Kitchen Order Ticket (KOT).
class KitchenOrderTicket {
  const KitchenOrderTicket({
    required this.id,
    required this.restaurantId,
    required this.orderId,
    this.tableSessionId,
    required this.kotNumber,
    this.sequenceNumber = 1,
    this.tableName = 'Takeaway',
    this.stationId,
    this.stationName,
    this.status = KotStatus.newOrder,
    this.specialInstructions = '',
    required this.createdAt,
    this.items = const [],
    this.clientTxId,
  });

  final String id;
  final String restaurantId;
  final String orderId;
  final String? tableSessionId;
  final String kotNumber;
  final int sequenceNumber;
  final String tableName;
  final String? stationId;
  final String? stationName;
  final KotStatus status;
  final String specialInstructions;
  final DateTime createdAt;
  final List<KotItem> items;
  final String? clientTxId;

  /// Human-readable elapsed preparation time
  Duration get age => DateTime.now().difference(createdAt);

  String get elapsedLabel {
    final m = age.inMinutes;
    if (m < 1) return 'Just now';
    if (m < 60) return '${m}m ago';
    return '${age.inHours}h ${m % 60}m ago';
  }

  KitchenOrderTicket copyWith({KotStatus? status, List<KotItem>? items}) =>
      KitchenOrderTicket(
        id: id,
        restaurantId: restaurantId,
        orderId: orderId,
        tableSessionId: tableSessionId,
        kotNumber: kotNumber,
        sequenceNumber: sequenceNumber,
        tableName: tableName,
        stationId: stationId,
        stationName: stationName,
        status: status ?? this.status,
        specialInstructions: specialInstructions,
        createdAt: createdAt,
        items: items ?? this.items,
        clientTxId: clientTxId,
      );

  factory KitchenOrderTicket.fromMap(
    Map<String, dynamic> map, {
    List<KotItem> items = const [],
    String? stationName,
  }) => KitchenOrderTicket(
    id: map['id'] as String,
    restaurantId: map['restaurant_id'] as String,
    orderId: map['order_id'] as String,
    tableSessionId: map['table_session_id'] as String?,
    kotNumber: map['kot_number'] as String,
    sequenceNumber: (map['sequence_number'] as num?)?.toInt() ?? 1,
    tableName: (map['table_name'] as String?) ?? 'Takeaway',
    stationId: map['station_id'] as String?,
    stationName: stationName ?? (map['station_name'] as String?),
    status: KotStatusX.fromDb(map['status'] as String?),
    specialInstructions: (map['special_instructions'] as String?) ?? '',
    createdAt: DateTime.parse(map['created_at'] as String),
    items: items,
    clientTxId: map['client_tx_id'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'order_id': orderId,
    'table_session_id': tableSessionId,
    'kot_number': kotNumber,
    'sequence_number': sequenceNumber,
    'table_name': tableName,
    'station_id': stationId,
    'status': status.dbValue,
    'special_instructions': specialInstructions,
    'created_at': createdAt.toIso8601String(),
    'client_tx_id': clientTxId,
  };
}
