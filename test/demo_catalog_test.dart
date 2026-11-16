import 'package:cafeflow/features/demo/application/demo_catalog_controller.dart';
import 'package:cafeflow/features/menu/domain/catalog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DemoCatalogController Unit Tests', () {
    test('initial state loads demo categories and products', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final catalog = container.read(demoCatalogProvider);
      expect(catalog.categories, isNotEmpty);
      expect(catalog.products, isNotEmpty);
      expect(catalog.isDemo, isTrue);
    });

    test('saving product adds or updates item in catalog', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(demoCatalogProvider.notifier);
      final newId = controller.newId();
      final product = MenuProduct(
        id: newId,
        categoryId: 'coffee',
        name: 'Aeropress Special',
        priceMinor: 26000,
        available: true,
      );

      controller.save(product);

      final updated = container.read(demoCatalogProvider);
      expect(updated.products.any((p) => p.id == newId), isTrue);
      final found = updated.products.firstWhere((p) => p.id == newId);
      expect(found.name, 'Aeropress Special');
      expect(found.priceMinor, 26000);
    });

    test('saving product with empty name or negative price throws', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(demoCatalogProvider.notifier);
      expect(
        () => controller.save(
          const MenuProduct(
            id: 'bad-1',
            categoryId: 'coffee',
            name: '',
            priceMinor: 10000,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => controller.save(
          const MenuProduct(
            id: 'bad-2',
            categoryId: 'coffee',
            name: 'Valid Name',
            priceMinor: -500,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('adding category creates unique category', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(demoCatalogProvider.notifier);
      controller.category('Signature Desserts');

      final updated = container.read(demoCatalogProvider);
      expect(
        updated.categories.any((c) => c.name == 'Signature Desserts'),
        isTrue,
      );

      // Duplicate category name throws
      expect(
        () => controller.category('Signature Desserts'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
