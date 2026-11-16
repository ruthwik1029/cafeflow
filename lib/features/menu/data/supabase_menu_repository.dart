import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/database_gateway.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/backend.dart';
import '../../../core/services/cafe_realtime_service.dart';
import '../../../core/services/realtime_gateway.dart';
import '../domain/catalog.dart';
import '../domain/menu_repository.dart';

class SupabaseMenuRepository implements MenuRepository {
  SupabaseMenuRepository({required this.gateway, this.client, this.realtime});

  final DatabaseGateway gateway;
  final SupabaseClient? client;
  final CafeRealtimeService? realtime;

  @override
  Future<List<MenuItem>> listAvailable({String? restaurantId}) async {
    final equals = <String, Object>{'is_available': true, 'is_archived': false};
    if (restaurantId != null && restaurantId.isNotEmpty) {
      equals['restaurant_id'] = restaurantId;
    }
    final rows = await gateway.readRows('menu_items', equals: equals);
    return rows
        .map(
          (row) => MenuItem(
            id: row['id'] as String,
            name: row['name'] as String,
            available: (row['is_available'] as bool?) ?? true,
          ),
        )
        .toList();
  }

  /// Fetches a full CatalogSnapshot for the current cafe from Supabase.
  Future<CatalogSnapshot> fetchCatalog({String? restaurantId}) async {
    final categoryEquals = <String, Object>{'is_active': true};
    final itemEquals = <String, Object>{'is_archived': false};
    if (restaurantId != null && restaurantId.isNotEmpty) {
      categoryEquals['restaurant_id'] = restaurantId;
      itemEquals['restaurant_id'] = restaurantId;
    }

    final categoryRows = await gateway.readRows(
      'menu_categories',
      equals: categoryEquals,
    );
    final categories = categoryRows.map((row) {
      return MenuCategory(
        id: row['id'] as String,
        name: row['name'] as String,
        active: (row['is_active'] as bool?) ?? true,
      );
    }).toList();

    final itemRows = await gateway.readRows('menu_items', equals: itemEquals);
    final products = itemRows.map((row) {
      return MenuProduct(
        id: row['id'] as String,
        categoryId: row['category_id'] as String,
        name: row['name'] as String,
        priceMinor: (row['price_minor'] as num).toInt(),
        description: (row['description'] as String?) ?? '',
        image: (row['image_url'] as String?) ?? '',
        available: (row['is_available'] as bool?) ?? true,
        archived: (row['is_archived'] as bool?) ?? false,
        featured: (row['is_featured'] as bool?) ?? false,
      );
    }).toList();

    return CatalogSnapshot(
      categories: categories,
      products: products,
      isDemo: false,
    );
  }

