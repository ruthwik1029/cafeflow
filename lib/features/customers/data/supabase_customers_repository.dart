import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/database_gateway.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/backend.dart';
import '../../../core/services/cafe_realtime_service.dart';
import '../../../core/services/realtime_gateway.dart';

class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.phone = '',
    this.email = '',
    this.loyaltyTier = 'GUEST',
    this.totalSpendMinor = 0,
    this.visitsCount = 0,
    this.favoriteItem = '',
    this.lastVisitedAt,
  });

  final String id;
  final String restaurantId;
  final String name;
  final String phone;
  final String email;
  final String loyaltyTier;
  final int totalSpendMinor;
  final int visitsCount;
  final String favoriteItem;
  final DateTime? lastVisitedAt;
}

class SupabaseCustomersRepository {
  SupabaseCustomersRepository({
    required this.gateway,
    this.client,
    this.realtime,
  });

  final DatabaseGateway gateway;
  final SupabaseClient? client;
  final CafeRealtimeService? realtime;

  Future<List<CustomerRecord>> listCustomers({
    required String restaurantId,
    String search = '',
  }) async {
    final rows = await gateway.readRows(
      'customers',
      equals: {'restaurant_id': restaurantId, 'deleted_at': 'null'},
      limit: 100,
    );

    final cleanSearch = search.trim().toLowerCase();
    final results = rows
        .map((row) {
          return CustomerRecord(
            id: row['id'] as String,
            restaurantId: row['restaurant_id'] as String,
            name: row['name'] as String,
            phone: (row['phone'] as String?) ?? '',
            email: (row['email'] as String?) ?? '',
            loyaltyTier: (row['loyalty_tier'] as String?) ?? 'GUEST',
            totalSpendMinor: (row['total_spend_minor'] as num?)?.toInt() ?? 0,
            visitsCount: (row['visits_count'] as num?)?.toInt() ?? 0,
            favoriteItem: (row['favorite_item'] as String?) ?? '',
            lastVisitedAt: DateTime.tryParse(
              row['last_visited_at'] as String? ?? '',
            ),
          );
        })
        .where((c) {
          if (cleanSearch.isEmpty) return true;
          return c.name.toLowerCase().contains(cleanSearch) ||
              c.phone.contains(cleanSearch) ||
              c.email.toLowerCase().contains(cleanSearch);
        })
        .toList();

    return results;
  }

  Future<CustomerRecord> createCustomer({
    required String restaurantId,
    required String name,
    String phone = '',
    String email = '',
    String favoriteItem = '',
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const AppFailure('Customer name cannot be empty.');
    }
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .from('customers')
          .insert({
            'restaurant_id': restaurantId,
            'name': trimmedName,
            'phone': phone.trim(),
            'email': email.trim(),
            'favorite_item': favoriteItem.trim(),
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 15));

      return CustomerRecord(
        id: res['id'] as String,
        restaurantId: res['restaurant_id'] as String,
        name: res['name'] as String,
        phone: (res['phone'] as String?) ?? '',
        email: (res['email'] as String?) ?? '',
        loyaltyTier: (res['loyalty_tier'] as String?) ?? 'GUEST',
        totalSpendMinor: (res['total_spend_minor'] as num?)?.toInt() ?? 0,
        visitsCount: (res['visits_count'] as num?)?.toInt() ?? 0,
        favoriteItem: (res['favorite_item'] as String?) ?? '',
      );
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure('Unauthorized: cannot create customer record.');
      }
      throw AppFailure(e.message);
    } catch (_) {
      throw const AppFailure('Network failure while saving customer record.');
    }
  }

  Stream<void> watchInvalidations(String restaurantId) {
    if (realtime == null) return const Stream.empty();
    return realtime!
        .watchCustomers(restaurantId: restaurantId)
        .transform(
          StreamTransformer<RealtimeSignal, void>.fromHandlers(
            handleData: (signal, sink) => sink.add(null),
            handleError: (error, stackTrace, sink) {},
          ),
        );
  }
}

final customersRepositoryProvider = Provider<SupabaseCustomersRepository?>((
  ref,
) {
  final backend = ref.watch(backendProvider);
  if (backend.status != BackendStatus.initialized) {
    return null;
  }
  return SupabaseCustomersRepository(
    gateway: ref.watch(databaseGatewayProvider),
    client: backend.client,
    realtime: ref.watch(cafeRealtimeServiceProvider),
  );
});
