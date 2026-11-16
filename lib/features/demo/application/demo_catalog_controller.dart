import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../menu/domain/catalog.dart';
import '../data/demo_catalog.dart';

final demoCatalogProvider =
    NotifierProvider<DemoCatalogController, CatalogSnapshot>(
      DemoCatalogController.new,
    );

class DemoCatalogController extends Notifier<CatalogSnapshot> {
  int _nextId = 0;
  @override
  CatalogSnapshot build() => demoCatalog;
  void save(MenuProduct item) {
    if (item.name.trim().isEmpty ||
        item.priceMinor < 0 ||
        !state.categories.any((c) => c.id == item.categoryId)) {
      throw ArgumentError(
        'A name, valid category and non-negative price are required.',
      );
    }
    state = CatalogSnapshot(
      categories: state.categories,
      products: [...state.products.where((p) => p.id != item.id), item],
    );
  }

  void reset() {
    state = demoCatalog;
    _nextId = 0;
  }

  String newId() => 'local-product-${_nextId++}';
  void category(String name, {String? id, bool active = true}) {
    final clean = name.trim();
    if (clean.isEmpty ||
        state.categories.any(
          (c) => c.id != id && c.name.toLowerCase() == clean.toLowerCase(),
        )) {
      throw ArgumentError('Use a unique category name.');
    }
    state = CatalogSnapshot(
      products: state.products,
      categories: [
        ...state.categories.where((c) => c.id != id),
        MenuCategory(
          id: id ?? 'local-category-${_nextId++}',
          name: clean,
          active: active,
        ),
      ],
    );
  }
}
