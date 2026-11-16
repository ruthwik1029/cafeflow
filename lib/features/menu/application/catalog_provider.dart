import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backend.dart';
import '../../../core/services/cafe_realtime_service.dart';
import '../../../core/storage/local_database.dart';
import '../../auth/application/auth_controller.dart';
import '../../demo/application/demo_catalog_controller.dart';
import '../data/supabase_menu_repository.dart';
import '../domain/catalog.dart';

final catalogProvider = FutureProvider<CatalogSnapshot>((ref) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(menuRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final localDb = ref.watch(localDatabaseProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (restaurantId != null) {
    if (backend.status == BackendStatus.initialized &&
        repo is SupabaseMenuRepository) {
      try {
        // Set up realtime invalidation for live menu updates
        final menuSub = repo
            .watchInvalidations(restaurantId: restaurantId)
            .listen((_) {
              ref.invalidateSelf();
            });
        ref.onDispose(menuSub.cancel);

        final realtimeService = ref.watch(cafeRealtimeServiceProvider);
        if (realtimeService != null) {
          final catSub = realtimeService
              .watchCategories(restaurantId: restaurantId)
              .listen((_) => ref.invalidateSelf());
          ref.onDispose(catSub.cancel);
        }

        final remoteSnapshot = await repo.fetchCatalog(
          restaurantId: restaurantId,
        );

        // Cache categories and products into local database for offline resilience
        for (final cat in remoteSnapshot.categories) {
          await localDb.put('menu_categories', cat.id, {
            'id': cat.id,
            'restaurant_id': restaurantId,
            'name': cat.name,
            'is_active': cat.active,
          });
        }
        for (final prod in remoteSnapshot.products) {
          await localDb.put('menu_items', prod.id, {
            'id': prod.id,
            'restaurant_id': restaurantId,
            'category_id': prod.categoryId,
            'name': prod.name,
            'price_minor': prod.priceMinor,
            'description': prod.description,
            'image': prod.image,
            'is_available': prod.available,
            'is_archived': prod.archived,
            'is_featured': prod.featured,
          });
        }

        return remoteSnapshot;
      } catch (_) {
        // Network dropped or Supabase offline -> check local database cache
      }
    }

    // Load from local database cache
    final catRows = await localDb.query(
      'menu_categories',
      where: {'restaurant_id': restaurantId},
    );
    final prodRows = await localDb.query(
      'menu_items',
      where: {'restaurant_id': restaurantId},
    );

    if (catRows.isNotEmpty && prodRows.isNotEmpty) {
      final cachedCategories = catRows.map((r) {
        return MenuCategory(
          id: r['id'] as String,
          name: r['name'] as String,
          active: (r['is_active'] as bool?) ?? true,
        );
      }).toList();

      final cachedProducts = prodRows.map((r) {
        return MenuProduct(
          id: r['id'] as String,
          categoryId: (r['category_id'] as String?) ?? '',
          name: r['name'] as String,
          priceMinor: (r['price_minor'] as num).toInt(),
          description: (r['description'] as String?) ?? '',
          image: (r['image'] as String?) ?? '',
          available: (r['is_available'] as bool?) ?? true,
          archived: (r['is_archived'] as bool?) ?? false,
          featured: (r['is_featured'] as bool?) ?? false,
        );
      }).toList();

      return CatalogSnapshot(
        categories: cachedCategories,
        products: cachedProducts,
        isDemo: false,
      );
    }
  }

  return ref.watch(demoCatalogProvider);
});
