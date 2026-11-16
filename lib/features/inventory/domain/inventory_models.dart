/// Supported units of measurement for inventory items.
enum InventoryUnit {
  pieces,
  kilograms,
  grams,
  litres,
  millilitres,
  packs,
  boxes;

  String get label => switch (this) {
    InventoryUnit.pieces => 'Pieces (pcs)',
    InventoryUnit.kilograms => 'Kilograms (kg)',
    InventoryUnit.grams => 'Grams (g)',
    InventoryUnit.litres => 'Litres (L)',
    InventoryUnit.millilitres => 'Millilitres (mL)',
    InventoryUnit.packs => 'Packs (pk)',
    InventoryUnit.boxes => 'Boxes (box)',
  };

  String get shortLabel => switch (this) {
    InventoryUnit.pieces => 'pcs',
    InventoryUnit.kilograms => 'kg',
    InventoryUnit.grams => 'g',
    InventoryUnit.litres => 'L',
    InventoryUnit.millilitres => 'mL',
    InventoryUnit.packs => 'pk',
    InventoryUnit.boxes => 'box',
  };

  static InventoryUnit parse(String? raw) {
    final v = raw?.trim().toLowerCase();
    return switch (v) {
      'kg' || 'kilograms' || 'kilogram' => InventoryUnit.kilograms,
      'g' || 'grams' || 'gram' => InventoryUnit.grams,
      'l' || 'litres' || 'liters' || 'litre' => InventoryUnit.litres,
      'ml' || 'millilitres' || 'milliliters' => InventoryUnit.millilitres,
      'pk' || 'pack' || 'packs' => InventoryUnit.packs,
      'box' || 'boxes' => InventoryUnit.boxes,
      _ => InventoryUnit.pieces,
    };
  }
}

/// Stock ledger movement types.
enum StockMovementType {
  purchase,
  saleConsumption,
  manualAdjustment,
  wastage,
  damage,
  returnMovement,
  transfer,
  reversal;

  String get label => switch (this) {
    StockMovementType.purchase => 'Purchase / Receipt',
    StockMovementType.saleConsumption => 'Sale Consumption',
    StockMovementType.manualAdjustment => 'Manual Adjustment',
    StockMovementType.wastage => 'Wastage / Spoilage',
    StockMovementType.damage => 'Damaged Goods',
    StockMovementType.returnMovement => 'Vendor Return',
    StockMovementType.transfer => 'Internal Transfer',
    StockMovementType.reversal => 'Reversal Correction',
  };

  String get dbValue => switch (this) {
    StockMovementType.purchase => 'PURCHASE',
    StockMovementType.saleConsumption => 'SALE_CONSUMPTION',
    StockMovementType.manualAdjustment => 'MANUAL_ADJUSTMENT',
    StockMovementType.wastage => 'WASTAGE',
    StockMovementType.damage => 'DAMAGE',
    StockMovementType.returnMovement => 'RETURN',
    StockMovementType.transfer => 'TRANSFER',
    StockMovementType.reversal => 'REVERSAL',
  };

  static StockMovementType fromDb(String? raw) => switch (raw?.toUpperCase()) {
    'PURCHASE' => StockMovementType.purchase,
    'SALE_CONSUMPTION' || 'USAGE' => StockMovementType.saleConsumption,
    'MANUAL_ADJUSTMENT' || 'ADJUSTMENT' => StockMovementType.manualAdjustment,
    'WASTAGE' => StockMovementType.wastage,
    'DAMAGE' => StockMovementType.damage,
    'RETURN' => StockMovementType.returnMovement,
    'TRANSFER' => StockMovementType.transfer,
    'REVERSAL' => StockMovementType.reversal,
    _ => StockMovementType.manualAdjustment,
  };
}

