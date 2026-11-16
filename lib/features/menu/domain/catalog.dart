class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.name,
    this.active = true,
  });
  final String id;
  final String name;
  final bool active;
}

class MenuProduct {
  const MenuProduct({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.priceMinor,
    this.description = '',
    this.image = '',
    this.available = true,
    this.archived = false,
    this.featured = false,
  });
  final String id;
  final String categoryId;
  final String name;
  final int priceMinor;
  final String description;
  final String image;
  final bool available;
  final bool archived;
  final bool featured;
  MenuProduct copyWith({
    String? categoryId,
    String? name,
    int? priceMinor,
    String? description,
    String? image,
    bool? available,
    bool? archived,
    bool? featured,
  }) => MenuProduct(
    id: id,
    categoryId: categoryId ?? this.categoryId,
    name: name ?? this.name,
    priceMinor: priceMinor ?? this.priceMinor,
    description: description ?? this.description,
    image: image ?? this.image,
    available: available ?? this.available,
    archived: archived ?? this.archived,
    featured: featured ?? this.featured,
  );
}

class CatalogSnapshot {
  CatalogSnapshot({
    required List<MenuCategory> categories,
    required List<MenuProduct> products,
    this.isDemo = true,
  }) : categories = List.unmodifiable(categories),
       products = List.unmodifiable(products);
  final List<MenuCategory> categories;
  final List<MenuProduct> products;
  final bool isDemo;
  List<MenuProduct> get visibleProducts => products
      .where(
        (p) =>
            !p.archived &&
            categories.any((c) => c.id == p.categoryId && c.active),
      )
      .toList();
}

String money(int minor) => '₹${(minor / 100).toStringAsFixed(2)}';

/// Decimal input is parsed as minor units, without floating-point arithmetic.
int? parseMoney(String value) {
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(value.trim())) return null;
  final parts = value.trim().split('.');
  return int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
}
