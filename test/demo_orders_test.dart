import 'package:cafeflow/features/demo/application/demo_orders_controller.dart';
import 'package:cafeflow/features/orders/domain/cafe_order.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DemoOrdersController Unit Tests', () {
    test('initial state loads demo orders', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final orders = container.read(demoOrdersProvider);
      expect(orders, isNotEmpty);
      expect(orders.any((o) => o.status == OrderStatus.preparing), isTrue);
    });

    test('add creates order and increments sequence', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(demoOrdersProvider.notifier);
      final newOrder = controller.add(
        lines: const [
          OrderLine(
            productId: 'latte',
            name: 'Velvet latte',
            unitMinor: 22000,
            quantity: 2,
          ),
        ],
        table: 'Table 03',
        instructions: 'Extra hot',
        taxMinor: 2200,
        discountMinor: 0,
      );

      expect(newOrder.table, 'Table 03');
      expect(newOrder.instructions, 'Extra hot');
      expect(newOrder.status, OrderStatus.newOrder);
      expect(newOrder.subtotalMinor, 44000);
      expect(newOrder.totalMinor, 46200);

      final state = container.read(demoOrdersProvider);
      expect(state.first.id, newOrder.id);
    });

    test('add with empty lines throws StateError', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(demoOrdersProvider.notifier);
      expect(
        () => controller.add(
          lines: const [],
          table: 'Takeaway',
          instructions: '',
          taxMinor: 0,
          discountMinor: 0,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('advance transitions order from newOrder to preparing to ready', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(demoOrdersProvider.notifier);
      final order = controller.add(
        lines: const [
          OrderLine(
            productId: 'latte',
            name: 'Velvet latte',
            unitMinor: 22000,
            quantity: 1,
          ),
        ],
        table: 'Table 01',
        instructions: '',
        taxMinor: 1100,
        discountMinor: 0,
      );

      expect(order.status, OrderStatus.newOrder);

      controller.advance(order.id);
      var state = container.read(demoOrdersProvider);
      var updated = state.firstWhere((o) => o.id == order.id);
      expect(updated.status, OrderStatus.preparing);

      controller.advance(order.id);
      state = container.read(demoOrdersProvider);
      updated = state.firstWhere((o) => o.id == order.id);
      expect(updated.status, OrderStatus.ready);

      // Advancing from ready throws StateError
      expect(() => controller.advance(order.id), throwsA(isA<StateError>()));
    });
  });
}
