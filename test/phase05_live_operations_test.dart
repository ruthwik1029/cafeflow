import 'dart:typed_data';

import 'package:cafeflow/core/database/database_gateway.dart';
import 'package:cafeflow/core/errors/app_failure.dart';
import 'package:cafeflow/core/services/cafe_realtime_service.dart';
import 'package:cafeflow/core/services/realtime_gateway.dart';
import 'package:cafeflow/features/customers/data/supabase_customers_repository.dart';
import 'package:cafeflow/features/inventory/data/supabase_inventory_repository.dart';
import 'package:cafeflow/features/menu/data/supabase_menu_repository.dart';
import 'package:cafeflow/features/orders/data/supabase_order_repository.dart';
import 'package:cafeflow/features/orders/domain/cafe_order.dart';
import 'package:cafeflow/features/tables/data/supabase_tables_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDatabaseGateway implements DatabaseGateway {
  const FakeDatabaseGateway();

  @override
  Future<List<Map<String, dynamic>>> readRows(
    String relation, {
    Map<String, Object> equals = const {},
    int limit = 100,
  }) async {
    return [];
  }
}

class FakeChangefeedTransport implements ChangefeedTransport {
  const FakeChangefeedTransport();

  @override
  CloseSubscription open(
    ChangefeedSpec spec,
    void Function(RealtimeSignal) onSignal,
    void Function(AppFailure) onError,
  ) {
    onSignal(RealtimeSignal.subscribed);
    return () async {};
  }
}