  /// Creates a new menu category
  Future<MenuCategory> createCategory({
    required String restaurantId,
    required String name,
    int displayOrder = 0,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const AppFailure('Category name cannot be empty.');
    }
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .from('menu_categories')
          .insert({
            'restaurant_id': restaurantId,
            'name': trimmedName,
            'display_order': displayOrder,
            'is_active': true,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 15));

      return MenuCategory(
        id: res['id'] as String,
        name: res['name'] as String,
        active: (res['is_active'] as bool?) ?? true,
      );
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: only Owners and Admins can create categories.',
        );
      }
      throw AppFailure(e.message);
    } catch (_) {
      throw const AppFailure('Network failure while creating menu category.');
    }
  }

  /// Updates an existing menu category
  Future<void> updateCategory({
    required String categoryId,
    required String name,
    bool active = true,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const AppFailure('Category name cannot be empty.');
    }
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      await client!
          .from('menu_categories')
          .update({'name': trimmedName, 'is_active': active})
          .eq('id', categoryId)
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: only Owners and Admins can edit categories.',
        );
      }
      throw AppFailure(e.message);
    } catch (_) {
      throw const AppFailure('Network failure while updating category.');
    }
  }

  /// Creates a new menu item
  Future<MenuProduct> createMenuItem({
    required String restaurantId,
    required String categoryId,
    required String name,
    required int priceMinor,
    String description = '',
    String imageUrl = '',
    bool available = true,
    bool featured = false,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const AppFailure('Product name cannot be empty.');
    }
    if (priceMinor < 0) {
      throw const AppFailure('Price cannot be negative.');
    }
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .from('menu_items')
          .insert({
            'restaurant_id': restaurantId,
            'category_id': categoryId,
            'name': trimmedName,
            'price_minor': priceMinor,
            'description': description.trim(),
            'image_url': imageUrl.trim(),
            'is_available': available,
            'is_featured': featured,
            'is_archived': false,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 15));

      return MenuProduct(
        id: res['id'] as String,
        categoryId: res['category_id'] as String,
        name: res['name'] as String,
        priceMinor: (res['price_minor'] as num).toInt(),
        description: (res['description'] as String?) ?? '',
        image: (res['image_url'] as String?) ?? '',
        available: (res['is_available'] as bool?) ?? true,
        archived: false,
        featured: (res['is_featured'] as bool?) ?? false,
      );
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: only Owners and Admins can create menu items.',
        );
      }
      throw AppFailure(e.message);
    } catch (_) {
      throw const AppFailure('Network failure while creating menu item.');
    }
  }

  /// Updates an existing menu item
  Future<void> updateMenuItem({
    required String itemId,
    String? name,
    int? priceMinor,
    String? description,
    String? categoryId,
    String? imageUrl,
    bool? available,
    bool? featured,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        throw const AppFailure('Product name cannot be empty.');
      }
      updates['name'] = trimmed;
    }
    if (priceMinor != null) {
      if (priceMinor < 0) {
        throw const AppFailure('Price cannot be negative.');
      }
      updates['price_minor'] = priceMinor;
    }
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }
    if (description != null) updates['description'] = description.trim();
    if (categoryId != null) updates['category_id'] = categoryId;
    if (imageUrl != null) updates['image_url'] = imageUrl.trim();
    if (available != null) updates['is_available'] = available;
    if (featured != null) updates['is_featured'] = featured;

    try {
      await client!
          .from('menu_items')
          .update(updates)
          .eq('id', itemId)
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: only Owners and Admins can edit menu items.',
        );
      }
      throw AppFailure(e.message);
    } catch (_) {
      throw const AppFailure('Network failure while updating menu item.');
    }
  }

  /// Sets menu item availability
  Future<void> setMenuItemAvailability({
    required String itemId,
    required bool available,
  }) async {
    return updateMenuItem(itemId: itemId, available: available);
  }

  /// Archives a menu item, preserving it for historical orders
  Future<void> archiveMenuItem({required String itemId}) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }
    try {
      await client!
          .from('menu_items')
          .update({'is_archived': true, 'is_available': false})
          .eq('id', itemId)
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: only Owners and Admins can archive menu items.',
        );
      }
      throw AppFailure(e.message);
    } catch (_) {
      throw const AppFailure('Network failure while archiving menu item.');
    }
  }

  /// Uploads menu image to Supabase Storage menu-images bucket
  Future<String> uploadMenuImage({
    required Uint8List imageBytes,
    required String fileName,
    String mimeType = 'image/jpeg',
  }) async {
    if (client == null) {
      throw const AppFailure('Storage client is not available.');
    }
    final safeName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';

    try {
      await client!.storage
          .from('menu-images')
          .uploadBinary(
            safeName,
            imageBytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          )
          .timeout(const Duration(seconds: 30));

      return client!.storage.from('menu-images').getPublicUrl(safeName);
    } on StorageException catch (e) {
      throw AppFailure('Storage error: ${e.message}');
    } catch (_) {
      throw const AppFailure('Failed to upload image. Please check network.');
    }
  }

  @override
  Stream<void> watchInvalidations({String? restaurantId}) {
    if (realtime == null) {
      return const Stream.empty();
    }
    return realtime!
        .watchMenu(restaurantId: restaurantId)
        .transform(
          StreamTransformer<RealtimeSignal, void>.fromHandlers(
            handleData: (signal, sink) => sink.add(null),
            handleError: (error, stackTrace, sink) {
              if (error is AppFailure) {
                // Ignore transient transport failures in stream listeners
              }
            },
          ),
        );
  }
}

final menuRepositoryProvider = Provider<MenuRepository?>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend.status != BackendStatus.initialized) {
    return null;
  }
  return SupabaseMenuRepository(
    gateway: ref.watch(databaseGatewayProvider),
    client: backend.client,
    realtime: ref.watch(cafeRealtimeServiceProvider),
  );
});
