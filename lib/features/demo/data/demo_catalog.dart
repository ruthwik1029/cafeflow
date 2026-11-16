import '../../menu/domain/catalog.dart';

// Fictional, in-memory visual development fixtures. No Supabase writes.
final demoCatalog = CatalogSnapshot(
  categories: const [
    MenuCategory(id: 'coffee', name: 'Coffee bar'),
    MenuCategory(id: 'bakery', name: 'Freshly baked'),
    MenuCategory(id: 'brunch', name: 'Brunch & bites'),
  ],
  products: const [
    MenuProduct(
      id: 'latte',
      categoryId: 'coffee',
      name: 'Velvet latte',
      priceMinor: 22000,
      description:
          'Double espresso, steamed milk, and a beautifully soft finish.',
      image: 'assets/images/coffee.jpg',
      featured: true,
    ),
    MenuProduct(
      id: 'espresso',
      categoryId: 'coffee',
      name: 'House espresso',
      priceMinor: 14000,
      description: 'Our signature roast. Chocolate notes, a little citrus, a long finish.',
      image: 'assets/images/coffee.jpg',
    ),
    MenuProduct(
      id: 'cold-brew',
      categoryId: 'coffee',
      name: 'Slow cold brew',
      priceMinor: 24000,
      description: 'Steeped overnight for a crisp, gently sweet cup.',
      image: 'assets/images/coffee.jpg',
      featured: true,
    ),
    MenuProduct(
      id: 'croissant',
      categoryId: 'bakery',
      name: 'Butter croissant',
      priceMinor: 18000,
      description: 'Golden layers, cultured butter, baked fresh each morning.',
      image: 'assets/images/pastry.jpg',
      featured: true,
    ),
    MenuProduct(
      id: 'almond',
      categoryId: 'bakery',
      name: 'Almond morning bun',
      priceMinor: 21000,
      description: 'A tender pastry with toasted almonds and vanilla.',
      image: 'assets/images/pastry.jpg',
      available: false,
    ),
    MenuProduct(
      id: 'bowl',
      categoryId: 'brunch',
      name: 'Garden grain bowl',
      priceMinor: 34000,
      description:
          'Seasonal greens, warm grains, roasted vegetables, lemon dressing.',
      image: 'assets/images/bowl.jpg',
      featured: true,
    ),
    MenuProduct(
      id: 'toast',
      categoryId: 'brunch',
      name: 'Sourdough melt',
      priceMinor: 32000,
      description:
          'Toasted sourdough, melted cheese, tomatoes, and fresh basil.',
      image: 'assets/images/sandwich.jpg',
    ),
  ],
);