void main() {
  const gateway = FakeDatabaseGateway();

  group('Phase 05 — Supabase Menu Management Repository', () {
    test(
      'uninitialized client throws AppFailure for all mutation methods',
      () async {
        final repo = SupabaseMenuRepository(gateway: gateway, client: null);

        expect(
          () => repo.createCategory(restaurantId: 'rest-1', name: 'Hot Drinks'),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.updateCategory(categoryId: 'cat-1', name: 'Cold Drinks'),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.createMenuItem(
            restaurantId: 'rest-1',
            categoryId: 'cat-1',
            name: 'Flat White',
            priceMinor: 22000,
          ),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.updateMenuItem(itemId: 'item-1', name: 'Updated Latte'),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.archiveMenuItem(itemId: 'item-1'),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.uploadMenuImage(
            imageBytes: Uint8List.fromList([1, 2, 3]),
            fileName: 'coffee.jpg',
          ),
          throwsA(isA<AppFailure>()),
        );
      },
    );

    test('validates category inputs and rejects blank names', () async {
      final repo = SupabaseMenuRepository(gateway: gateway, client: null);

      expect(
        () => repo.createCategory(restaurantId: 'rest-1', name: '   '),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('Category name cannot be empty'),
          ),
        ),
      );

      expect(
        () => repo.updateCategory(categoryId: 'cat-1', name: '   '),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('Category name cannot be empty'),
          ),
        ),
      );
    });

    test(
      'validates menu item inputs and rejects blank name or negative price',
      () async {
        final repo = SupabaseMenuRepository(gateway: gateway, client: null);

        expect(
          () => repo.createMenuItem(
            restaurantId: 'rest-1',
            categoryId: 'cat-1',
            name: '   ',
            priceMinor: 100,
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'message',
              contains('Product name cannot be empty'),
            ),
          ),
        );

        expect(
          () => repo.createMenuItem(
            restaurantId: 'rest-1',
            categoryId: 'cat-1',
            name: 'Affogato',
            priceMinor: -50,
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'message',
              contains('Price cannot be negative'),
            ),
          ),
        );

        expect(
          () => repo.updateMenuItem(itemId: 'item-1', name: '  '),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'message',
              contains('Product name cannot be empty'),
            ),
          ),
        );

        expect(
          () => repo.updateMenuItem(itemId: 'item-1', priceMinor: -1),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'message',
              contains('Price cannot be negative'),
            ),
          ),
        );
      },
    );
  });

  group('Phase 05 — Atomic Order Submission & Order Repository', () {
    test('uninitialized client throws AppFailure for order creation and status transition', () async {
      final repo = SupabaseOrderRepository(gateway: gateway, client: null);

      expect(
        () => repo.createOrder(
          restaurantId: 'rest-1',
          tableName: 'Table 1',
          items: [
            const OrderSubmissionItem(
              menuItemId: 'item-1',
              quantity: 2,
              notes: 'Oat milk',
            ),
          ],
        ),
        throwsA(isA<AppFailure>()),
      );

      expect(
        () => repo.updateStatus('ord-1', OrderStatus.preparing),
        throwsA(isA<AppFailure>()),
      );
    });

    test('createOrder rejects submission with zero items', () async {
      final repo = SupabaseOrderRepository(gateway: gateway, client: null);

      expect(
        () => repo.createOrder(
          restaurantId: 'rest-1',
          tableName: 'Table 1',
          items: const [],
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('Cannot create an order with no items'),
          ),
        ),
      );
    });

    test('OrderSubmissionItem model serializes accurately for create_order_with_items RPC', () {
      const item = OrderSubmissionItem(
        menuItemId: 'item-123',
        quantity: 3,
        notes: 'Extra hot',
      );

      final json = item.toJson();
      expect(json['menu_item_id'], 'item-123');
      expect(json['quantity'], 3);
      expect(json['notes'], 'Extra hot');
    });

    test('CreatedOrderResult maps properties correctly', () {
      const result = CreatedOrderResult(
        id: 'ord-999',
        orderNumber: 'ORD-2026-1044',
        subtotalMinor: 45000,
        discountMinor: 0,
        taxMinor: 2250,
        totalMinor: 47250,
      );

      expect(result.id, 'ord-999');
      expect(result.orderNumber, 'ORD-2026-1044');
      expect(result.subtotalMinor, 45000);
      expect(result.taxMinor, 2250);
      expect(result.totalMinor, 47250);
    });
  });

  group('Phase 05 — Supabase Inventory Repository & Calculations', () {
    test('InventoryRecord computes low stock alert when stock is at or below reorder level', () {
      const healthy = InventoryRecord(
        id: 'inv-1',
        restaurantId: 'rest-1',
        name: 'Whole Milk',
        unit: 'litres',
        currentStock: 25.0,
        reorderLevel: 10.0,
        costPerUnitMinor: 6500,
        categoryName: 'Dairy',
      );

      const low = InventoryRecord(
        id: 'inv-2',
        restaurantId: 'rest-1',
        name: 'Espresso Beans',
        unit: 'kg',
        currentStock: 4.5,
        reorderLevel: 5.0,
        costPerUnitMinor: 120000,
        categoryName: 'Coffee',
      );

      const zero = InventoryRecord(
        id: 'inv-3',
        restaurantId: 'rest-1',
        name: 'Vanilla Syrup',
        unit: 'bottles',
        currentStock: 0.0,
        reorderLevel: 2.0,
        costPerUnitMinor: 45000,
        categoryName: 'Syrups',
      );

      expect(healthy.isLow, isFalse);
      expect(low.isLow, isTrue);
      expect(zero.isLow, isTrue);
    });

    test(
      'uninitialized client throws AppFailure for inventory mutations',
      () async {
        final repo = SupabaseInventoryRepository(
          gateway: gateway,
          client: null,
        );

        expect(
          () => repo.adjustStock(
            restaurantId: 'rest-1',
            itemId: 'inv-1',
            movementType: 'PURCHASE',
            quantityChange: 10.0,
          ),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.createItem(
            restaurantId: 'rest-1',
            name: 'Sugar',
            unit: 'kg',
          ),
          throwsA(isA<AppFailure>()),
        );
      },
    );

    test('validates inventory item creation name', () async {
      final repo = SupabaseInventoryRepository(gateway: gateway, client: null);

      expect(
        () => repo.createItem(restaurantId: 'rest-1', name: '   ', unit: 'kg'),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('Item name cannot be empty'),
          ),
        ),
      );
    });
  });

  group('Phase 05 — Supabase Tables Repository & Domain Records', () {
    test('DiningTableRecord parses statuses correctly', () {
      const availableTable = DiningTableRecord(
        id: 'tbl-1',
        restaurantId: 'rest-1',
        tableNumber: 'T-01',
        capacity: 4,
        status: TableStatus.available,
      );

      const occupiedTable = DiningTableRecord(
        id: 'tbl-2',
        restaurantId: 'rest-1',
        tableNumber: 'T-02',
        capacity: 2,
        status: TableStatus.occupied,
      );

      const reservedTable = DiningTableRecord(
        id: 'tbl-3',
        restaurantId: 'rest-1',
        tableNumber: 'T-03',
        capacity: 6,
        status: TableStatus.reserved,
      );

      expect(availableTable.status, TableStatus.available);
      expect(occupiedTable.status, TableStatus.occupied);
      expect(reservedTable.status, TableStatus.reserved);
    });

    test(
      'uninitialized client throws AppFailure for table operations',
      () async {
        final repo = SupabaseTablesRepository(gateway: gateway, client: null);

        expect(
          () => repo.updateTableStatus(
            restaurantId: 'rest-1',
            tableId: 'tbl-1',
            status: TableStatus.occupied,
          ),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.createTable(
            restaurantId: 'rest-1',
            tableNumber: 'T-04',
            capacity: 4,
          ),
          throwsA(isA<AppFailure>()),
        );
      },
    );

    test('validates table creation parameters', () async {
      final repo = SupabaseTablesRepository(gateway: gateway, client: null);

      expect(
        () => repo.createTable(
          restaurantId: 'rest-1',
          tableNumber: '   ',
          capacity: 4,
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('Table number cannot be empty'),
          ),
        ),
      );

      expect(
        () => repo.createTable(
          restaurantId: 'rest-1',
          tableNumber: 'T-05',
          capacity: 0,
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('Capacity must be greater than zero'),
          ),
        ),
      );

      expect(
        () => repo.createTable(
          restaurantId: 'rest-1',
          tableNumber: 'T-06',
          capacity: -2,
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('Capacity must be greater than zero'),
          ),
        ),
      );
    });
  });

  group('Phase 05 — Supabase Customers Repository', () {
    test('CustomerRecord model instantiates correctly', () {
      final customer = CustomerRecord(
        id: 'cust-1',
        restaurantId: 'rest-1',
        name: 'Arjun Verma',
        phone: '+919876543210',
        email: 'arjun@example.com',
        favoriteItem: 'Cappuccino',
        visitsCount: 14,
        totalSpendMinor: 420000,
        lastVisitedAt: DateTime(2026, 11, 14),
      );

      expect(customer.name, 'Arjun Verma');
      expect(customer.phone, '+919876543210');
      expect(customer.visitsCount, 14);
      expect(customer.totalSpendMinor, 420000);
      expect(customer.lastVisitedAt, isNotNull);
    });

    test(
      'uninitialized client throws AppFailure for customer creation',
      () async {
        final repo = SupabaseCustomersRepository(
          gateway: gateway,
          client: null,
        );

        expect(
          () => repo.createCustomer(restaurantId: 'rest-1', name: 'Jane Doe'),
          throwsA(isA<AppFailure>()),
        );
      },
    );

    test('validates customer name cannot be blank', () async {
      final repo = SupabaseCustomersRepository(gateway: gateway, client: null);

      expect(
        () => repo.createCustomer(restaurantId: 'rest-1', name: '   '),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('Customer name cannot be empty'),
          ),
        ),
      );
    });
  });

  group('Phase 05 — Realtime Service Stream Lifecycle', () {
    test(
      'CafeRealtimeService creates scoped streams and delegates to gateway',
      () async {
        const transport = FakeChangefeedTransport();
        const gateway = RealtimeGateway(transport);
        const service = CafeRealtimeService(gateway);

        final menuStream = service.watchMenu(restaurantId: 'rest-abc');
        final catStream = service.watchCategories(restaurantId: 'rest-abc');
        final orderStream = service.watchOrders(restaurantId: 'rest-abc');
        final tblStream = service.watchDiningTables(restaurantId: 'rest-abc');
        final invStream = service.watchInventory(restaurantId: 'rest-abc');
        final custStream = service.watchCustomers(restaurantId: 'rest-abc');

        expect(menuStream, isA<Stream<RealtimeSignal>>());
        expect(catStream, isA<Stream<RealtimeSignal>>());
        expect(orderStream, isA<Stream<RealtimeSignal>>());
        expect(tblStream, isA<Stream<RealtimeSignal>>());
        expect(invStream, isA<Stream<RealtimeSignal>>());
        expect(custStream, isA<Stream<RealtimeSignal>>());

        // Verify signals emit properly
        final firstSignal = await menuStream.first;
        expect(firstSignal, RealtimeSignal.subscribed);
      },
    );
  });
}
