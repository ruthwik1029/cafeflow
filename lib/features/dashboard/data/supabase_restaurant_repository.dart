import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_gateway.dart';
import '../../../core/services/backend.dart';

class RestaurantInfo {
  const RestaurantInfo({
    required this.id,
    required this.name,
    required this.slug,
    this.address = '',
    this.phone = '',
    this.email = '',
    this.isActive = true,
  });

  final String id;
  final String name;
  final String slug;
  final String address;
  final String phone;
  final String email;
  final bool isActive;
}

class RestaurantSettingsInfo {
  const RestaurantSettingsInfo({
    required this.restaurantId,
    this.currency = 'INR',
    this.gstRateBasisPoints = 500,
    this.receiptPrefix = 'ORD-',
    this.autoAcceptOrders = false,
  });

  final String restaurantId;
  final String currency;
  final int gstRateBasisPoints;
  final String receiptPrefix;
  final bool autoAcceptOrders;
}

class SupabaseRestaurantRepository {
  const SupabaseRestaurantRepository(this._gateway);
  final DatabaseGateway _gateway;

  Future<RestaurantInfo?> fetchBySlug(String slug) async {
    final rows = await _gateway.readRows(
      'restaurants',
      equals: {'slug': slug, 'is_active': true},
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return RestaurantInfo(
      id: row['id'] as String,
      name: row['name'] as String,
      slug: row['slug'] as String,
      address: (row['address'] as String?) ?? '',
      phone: (row['phone'] as String?) ?? '',
      email: (row['email'] as String?) ?? '',
      isActive: (row['is_active'] as bool?) ?? true,
    );
  }

  Future<RestaurantSettingsInfo?> fetchSettings(String restaurantId) async {
    final rows = await _gateway.readRows(
      'restaurant_settings',
      equals: {'restaurant_id': restaurantId},
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return RestaurantSettingsInfo(
      restaurantId: restaurantId,
      currency: (row['currency'] as String?) ?? 'INR',
      gstRateBasisPoints:
          (row['gst_rate_basis_points'] as num?)?.toInt() ?? 500,
      receiptPrefix: (row['receipt_prefix'] as String?) ?? 'ORD-',
      autoAcceptOrders: (row['auto_accept_orders'] as bool?) ?? false,
    );
  }
}

final restaurantRepositoryProvider = Provider<SupabaseRestaurantRepository?>((
  ref,
) {
  final backend = ref.watch(backendProvider);
  if (backend.status != BackendStatus.initialized) {
    return null;
  }
  return SupabaseRestaurantRepository(ref.watch(databaseGatewayProvider));
});
