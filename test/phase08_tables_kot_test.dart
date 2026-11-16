import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cafeflow/core/database/database_gateway.dart';
import 'package:cafeflow/core/storage/local_database.dart';
import 'package:cafeflow/core/sync/cafe_sync_service.dart';
import 'package:cafeflow/core/sync/sync_queue.dart';
import 'package:cafeflow/features/kitchen/data/supabase_kitchen_repository.dart';
import 'package:cafeflow/features/orders/domain/cafe_order.dart';
import 'package:cafeflow/features/orders/presentation/orders_page.dart';
import 'package:cafeflow/features/tables/data/supabase_tables_repository.dart';

class MockDatabaseGateway implements DatabaseGateway {
  final Map<String, List<Map<String, dynamic>>> tables = {};

  @override
  Future<List<Map<String, dynamic>>> readRows(
    String relation, {
    Map<String, Object> equals = const {},
    int limit = 100,
  }) async {
    final rows = tables[relation] ?? [];
    return rows
        .where((row) {
          for (final entry in equals.entries) {
            if (row[entry.key] != entry.value) return false;
          }
          return true;
        })
        .take(limit)
        .toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 08: Floor Sections & Dining Tables Domain Model Tests', () {
    test('FloorSection serializes and deserializes with sort order', () {
      final section = FloorSection(
        id: 'sec-1',
        restaurantId: 'rest-1',
        name: 'Patio Terrace',
        description: 'Outdoor seating with heater',
        sortOrder: 2,
        isActive: true,
      );

      final map = section.toMap();
      expect(map['id'], 'sec-1');
      expect(map['restaurant_id'], 'rest-1');
      expect(map['name'], 'Patio Terrace');
      expect(map['sort_order'], 2);
      expect(map['is_active'], true);

      final fromMap = FloorSection.fromMap(map);
      expect(fromMap.id, section.id);
      expect(fromMap.name, section.name);
      expect(fromMap.sortOrder, 2);
    });

    test(
      'TableStatus supports all 6 operational states with correct DB values',
      () {
        expect(TableStatus.available.dbValue, 'AVAILABLE');
        expect(TableStatus.occupied.dbValue, 'OCCUPIED');
        expect(TableStatus.reserved.dbValue, 'RESERVED');
        expect(TableStatus.billRequested.dbValue, 'BILL_REQUESTED');
        expect(TableStatus.cleaning.dbValue, 'CLEANING');
        expect(TableStatus.outOfService.dbValue, 'OUT_OF_SERVICE');

        expect(TableStatusX.fromDb('AVAILABLE'), TableStatus.available);
        expect(TableStatusX.fromDb('OCCUPIED'), TableStatus.occupied);
        expect(TableStatusX.fromDb('RESERVED'), TableStatus.reserved);
        expect(
          TableStatusX.fromDb('BILL_REQUESTED'),
          TableStatus.billRequested,
        );
        expect(TableStatusX.fromDb('CLEANING'), TableStatus.cleaning);
        expect(TableStatusX.fromDb('OUT_OF_SERVICE'), TableStatus.outOfService);
        expect(TableStatusX.fromDb('UNKNOWN_FALLBACK'), TableStatus.available);
      },
    );

    test(
      'DiningTableRecord correctly reports section and session references',
      () {
        final now = DateTime.now().subtract(const Duration(minutes: 25));
        final table = DiningTableRecord(
          id: 'tbl-1',
          restaurantId: 'rest-1',
          sectionId: 'sec-1',
          sectionName: 'Main Dining',
          tableNumber: 'Table 04',
          capacity: 6,
          status: TableStatus.occupied,
          activeSessionId: 'sess-101',
          currentOrderId: 'ord-500',
          currentOrderNumber: 'CF-1005',
          occupiedSince: now,
        );

        expect(table.capacity, 6);
        expect(table.status, TableStatus.occupied);
        expect(table.sectionName, 'Main Dining');
        expect(table.activeSessionId, 'sess-101');
        expect(table.currentOrderNumber, 'CF-1005');

        final map = table.toMap();
        expect(map['table_number'], 'Table 04');
        expect(map['status'], 'OCCUPIED');
        expect(map['capacity'], 6);
      },
    );

    test('TableSession model tracks status, opening time, and guest count', () {
      final openedAt = DateTime.now().subtract(const Duration(minutes: 40));
      final session = TableSession(
        id: 'sess-1',
        restaurantId: 'rest-1',
        tableId: 'tbl-1',
        tableNumber: 'Table 04',
        status: TableSessionStatus.active,
        openedBy: 'usr-1',
        guestCount: 4,
        currentOrderId: 'ord-500',
        notes: 'Birthday celebration',
        openedAt: openedAt,
      );

      expect(session.status, TableSessionStatus.active);
      expect(session.guestCount, 4);
      expect(session.duration.inMinutes, greaterThanOrEqualTo(40));
      expect(session.formattedDuration, isNotEmpty);
      expect(session.notes, 'Birthday celebration');

      final closed = session.copyWith(
        status: TableSessionStatus.closed,
        closedBy: 'usr-2',
        closedAt: DateTime.now(),
      );
      expect(closed.status, TableSessionStatus.closed);
      expect(closed.closedBy, 'usr-2');
    });
  });

  group('Phase 08: Kitchen Stations & KOT Models Tests', () {
    test('KitchenStation model validates code, name, and printer settings', () {
      const station = KitchenStation(
        id: 'st-bar',
        restaurantId: 'rest-1',
        name: 'Beverage Bar & Espresso',
        code: 'BAR',
        description: 'Coffee, teas, shakes, and mocktails',
        printerName: 'POS-PRINTER-BAR',
      );

      final map = station.toMap();
      expect(map['code'], 'BAR');
      expect(map['name'], 'Beverage Bar & Espresso');
      expect(map['printer_name'], 'POS-PRINTER-BAR');

      final reconstituted = KitchenStation.fromMap(map);
      expect(reconstituted.id, 'st-bar');
      expect(reconstituted.code, 'BAR');
    });

    test('KotStatus and KotItem model handle full fulfillment lifecycle and cancellation reason', () {
      final createdAt = DateTime.now();
      final item = KotItem(
        id: 'item-1',
        kotId: 'kot-101',
        orderItemId: 'ord-item-1',
        itemName: 'Velvet Latte',
        quantity: 2,
        selectedVariant: 'Oat Milk',
        selectedAddons: ['Extra Shot', 'Vanilla Syrup'],
        notes: 'Extra hot, no foam',
        status: KotStatus.newOrder,
        createdAt: createdAt,
      );

      expect(item.itemName, 'Velvet Latte');
      expect(item.quantity, 2);
      expect(item.selectedVariant, 'Oat Milk');
      expect(item.selectedAddons.length, 2);
      expect(item.status, KotStatus.newOrder);

      // Transition to PREPARING
      final preparingItem = item.copyWith(
        status: KotStatus.preparing,
        preparedAt: DateTime.now(),
      );
      expect(preparingItem.status, KotStatus.preparing);
      expect(preparingItem.preparedAt, isNotNull);

      // Transition to READY
      final readyItem = preparingItem.copyWith(status: KotStatus.ready);
      expect(readyItem.status, KotStatus.ready);

      // Transition to SERVED
      final servedItem = readyItem.copyWith(
        status: KotStatus.served,
        servedAt: DateTime.now(),
      );
      expect(servedItem.status, KotStatus.served);
      expect(servedItem.servedAt, isNotNull);

      // Transition to CANCELLED with mandatory reason
      final cancelledItem = item.copyWith(
        status: KotStatus.cancelled,
        cancelledAt: DateTime.now(),
        cancelReason: '86 - Out of oat milk',
      );
      expect(cancelledItem.status, KotStatus.cancelled);
      expect(cancelledItem.cancelReason, '86 - Out of oat milk');
    });

    test(
      'KitchenOrderTicket calculates elapsed duration and sequence formatting',
      () {
        final thirtyMinsAgo = DateTime.now().subtract(
          const Duration(minutes: 32),
        );
        final ticket = KitchenOrderTicket(
          id: 'kot-1',
          restaurantId: 'rest-1',
          orderId: 'ord-100',
          tableSessionId: 'sess-1',
          kotNumber: 'KOT-0042',
          sequenceNumber: 2,
          tableName: 'Table 03',
          stationName: 'Hot Kitchen & Grills',
          status: KotStatus.preparing,
          specialInstructions: 'Allergies: Nut allergy on guest 2',
          createdAt: thirtyMinsAgo,
          items: [
            KotItem(
              id: 'it-1',
              kotId: 'kot-1',
              itemName: 'Classic Sourdough Toast',
              quantity: 1,
              status: KotStatus.preparing,
              createdAt: thirtyMinsAgo,
            ),
          ],
        );

        expect(ticket.kotNumber, 'KOT-0042');
        expect(ticket.sequenceNumber, 2);
        expect(ticket.tableName, 'Table 03');
        expect(ticket.age.inMinutes, greaterThanOrEqualTo(32));
        expect(ticket.elapsedLabel, contains('m ago'));
        expect(ticket.items.length, 1);
      },
    );
  });

  group('Phase 08: Repositories Unit & Integration Logic Tests', () {
    test('SupabaseTablesRepository listSections returns sections sorted by sort_order', () async {
      final gateway = MockDatabaseGateway();
      gateway.tables['floor_sections'] = [
        {
          'id': 'sec-2',
          'restaurant_id': 'rest-1',
          'name': 'Patio',
          'sort_order': 2,
          'is_active': true,
        },
        {
          'id': 'sec-1',
          'restaurant_id': 'rest-1',
          'name': 'Main Dining',
          'sort_order': 1,
          'is_active': true,
        },
      ];

      final repo = SupabaseTablesRepository(gateway: gateway);
      final sections = await repo.listSections('rest-1');

      expect(sections.length, 2);
      expect(sections[0].name, 'Main Dining');
      expect(sections[1].name, 'Patio');
    });

    test('SupabaseKitchenRepository listKots attaches item records to matching tickets', () async {
      final gateway = MockDatabaseGateway();
      final nowStr = DateTime.now().toIso8601String();

      gateway.tables['kitchen_stations'] = [
        {
          'id': 'st-1',
          'restaurant_id': 'rest-1',
          'name': 'Hot Kitchen',
          'code': 'HOT',
          'is_active': true,
        },
      ];

      gateway.tables['kitchen_order_tickets'] = [
        {
          'id': 'kot-10',
          'restaurant_id': 'rest-1',
          'order_id': 'ord-1',
          'kot_number': 'KOT-0010',
          'sequence_number': 1,
          'table_name': 'Table 05',
          'station_id': 'st-1',
          'status': 'NEW',
          'special_instructions': 'Rush order',
          'created_at': nowStr,
        },
      ];

      gateway.tables['kot_items'] = [
        {
          'id': 'kit-1',
          'kot_id': 'kot-10',
          'item_name': 'Avocado Tartine',
          'quantity': 2,
          'status': 'NEW',
          'created_at': nowStr,
        },
        {
          'id': 'kit-2',
          'kot_id': 'kot-10',
          'item_name': 'Filter Coffee',
          'quantity': 1,
          'status': 'NEW',
          'created_at': nowStr,
        },
      ];

      final repo = SupabaseKitchenRepository(gateway: gateway);
      final tickets = await repo.listKots(restaurantId: 'rest-1');

      expect(tickets.length, 1);
      expect(tickets.first.kotNumber, 'KOT-0010');
      expect(tickets.first.stationName, 'Hot Kitchen');
      expect(tickets.first.items.length, 2);
      expect(tickets.first.items[0].itemName, 'Avocado Tartine');
      expect(tickets.first.items[1].itemName, 'Filter Coffee');
    });
  });

  group('Phase 08: Offline Persistence for Tables & KOTs Tests', () {
    test('CafeSyncService.saveOfflineOrder creates pending order and local KOT ticket with items', () async {
      final adapter = MemoryStorageAdapter();
      final localDb = CafeLocalDatabase(adapter: adapter);
      await localDb.initialize();
      final syncQueue = SyncQueue(localDb);
      final syncService = CafeSyncService(database: localDb, queue: syncQueue);

      final lines = [
        const OrderLine(
          productId: 'prod-coldbrew',
          name: 'Cold Brew Reserve',
          unitMinor: 25000,
          quantity: 2,
        ),
        const OrderLine(
          productId: 'prod-croissant',
          name: 'Croissant',
          unitMinor: 15000,
          quantity: 1,
        ),
      ];

      final orderId = await syncService.saveOfflineOrder(
        restaurantId: 'rest-offline-1',
        tableName: 'Table 07',
        lines: lines,
        tableSessionId: 'sess-offline-7',
        orderType: 'DINE_IN',
        specialInstructions: 'Window seat table',
      );

      expect(orderId, isNotEmpty);
      final savedOrder = await localDb.get('orders', orderId);
      expect(savedOrder, isNotNull);
      expect(savedOrder!['sync_status'], 'PENDING');
      expect(savedOrder['table_session_id'], 'sess-offline-7');
      expect(savedOrder['order_type'], 'DINE_IN');

      // Verify offline KOT was created in local database
      final localKots = await localDb.query('kitchen_order_tickets');
      expect(localKots.length, 1);
      expect(localKots.first['order_id'], orderId);
      expect(localKots.first['table_session_id'], 'sess-offline-7');
      expect(localKots.first['status'], 'NEW');

      // Verify offline KOT items were created in local database
      final localKotItems = await localDb.query('kot_items');
      expect(localKotItems.length, 2);
      expect(
        localKotItems.any((it) => it['item_name'] == 'Cold Brew Reserve'),
        isTrue,
      );
      expect(localKotItems.any((it) => it['item_name'] == 'Croissant'), isTrue);
    });
  });

  group('Phase 08: Kitchen Display Widget & Security Isolation Tests', () {
    testWidgets(
      'KotTicketCard renders ticket operational details and strictly isolates financial/payment info',
      (tester) async {
        final ticket = KitchenOrderTicket(
          id: 'kot-test-1',
          restaurantId: 'rest-1',
          orderId: 'ord-101',
          kotNumber: 'KOT-0088',
          sequenceNumber: 1,
          tableName: 'Table 08',
          stationName: 'Beverage Bar',
          status: KotStatus.newOrder,
          specialInstructions: 'Make it extra warm',
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          items: [
            KotItem(
              id: 'it-1',
              kotId: 'kot-test-1',
              itemName: 'House Cappuccino',
              quantity: 2,
              selectedVariant: 'Almond Milk',
              status: KotStatus.newOrder,
              createdAt: DateTime.now(),
            ),
          ],
        );

        bool advanceCalled = false;
        KotStatus? nextItemStatus;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: KotTicketCard(
                  ticket: ticket,
                  onAdvanceTicket: () => advanceCalled = true,
                  onUpdateItemStatus: (item, status) => nextItemStatus = status,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Operational info is visible
        expect(find.textContaining('KOT-0088 (#1)'), findsOneWidget);
        expect(find.text('Table 08'), findsOneWidget);
        expect(find.text('Beverage Bar'), findsOneWidget);
        expect(find.text('Make it extra warm'), findsOneWidget);
        expect(find.text('2 × House Cappuccino'), findsOneWidget);
        expect(find.text('Variant: Almond Milk'), findsOneWidget);
        expect(find.text('Start preparing ticket'), findsOneWidget);

        // Financial and payment information is strictly NOT rendered (Security isolation)
        expect(find.textContaining('₹'), findsNothing);
        expect(find.textContaining('Paid'), findsNothing);
        expect(find.textContaining('Settle'), findsNothing);
        expect(find.textContaining('Total'), findsNothing);

        // Advance ticket button triggers callback
        await tester.tap(find.text('Start preparing ticket'));
        await tester.pump();
        expect(advanceCalled, isTrue);

        // Item level button triggers callback
        await tester.tap(find.byTooltip('Start preparing'));
        await tester.pump();
        expect(nextItemStatus, KotStatus.preparing);
      },
    );

    testWidgets(
      'KotTicketCard displays delayed warning badge for tickets exceeding 15 minutes',
      (tester) async {
        final delayedTicket = KitchenOrderTicket(
          id: 'kot-delayed-1',
          restaurantId: 'rest-1',
          orderId: 'ord-202',
          kotNumber: 'KOT-0099',
          sequenceNumber: 1,
          tableName: 'Table 02',
          status: KotStatus.preparing,
          createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
          items: [
            KotItem(
              id: 'it-2',
              kotId: 'kot-delayed-1',
              itemName: 'Grilled Panini',
              quantity: 1,
              status: KotStatus.preparing,
              createdAt: DateTime.now(),
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: KotTicketCard(ticket: delayedTicket),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
        expect(
          find.text('Mark ticket ready'),
          findsNothing,
        ); // no onAdvance provided
      },
    );
  });
}