/// Category grouping for inventory items.
class InventoryCategory {
  const InventoryCategory({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String name;
  final DateTime? createdAt;

  factory InventoryCategory.fromMap(Map<String, dynamic> map) =>
      InventoryCategory(
        id: map['id'] as String,
        restaurantId: map['restaurant_id'] as String,
        name: map['name'] as String,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'name': name,
    'created_at': createdAt?.toIso8601String(),
  };
}

/// Vendor / Supplier profile.
class Supplier {
  const Supplier({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.contactName = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.notes = '',
    this.isActive = true,
    this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String contactName;
  final String email;
  final String phone;
  final String address;
  final String notes;
  final bool isActive;
  final DateTime? createdAt;

  factory Supplier.fromMap(Map<String, dynamic> map) => Supplier(
    id: map['id'] as String,
    restaurantId: map['restaurant_id'] as String,
    name: map['name'] as String,
    contactName: (map['contact_name'] as String?) ?? '',
    email: (map['email'] as String?) ?? '',
    phone: (map['phone'] as String?) ?? '',
    address: (map['address'] as String?) ?? '',
    notes: (map['notes'] as String?) ?? '',
    isActive: (map['is_active'] as bool?) ?? true,
    createdAt: map['created_at'] != null
        ? DateTime.tryParse(map['created_at'] as String)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'name': name,
    'contact_name': contactName,
    'email': email,
    'phone': phone,
    'address': address,
    'notes': notes,
    'is_active': isActive,
    'created_at': createdAt?.toIso8601String(),
  };
}

/// Comprehensive inventory item definition.
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.unit,
    required this.currentStock,
    this.minimumStock = 0.0,
    required this.reorderLevel,
    this.costPerUnitMinor = 0,
    this.sku,
    this.categoryId,
    this.categoryName = 'General',
    this.supplierId,
    this.supplierName,
    this.storageLocation = 'Kitchen Pantry',
    this.isArchived = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String unit;
  final double currentStock;
  final double minimumStock;
  final double reorderLevel;
  final int costPerUnitMinor;
  final String? sku;
  final String? categoryId;
  final String categoryName;
  final String? supplierId;
  final String? supplierName;
  final String storageLocation;
  final bool isArchived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isOutOfStock => currentStock <= 0;
  bool get isLow => currentStock <= reorderLevel;
  bool get isLowStock => currentStock <= reorderLevel && !isOutOfStock;

  /// Current inventory asset value in minor units (integer)
  int get stockValuationMinor => (currentStock * costPerUnitMinor).round();

  InventoryItem copyWith({
    String? name,
    String? unit,
    double? currentStock,
    double? minimumStock,
    double? reorderLevel,
    int? costPerUnitMinor,
    String? sku,
    String? categoryId,
    String? categoryName,
    String? supplierId,
    String? supplierName,
    String? storageLocation,
    bool? isArchived,
  }) => InventoryItem(
    id: id,
    restaurantId: restaurantId,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    currentStock: currentStock ?? this.currentStock,
    minimumStock: minimumStock ?? this.minimumStock,
    reorderLevel: reorderLevel ?? this.reorderLevel,
    costPerUnitMinor: costPerUnitMinor ?? this.costPerUnitMinor,
    sku: sku ?? this.sku,
    categoryId: categoryId ?? this.categoryId,
    categoryName: categoryName ?? this.categoryName,
    supplierId: supplierId ?? this.supplierId,
    supplierName: supplierName ?? this.supplierName,
    storageLocation: storageLocation ?? this.storageLocation,
    isArchived: isArchived ?? this.isArchived,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  factory InventoryItem.fromMap(
    Map<String, dynamic> map, {
    String? catName,
    String? supName,
  }) => InventoryItem(
    id: map['id'] as String,
    restaurantId: map['restaurant_id'] as String,
    name: map['name'] as String,
    unit: (map['unit'] as String?) ?? 'pcs',
    currentStock: (map['current_stock'] as num?)?.toDouble() ?? 0.0,
    minimumStock: (map['minimum_stock'] as num?)?.toDouble() ?? 0.0,
    reorderLevel: (map['reorder_level'] as num?)?.toDouble() ?? 0.0,
    costPerUnitMinor: (map['cost_per_unit_minor'] as num?)?.toInt() ?? 0,
    sku: map['sku'] as String?,
    categoryId: map['category_id'] as String?,
    categoryName: catName ?? (map['category_name'] as String?) ?? 'General',
    supplierId: map['supplier_id'] as String?,
    supplierName: supName ?? (map['supplier_name'] as String?),
    storageLocation: (map['storage_location'] as String?) ?? 'Kitchen Pantry',
    isArchived: (map['is_archived'] as bool?) ?? false,
    createdAt: map['created_at'] != null
        ? DateTime.tryParse(map['created_at'] as String)
        : null,
    updatedAt: map['updated_at'] != null
        ? DateTime.tryParse(map['updated_at'] as String)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'name': name,
    'unit': unit,
    'current_stock': currentStock,
    'minimum_stock': minimumStock,
    'reorder_level': reorderLevel,
    'cost_per_unit_minor': costPerUnitMinor,
    'sku': sku,
    'category_id': categoryId,
    'supplier_id': supplierId,
    'storage_location': storageLocation,
    'is_archived': isArchived,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };
}

/// Immutable stock movement ledger entry.
class StockMovement {
  const StockMovement({
    required this.id,
    required this.restaurantId,
    required this.inventoryItemId,
    this.itemName = 'Ingredient',
    required this.movementType,
    required this.quantityChange,
    required this.previousStock,
    required this.newStock,
    required this.unit,
    this.reference = '',
    this.reason = '',
    this.performedBy,
    this.performedByName,
    required this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String inventoryItemId;
  final String itemName;
  final StockMovementType movementType;
  final double quantityChange;
  final double previousStock;
  final double newStock;
  final String unit;
  final String reference;
  final String reason;
  final String? performedBy;
  final String? performedByName;
  final DateTime createdAt;

  factory StockMovement.fromMap(
    Map<String, dynamic> map, {
    String? itemTitle,
    String? actorName,
  }) => StockMovement(
    id: map['id'] as String,
    restaurantId: map['restaurant_id'] as String,
    inventoryItemId: map['inventory_item_id'] as String,
    itemName: itemTitle ?? (map['item_name'] as String?) ?? 'Ingredient',
    movementType: StockMovementType.fromDb(map['movement_type'] as String?),
    quantityChange: (map['quantity_change'] as num?)?.toDouble() ?? 0.0,
    previousStock: (map['previous_stock'] as num?)?.toDouble() ?? 0.0,
    newStock: (map['new_stock'] as num?)?.toDouble() ?? 0.0,
    unit: (map['unit'] as String?) ?? '',
    reference: (map['reference'] as String?) ?? '',
    reason: (map['reason'] as String?) ?? '',
    performedBy: map['performed_by'] as String?,
    performedByName: actorName ?? (map['performed_by_name'] as String?),
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'inventory_item_id': inventoryItemId,
    'movement_type': movementType.dbValue,
    'quantity_change': quantityChange,
    'previous_stock': previousStock,
    'new_stock': newStock,
    'unit': unit,
    'reference': reference,
    'reason': reason,
    'performed_by': performedBy,
    'created_at': createdAt.toIso8601String(),
  };
}

/// Menu-item recipe ingredient specification.
class MenuItemIngredient {
  const MenuItemIngredient({
    required this.id,
    required this.restaurantId,
    required this.menuItemId,
    required this.inventoryItemId,
    this.inventoryItemName = 'Ingredient',
    required this.quantity,
    required this.unit,
    this.notes = '',
    this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String menuItemId;
  final String inventoryItemId;
  final String inventoryItemName;
  final double quantity;
  final String unit;
  final String notes;
  final DateTime? createdAt;

  factory MenuItemIngredient.fromMap(
    Map<String, dynamic> map, {
    String? ingName,
  }) => MenuItemIngredient(
    id: map['id'] as String,
    restaurantId: map['restaurant_id'] as String,
    menuItemId: map['menu_item_id'] as String,
    inventoryItemId: map['inventory_item_id'] as String,
    inventoryItemName:
        ingName ?? (map['inventory_item_name'] as String?) ?? 'Ingredient',
    quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
    unit: (map['unit'] as String?) ?? 'g',
    notes: (map['notes'] as String?) ?? '',
    createdAt: map['created_at'] != null
        ? DateTime.tryParse(map['created_at'] as String)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'menu_item_id': menuItemId,
    'inventory_item_id': inventoryItemId,
    'quantity': quantity,
    'unit': unit,
    'notes': notes,
  };
}

/// Purchase order item row.
class PurchaseItemRecord {
  const PurchaseItemRecord({
    required this.id,
    required this.purchaseId,
    required this.inventoryItemId,
    this.inventoryItemName = 'Item',
    required this.quantity,
    required this.unit,
    this.unitCostMinor = 0,
    this.totalCostMinor = 0,
    this.quantityReceived = 0.0,
  });

  final String id;
  final String purchaseId;
  final String inventoryItemId;
  final String inventoryItemName;
  final double quantity;
  final String unit;
  final int unitCostMinor;
  final int totalCostMinor;
  final double quantityReceived;

  factory PurchaseItemRecord.fromMap(
    Map<String, dynamic> map, {
    String? itemName,
  }) => PurchaseItemRecord(
    id: map['id'] as String,
    purchaseId: map['purchase_id'] as String,
    inventoryItemId: map['inventory_item_id'] as String,
    inventoryItemName: itemName ?? (map['item_name'] as String?) ?? 'Item',
    quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
    unit: (map['unit'] as String?) ?? 'pcs',
    unitCostMinor: (map['unit_cost_minor'] as num?)?.toInt() ?? 0,
    totalCostMinor: (map['total_cost_minor'] as num?)?.toInt() ?? 0,
    quantityReceived: (map['quantity_received'] as num?)?.toDouble() ?? 0.0,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'purchase_id': purchaseId,
    'inventory_item_id': inventoryItemId,
    'quantity': quantity,
    'unit': unit,
    'unit_cost_minor': unitCostMinor,
    'total_cost_minor': totalCostMinor,
    'quantity_received': quantityReceived,
  };
}

/// Purchase Order header record.
class PurchaseRecord {
  const PurchaseRecord({
    required this.id,
    required this.restaurantId,
    required this.purchaseNumber,
    this.supplierId,
    this.supplierName = 'Vendor',
    this.status = 'ORDERED',
    required this.purchaseDate,
    this.expectedDeliveryDate,
    this.subtotalMinor = 0,
    this.taxMinor = 0,
    this.additionalChargesMinor = 0,
    this.totalMinor = 0,
    this.notes = '',
    this.receivedAt,
    this.receivedBy,
    this.receivedByName,
    this.createdBy,
    this.items = const [],
  });

  final String id;
  final String restaurantId;
  final String purchaseNumber;
  final String? supplierId;
  final String supplierName;
  final String status;
  final DateTime purchaseDate;
  final DateTime? expectedDeliveryDate;
  final int subtotalMinor;
  final int taxMinor;
  final int additionalChargesMinor;
  final int totalMinor;
  final String notes;
  final DateTime? receivedAt;
  final String? receivedBy;
  final String? receivedByName;
  final String? createdBy;
  final List<PurchaseItemRecord> items;

  bool get isReceived => status == 'RECEIVED';
  bool get isCancelled => status == 'CANCELLED';

  factory PurchaseRecord.fromMap(
    Map<String, dynamic> map, {
    String? supName,
    String? receiverName,
    List<PurchaseItemRecord> items = const [],
  }) => PurchaseRecord(
    id: map['id'] as String,
    restaurantId: map['restaurant_id'] as String,
    purchaseNumber: map['purchase_number'] as String,
    supplierId: map['supplier_id'] as String?,
    supplierName: supName ?? (map['supplier_name'] as String?) ?? 'Vendor',
    status: (map['status'] as String?) ?? 'ORDERED',
    purchaseDate: DateTime.parse(map['purchase_date'] as String),
    expectedDeliveryDate: map['expected_delivery_date'] != null
        ? DateTime.tryParse(map['expected_delivery_date'] as String)
        : null,
    subtotalMinor: (map['subtotal_minor'] as num?)?.toInt() ?? 0,
    taxMinor: (map['tax_minor'] as num?)?.toInt() ?? 0,
    additionalChargesMinor:
        (map['additional_charges_minor'] as num?)?.toInt() ?? 0,
    totalMinor: (map['total_minor'] as num?)?.toInt() ?? 0,
    notes: (map['notes'] as String?) ?? '',
    receivedAt: map['received_at'] != null
        ? DateTime.tryParse(map['received_at'] as String)
        : null,
    receivedBy: map['received_by'] as String?,
    receivedByName: receiverName ?? (map['received_by_name'] as String?),
    createdBy: map['created_by'] as String?,
    items: items,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'purchase_number': purchaseNumber,
    'supplier_id': supplierId,
    'status': status,
    'purchase_date': purchaseDate.toIso8601String(),
    'expected_delivery_date': expectedDeliveryDate?.toIso8601String(),
    'subtotal_minor': subtotalMinor,
    'tax_minor': taxMinor,
    'additional_charges_minor': additionalChargesMinor,
    'total_minor': totalMinor,
    'notes': notes,
    'received_at': receivedAt?.toIso8601String(),
    'received_by': receivedBy,
  };
}
