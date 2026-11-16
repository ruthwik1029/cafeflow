import 'package:cafeflow/core/config/app_config.dart';
import 'package:cafeflow/core/database/database_gateway.dart';
import 'package:cafeflow/core/errors/app_failure.dart';
import 'package:cafeflow/core/services/cafe_realtime_service.dart';
import 'package:cafeflow/core/services/realtime_gateway.dart';
import 'package:cafeflow/features/menu/data/supabase_menu_repository.dart';
import 'package:cafeflow/features/orders/data/supabase_order_repository.dart';
import 'package:cafeflow/features/orders/domain/cafe_order.dart';
import 'package:flutter_test/flutter_test.dart';

class MockDatabaseGateway implements DatabaseGateway {
  MockDatabaseGateway(this.responses);
  final Map<String, List<Map<String, dynamic>>> responses;

  @override
  Future<List<Map<String, dynamic>>> readRows(
    String relation, {
    Map<String, Object> equals = const {},
    int limit = 100,
  }) async {
    return responses[relation] ?? [];
  }
}

class MockChangefeedTransport implements ChangefeedTransport {
  int openCount = 0;
  ChangefeedSpec? lastSpec;

  @override
  CloseSubscription open(
    ChangefeedSpec spec,
    void Function(RealtimeSignal) onSignal,
    void Function(AppFailure) onError,
  ) {
    openCount++;
    lastSpec = spec;
    return () async {};
  }
}

void main() {
  group('Phase 03 AppConfig & Validation', () {
    test('accepts live Supabase project credentials', () {
      const config = AppConfig(
        environment: 'development',
        supabaseUrl: 'https://ierqwjxypkyehrhcrkbl.supabase.co',
        publishableKey: 'sb_publishable_n6Hxo6rCVc0g8LjSI4125w_Zs351KIC',
        demoMode: false,
      );

      expect(config.validate(), isNull);
      expect(config.hasBackendValues, isTrue);
      expect(config.allowsDemo, isFalse);
    });

    test('rejects malicious or invalid publishable keys', () {
      const badKeyConfig = AppConfig(
        environment: 'development',
        supabaseUrl: 'https://ierqwjxypkyehrhcrkbl.supabase.co',
        publishableKey: 'eyJh...service_role_secret',
      );

      expect(
        badKeyConfig.validate(),
        contains('Supply a Supabase publishable key'),
      );
    });
  });

  group('Phase 03 SupabaseMenuRepository', () {
    test('fetches available items and maps to domain model', () async {
      final mockGateway = MockDatabaseGateway({
        'menu_items': [
          {
            'id': 'item-1',
            'name': 'Cold Brew Reserve',
            'is_available': true,
            'is_archived': false,
          },
          {
            'id': 'item-2',
            'name': 'Velvet Latte',
            'is_available': true,
            'is_archived': false,
          },
        ],
      });

      final repo = SupabaseMenuRepository(gateway: mockGateway);
      final items = await repo.listAvailable();

      expect(items.length, 2);
      expect(items.first.name, 'Cold Brew Reserve');
      expect(items.first.available, isTrue);
    });

    test(
      'fetches full catalog snapshot with categories and products',
      () async {
        final mockGateway = MockDatabaseGateway({
          'menu_categories': [
            {'id': 'cat-1', 'name': 'Coffee', 'is_active': true},
          ],
          'menu_items': [
            {
              'id': 'item-1',
              'category_id': 'cat-1',
              'name': 'Velvet Latte',
              'price_minor': 24000,
              'description': 'Smooth latte',
              'image_url': 'https://example.com/latte.jpg',
              'is_available': true,
              'is_archived': false,
              'is_featured': true,
            },
          ],
        });

        final repo = SupabaseMenuRepository(gateway: mockGateway);
        final snapshot = await repo.fetchCatalog();

        expect(snapshot.isDemo, isFalse);
        expect(snapshot.categories.length, 1);
        expect(snapshot.products.length, 1);
        expect(snapshot.products.first.name, 'Velvet Latte');
        expect(snapshot.products.first.priceMinor, 24000);
        expect(snapshot.products.first.featured, isTrue);
      },
    );
  });

  group('Phase 03 SupabaseOrderRepository', () {
    test('lists active order references', () async {
      final mockGateway = MockDatabaseGateway({
        'orders': [
          {'id': 'ord-1', 'order_number': 'ORD-101'},
          {'id': 'ord-2', 'order_number': 'ORD-102'},
        ],
      });

      final repo = SupabaseOrderRepository(gateway: mockGateway);
      final orders = await repo.listActive();

      expect(orders.length, 2);
      expect(orders.first.displayNumber, 'ORD-101');
    });

    test('fetches full CafeOrder objects with line items and status', () async {
      final mockGateway = MockDatabaseGateway({
        'orders': [
          {
            'id': 'ord-101',
            'order_number': 'ORD-101',
            'created_at': '2026-11-14T10:00:00Z',
            'status': 'PREPARING',
            'table_name': 'Table 04',
            'special_instructions': 'Extra hot',
            'tax_minor': 1200,
            'discount_minor': 0,
          },
        ],
        'order_items': [
          {
            'id': 'item-line-1',
            'order_id': 'ord-101',
            'menu_item_id': 'menu-item-1',
            'item_name': 'Golden Croissant',
            'unit_price_minor': 21000,
            'quantity': 2,
          },
        ],
      });

      final repo = SupabaseOrderRepository(gateway: mockGateway);
      final orders = await repo.fetchOrders();

      expect(orders.length, 1);
      final order = orders.first;
      expect(order.number, 'ORD-101');
      expect(order.status, OrderStatus.preparing);
      expect(order.table, 'Table 04');
      expect(order.lines.length, 1);
      expect(order.lines.first.name, 'Golden Croissant');
      expect(order.lines.first.quantity, 2);
      expect(order.subtotalMinor, 42000);
      expect(order.totalMinor, 43200); // 42000 + 1200 tax
    });
  });

  group('Phase 03 CafeRealtimeService', () {
    test('sets up table channels without UI subscription leak', () {
      final transport = MockChangefeedTransport();
      final gateway = RealtimeGateway(transport);
      final service = CafeRealtimeService(gateway);

      final menuStream = service.watchMenu();
      final sub = menuStream.listen((_) {});

      expect(transport.openCount, 1);
      expect(transport.lastSpec?.table, 'menu_items');

      sub.cancel();
    });
  });
}
