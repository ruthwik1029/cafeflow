import 'package:cafeflow/features/billing/application/cart_controller.dart';
import 'package:cafeflow/features/menu/domain/catalog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CartController Unit Tests', () {
    const sampleProduct = MenuProduct(
      id: 'test-latte',
      categoryId: 'coffee',
      name: 'Test Latte',
      priceMinor: 22000, // ₹220.00
      available: true,
    );

    const soldOutProduct = MenuProduct(
      id: 'test-cake',
      categoryId: 'bakery',
      name: 'Sold Out Cake',
      priceMinor: 15000,
      available: false,
    );

    test('initial state is empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(cartProvider('cashier'));
      expect(state.lines, isEmpty);
      expect(state.subtotalMinor, 0);
      expect(state.totalMinor, 0);
      expect(state.discountMinor, 0);
      expect(state.paymentMethod, 'Cash');
    });

    test('adding available product adds to lines and calculates tax', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(cartProvider('cashier').notifier);
      controller.add(sampleProduct);

      final state = container.read(cartProvider('cashier'));
      expect(state.lines.length, 1);
      expect(state.lines.first.productId, 'test-latte');
      expect(state.lines.first.quantity, 1);
      expect(state.subtotalMinor, 22000);
      // 5% tax on 22000 = (22000 * 500 + 5000) ~/ 10000 = 1100
      expect(state.taxMinor, 1100);
      expect(state.totalMinor, 23100);
    });

    test('adding unavailable product throws StateError', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(cartProvider('cashier').notifier);
      expect(() => controller.add(soldOutProduct), throwsA(isA<StateError>()));
    });

    test('incrementing existing product quantity increases count', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(cartProvider('cashier').notifier);
      controller.add(sampleProduct);
      controller.add(sampleProduct);

      final state = container.read(cartProvider('cashier'));
      expect(state.lines.length, 1);
      expect(state.lines.first.quantity, 2);
      expect(state.subtotalMinor, 44000);
      expect(state.totalMinor, 46200);
    });

    test('setting quantity to 0 removes line', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(cartProvider('cashier').notifier);
      controller.add(sampleProduct);
      controller.quantity('test-latte', 0);

      final state = container.read(cartProvider('cashier'));
      expect(state.lines, isEmpty);
      expect(state.totalMinor, 0);
    });

    test('discount clamps to subtotal and updates tax and total', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(cartProvider('cashier').notifier);
      controller.add(sampleProduct); // 22000
      controller.discount(2000); // ₹20.00 discount

      final state = container.read(cartProvider('cashier'));
      expect(state.subtotalMinor, 22000);
      expect(state.discountMinor, 2000);
      expect(state.taxableMinor, 20000);
      // 5% tax on 20000 = 1000
      expect(state.taxMinor, 1000);
      expect(state.totalMinor, 21000);
    });

    test('discount exceeding subtotal throws ArgumentError', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(cartProvider('cashier').notifier);
      controller.add(sampleProduct);

      expect(() => controller.discount(25000), throwsA(isA<ArgumentError>()));
    });

    test('validates supported payment methods', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(cartProvider('cashier').notifier);
      controller.payment('UPI');
      expect(container.read(cartProvider('cashier')).paymentMethod, 'UPI');

      controller.payment('Card');
      expect(container.read(cartProvider('cashier')).paymentMethod, 'Card');

      expect(
        () => controller.payment('Bitcoin'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('clear resets cart to empty state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(cartProvider('cashier').notifier);
      controller.add(sampleProduct);
      controller.discount(1000);
      controller.clear();

      final state = container.read(cartProvider('cashier'));
      expect(state.lines, isEmpty);
      expect(state.discountMinor, 0);
      expect(state.totalMinor, 0);
    });
  });
}
