import '../../orders/domain/cafe_order.dart';
import '../../tables/domain/floor_models.dart';

export '../../tables/domain/floor_models.dart' show TableStatus;

class DemoDiningTable {
  const DemoDiningTable({
    required this.id,
    required this.name,
    required this.capacity,
    required this.status,
    this.currentOrderNumber,
  });

  final String id;
  final String name;
  final int capacity;
  final TableStatus status;
  final String? currentOrderNumber;

  DemoDiningTable copyWith({TableStatus? status, String? currentOrderNumber}) =>
      DemoDiningTable(
        id: id,
        name: name,
        capacity: capacity,
        status: status ?? this.status,
        currentOrderNumber: currentOrderNumber ?? this.currentOrderNumber,
      );
}

class DemoCustomer {
  const DemoCustomer({
    required this.id,
    required this.name,
    required this.phone,
    required this.visits,
    required this.favoriteItem,
    required this.totalSpendMinor,
  });

  final String id;
  final String name;
  final String phone;
  final int visits;
  final String favoriteItem;
  final int totalSpendMinor;
}

class DemoInventoryItem {
  const DemoInventoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.minimum,
    required this.unit,
  });

  final String id;
  final String name;
  final String category;
  final double quantity;
  final double minimum;
  final String unit;

  bool get isLow => quantity <= minimum;

  DemoInventoryItem copyWith({double? quantity}) => DemoInventoryItem(
    id: id,
    name: name,
    category: category,
    quantity: quantity ?? this.quantity,
    minimum: minimum,
    unit: unit,
  );
}

class DemoStaffMember {
  const DemoStaffMember({
    required this.id,
    required this.name,
    required this.role,
    required this.shift,
    required this.active,
  });

  final String id;
  final String name;
  final String role;
  final String shift;
  final bool active;
}

final demoOrders = [
  CafeOrder(
    id: 'demo-1042',
    number: 'CF-1042',
    createdAt: DateTime(2026, 11, 14, 10, 42),
    table: 'Table 04',
    instructions: 'Oat milk for the latte. Dressing on the side.',
    lines: const [
      OrderLine(
        productId: 'latte',
        name: 'Velvet latte',
        unitMinor: 22000,
        quantity: 2,
      ),
      OrderLine(
        productId: 'bowl',
        name: 'Garden grain bowl',
        unitMinor: 34000,
        quantity: 1,
      ),
    ],
    taxMinor: 3900,
  ),
  CafeOrder(
    id: 'demo-1041',
    number: 'CF-1041',
    createdAt: DateTime(2026, 11, 14, 10, 38),
    table: 'Table 02',
    status: OrderStatus.preparing,
    lines: const [
      OrderLine(
        productId: 'toast',
        name: 'Sourdough melt',
        unitMinor: 32000,
        quantity: 2,
      ),
    ],
    taxMinor: 3200,
  ),
  CafeOrder(
    id: 'demo-1040',
    number: 'CF-1040',
    createdAt: DateTime(2026, 11, 14, 10, 32),
    status: OrderStatus.ready,
    lines: const [
      OrderLine(
        productId: 'croissant',
        name: 'Butter croissant',
        unitMinor: 18000,
        quantity: 3,
      ),
    ],
    taxMinor: 2700,
  ),
  CafeOrder(
    id: 'demo-1039',
    number: 'CF-1039',
    createdAt: DateTime(2026, 11, 14, 10, 15),
    status: OrderStatus.completed,
    lines: const [
      OrderLine(
        productId: 'latte',
        name: 'Velvet latte',
        unitMinor: 22000,
        quantity: 4,
      ),
    ],
    taxMinor: 4400,
  ),
  CafeOrder(
    id: 'demo-1038',
    number: 'CF-1038',
    createdAt: DateTime(2026, 11, 14, 9, 52),
    status: OrderStatus.completed,
    lines: const [
      OrderLine(
        productId: 'bowl',
        name: 'Garden grain bowl',
        unitMinor: 34000,
        quantity: 3,
      ),
    ],
    taxMinor: 5100,
  ),
];

