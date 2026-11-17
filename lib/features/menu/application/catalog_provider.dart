import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/services/backend.dart';
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

  // 1. If Supabase backend is initialized, attempt live remote fetch
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

      if (restaurantId != null && repo.realtime != null) {
        final catSub = repo.realtime!
            .watchCategories(restaurantId: restaurantId)
            .listen((_) => ref.invalidateSelf());
        ref.onDispose(catSub.cancel);
      }

      final remoteSnapshot = await repo.fetchCatalog(
        restaurantId: restaurantId,
      );

      // Cache categories and products into local database for offline resilience
      if (restaurantId != null &&
          (remoteSnapshot.categories.isNotEmpty ||
              remoteSnapshot.products.isNotEmpty)) {
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
      }

      // Valid remote catalog (even if empty initially, isDemo is false)
      return remoteSnapshot;
    } catch (e) {
      // Network dropped -> check local database cache if authenticated
      if (restaurantId != null) {
        final catRows = await localDb.query(
          'menu_categories',
          where: {'restaurant_id': restaurantId},
        );
        final prodRows = await localDb.query(
          'menu_items',
          where: {'restaurant_id': restaurantId},
        );

        if (catRows.isNotEmpty || prodRows.isNotEmpty) {
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

      // If backend was initialized but fetch failed and no local cache exists
      throw AppFailure(
        e is AppFailure ? e.message : 'Unable to load menu from Supabase. Please check your connection.',
      );
    }
  }

  // 2. Load from local database cache if an authenticated tenant context exists
  if (restaurantId != null) {
    final catRows = await localDb.query(
      'menu_categories',
      where: {'restaurant_id': restaurantId},
    );
    final prodRows = await localDb.query(
      'menu_items',
      where: {'restaurant_id': restaurantId},
    );

    if (catRows.isNotEmpty || prodRows.isNotEmpty) {
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

  // 3. Fallback to demo catalog ONLY when demo mode is allowed in non-production
  if (backend.config.allowsDemo) {
    return ref.watch(demoCatalogProvider);
  }

  // In production with unconfigured or failed backend, throw explicit error
  throw AppFailure(
    'Supabase backend is not configured: ${backend.message}. Demo mode is disabled in production.',
  );
});
