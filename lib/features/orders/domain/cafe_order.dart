import '../../../core/sync/sync_models.dart';

enum OrderStatus { newOrder, preparing, ready, completed, cancelled }

extension OrderStatusLabel on OrderStatus {
  String get label => switch (this) {
    OrderStatus.newOrder => 'New',
    OrderStatus.preparing => 'Preparing',
    OrderStatus.ready => 'Ready',
    OrderStatus.completed => 'Completed',
    OrderStatus.cancelled => 'Cancelled',
  };
}

enum OrderFinancialStatus {
  unpaid,
  partiallyPaid,
  paid,
  refunded,
  partiallyRefunded,
  paymentFailed,
}

extension OrderFinancialStatusX on OrderFinancialStatus {
  String get label => switch (this) {
    OrderFinancialStatus.unpaid => 'Unpaid',
    OrderFinancialStatus.partiallyPaid => 'Partially Paid',
    OrderFinancialStatus.paid => 'Paid',
    OrderFinancialStatus.refunded => 'Refunded',
    OrderFinancialStatus.partiallyRefunded => 'Partially Refunded',
    OrderFinancialStatus.paymentFailed => 'Payment Failed',
  };

  String get dbValue => switch (this) {
    OrderFinancialStatus.unpaid => 'UNPAID',
    OrderFinancialStatus.partiallyPaid => 'PARTIALLY_PAID',
    OrderFinancialStatus.paid => 'PAID',
    OrderFinancialStatus.refunded => 'REFUNDED',
    OrderFinancialStatus.partiallyRefunded => 'PARTIALLY_REFUNDED',
    OrderFinancialStatus.paymentFailed => 'PAYMENT_FAILED',
  };

  static OrderFinancialStatus fromDb(String? value) {
    return switch (value?.toUpperCase()) {
      'PARTIALLY_PAID' => OrderFinancialStatus.partiallyPaid,
      'PAID' => OrderFinancialStatus.paid,
      'REFUNDED' => OrderFinancialStatus.refunded,
      'PARTIALLY_REFUNDED' => OrderFinancialStatus.partiallyRefunded,
      'PAYMENT_FAILED' => OrderFinancialStatus.paymentFailed,
      _ => OrderFinancialStatus.unpaid,
    };
  }
}

class OrderLine {
  const OrderLine({
    required this.productId,
    required this.name,
    required this.unitMinor,
    required this.quantity,
  });
  final String productId;
  final String name;
  final int unitMinor;
  final int quantity;
  int get totalMinor => unitMinor * quantity;
}

class CafeOrder {
  CafeOrder({
    required this.id,
    required this.number,
    required this.createdAt,
    required List<OrderLine> lines,
    this.status = OrderStatus.newOrder,
    this.financialStatus = OrderFinancialStatus.unpaid,
    this.table = 'Takeaway',
    this.instructions = '',
    this.taxMinor = 0,
    this.discountMinor = 0,
    this.serviceChargeMinor = 0,
    this.paidMinor = 0,
    this.refundedMinor = 0,
    this.taxName = 'GST',
    this.taxRateBps = 500,
    this.taxIsInclusive = false,
    this.discountReason = '',
    this.clientTxId,
    this.syncStatus = SyncStatus.synced,
    this.version = 1,
  }) : lines = List.unmodifiable(lines);

  final String id;
  final String number;
  final DateTime createdAt;
  final List<OrderLine> lines;
  final OrderStatus status;
  final OrderFinancialStatus financialStatus;
  final String table;
  final String instructions;
  final int taxMinor;
  final int discountMinor;
  final int serviceChargeMinor;
  final int paidMinor;
  final int refundedMinor;
  final String taxName;
  final int taxRateBps;
  final bool taxIsInclusive;
  final String discountReason;
  final String? clientTxId;
  final SyncStatus syncStatus;
  final int version;

  bool get isOffline => syncStatus != SyncStatus.synced;

  int get subtotalMinor => lines.fold(0, (sum, line) => sum + line.totalMinor);
  int get totalMinor => taxIsInclusive
      ? (subtotalMinor - discountMinor) + serviceChargeMinor
      : (subtotalMinor - discountMinor) + taxMinor + serviceChargeMinor;

  int get outstandingMinor => (totalMinor - paidMinor).clamp(0, totalMinor);
  bool get isFullyPaid => financialStatus == OrderFinancialStatus.paid;

  CafeOrder withStatus(OrderStatus value) => CafeOrder(
    id: id,
    number: number,
    createdAt: createdAt,
    lines: lines,
    status: value,
    financialStatus: financialStatus,
    table: table,
    instructions: instructions,
    taxMinor: taxMinor,
    discountMinor: discountMinor,
    serviceChargeMinor: serviceChargeMinor,
    paidMinor: paidMinor,
    refundedMinor: refundedMinor,
    taxName: taxName,
    taxRateBps: taxRateBps,
    taxIsInclusive: taxIsInclusive,
    discountReason: discountReason,
    clientTxId: clientTxId,
    syncStatus: syncStatus,
    version: version,
  );

  CafeOrder withFinancialStatus({
    required OrderFinancialStatus financialStatus,
    required int paidMinor,
    int? refundedMinor,
  }) => CafeOrder(
    id: id,
    number: number,
    createdAt: createdAt,
    lines: lines,
    status: status,
    financialStatus: financialStatus,
    table: table,
    instructions: instructions,
    taxMinor: taxMinor,
    discountMinor: discountMinor,
    serviceChargeMinor: serviceChargeMinor,
    paidMinor: paidMinor,
    refundedMinor: refundedMinor ?? this.refundedMinor,
    taxName: taxName,
    taxRateBps: taxRateBps,
    taxIsInclusive: taxIsInclusive,
    discountReason: discountReason,
    clientTxId: clientTxId,
    syncStatus: syncStatus,
    version: version,
  );

  CafeOrder withSyncStatus(SyncStatus status) => CafeOrder(
    id: id,
    number: number,
    createdAt: createdAt,
    lines: lines,
    status: this.status,
    financialStatus: financialStatus,
    table: table,
    instructions: instructions,
    taxMinor: taxMinor,
    discountMinor: discountMinor,
    serviceChargeMinor: serviceChargeMinor,
    paidMinor: paidMinor,
    refundedMinor: refundedMinor,
    taxName: taxName,
    taxRateBps: taxRateBps,
    taxIsInclusive: taxIsInclusive,
    discountReason: discountReason,
    clientTxId: clientTxId,
    syncStatus: status,
    version: version,
  );
}

class OrderSubmissionItem {
  const OrderSubmissionItem({
    required this.menuItemId,
    required this.quantity,
    this.selectedVariant,
    this.selectedAddons = const [],
    this.notes = '',
  });

  final String menuItemId;
  final int quantity;
  final String? selectedVariant;
  final List<String> selectedAddons;
  final String notes;

  Map<String, dynamic> toJson() => {
    'menu_item_id': menuItemId,
    'quantity': quantity,
    if (selectedVariant != null) 'selected_variant': selectedVariant,
    if (selectedAddons.isNotEmpty) 'selected_addons': selectedAddons,
    if (notes.isNotEmpty) 'notes': notes,
  };
}

class CreatedOrderResult {
  const CreatedOrderResult({
    required this.id,
    required this.orderNumber,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.totalMinor,
    this.serviceChargeMinor = 0,
    this.financialStatus = OrderFinancialStatus.unpaid,
    this.isReplay = false,
  });

  final String id;
  final String orderNumber;
  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int serviceChargeMinor;
  final int totalMinor;
  final OrderFinancialStatus financialStatus;
  final bool isReplay;
}