const demoInventory = [
  DemoInventoryItem(
    id: 'inv-1',
    name: 'House espresso beans',
    category: 'Coffee',
    quantity: 2.4,
    minimum: 5.0,
    unit: 'kg',
  ),
  DemoInventoryItem(
    id: 'inv-2',
    name: 'Oat milk',
    category: 'Dairy & Milks',
    quantity: 3.0,
    minimum: 6.0,
    unit: 'L',
  ),
  DemoInventoryItem(
    id: 'inv-3',
    name: 'Cultured butter',
    category: 'Bakery',
    quantity: 8.0,
    minimum: 3.0,
    unit: 'kg',
  ),
  DemoInventoryItem(
    id: 'inv-4',
    name: 'Sourdough loaves',
    category: 'Bakery',
    quantity: 12.0,
    minimum: 5.0,
    unit: 'loaves',
  ),
  DemoInventoryItem(
    id: 'inv-5',
    name: 'Organic whole milk',
    category: 'Dairy & Milks',
    quantity: 14.0,
    minimum: 10.0,
    unit: 'L',
  ),
  DemoInventoryItem(
    id: 'inv-6',
    name: 'Madagascar vanilla beans',
    category: 'Pantry',
    quantity: 0.8,
    minimum: 1.0,
    unit: 'kg',
  ),
];

const demoStaff = [
  DemoStaffMember(
    id: 'staff-1',
    name: 'Aanya Rao',
    role: 'Manager',
    shift: '08:00–16:00',
    active: true,
  ),
  DemoStaffMember(
    id: 'staff-2',
    name: 'Kabir Shah',
    role: 'Cashier',
    shift: '09:00–17:00',
    active: true,
  ),
  DemoStaffMember(
    id: 'staff-3',
    name: 'Mira Sen',
    role: 'Kitchen',
    shift: '08:00–16:00',
    active: true,
  ),
  DemoStaffMember(
    id: 'staff-4',
    name: 'Dev Iyer',
    role: 'Staff',
    shift: '10:00–18:00',
    active: true,
  ),
  DemoStaffMember(
    id: 'staff-5',
    name: 'Priya Sharma',
    role: 'Barista',
    shift: '07:30–15:30',
    active: false,
  ),
];

const demoTables = [
  DemoDiningTable(
    id: 't-1',
    name: 'Table 01',
    capacity: 2,
    status: TableStatus.available,
  ),
  DemoDiningTable(
    id: 't-2',
    name: 'Table 02',
    capacity: 4,
    status: TableStatus.occupied,
    currentOrderNumber: 'CF-1041',
  ),
  DemoDiningTable(
    id: 't-3',
    name: 'Table 03',
    capacity: 2,
    status: TableStatus.available,
  ),
  DemoDiningTable(
    id: 't-4',
    name: 'Table 04',
    capacity: 6,
    status: TableStatus.occupied,
    currentOrderNumber: 'CF-1042',
  ),
  DemoDiningTable(
    id: 't-5',
    name: 'Table 05',
    capacity: 4,
    status: TableStatus.reserved,
  ),
  DemoDiningTable(
    id: 't-6',
    name: 'Table 06',
    capacity: 2,
    status: TableStatus.available,
  ),
  DemoDiningTable(
    id: 't-7',
    name: 'Table 07',
    capacity: 4,
    status: TableStatus.available,
  ),
  DemoDiningTable(
    id: 't-8',
    name: 'Table 08',
    capacity: 8,
    status: TableStatus.available,
  ),
];

const demoCustomers = [
  DemoCustomer(
    id: 'c-1',
    name: 'Rohan Mehra',
    phone: '+91 98201 44321',
    visits: 24,
    favoriteItem: 'Velvet latte',
    totalSpendMinor: 1248000,
  ),
  DemoCustomer(
    id: 'c-2',
    name: 'Ananya Deshmukh',
    phone: '+91 97110 88290',
    visits: 18,
    favoriteItem: 'Butter croissant',
    totalSpendMinor: 890000,
  ),
  DemoCustomer(
    id: 'c-3',
    name: 'Vikram Sethi',
    phone: '+91 99302 11984',
    visits: 12,
    favoriteItem: 'Garden grain bowl',
    totalSpendMinor: 756000,
  ),
  DemoCustomer(
    id: 'c-4',
    name: 'Tara Varma',
    phone: '+91 98450 77123',
    visits: 31,
    favoriteItem: 'House espresso',
    totalSpendMinor: 1680000,
  ),
  DemoCustomer(
    id: 'c-5',
    name: 'Karan Kapoor',
    phone: '+91 99203 55678',
    visits: 9,
    favoriteItem: 'Sourdough melt',
    totalSpendMinor: 480000,
  ),
];
