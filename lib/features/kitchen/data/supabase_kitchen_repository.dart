import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/database_gateway.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/backend.dart';
import '../../../core/services/cafe_realtime_service.dart';
import '../../../core/services/realtime_gateway.dart';
import '../../orders/domain/cafe_order.dart';
import '../domain/kot_models.dart';

export '../domain/kot_models.dart';

class SupabaseKitchenRepository {
  SupabaseKitchenRepository({
    required this.gateway,
    this.client,
    this.realtime,
  });

  final DatabaseGateway gateway;
  final SupabaseClient? client;
  final CafeRealtimeService? realtime;

  // --------------------------------------------------------------------------
  // Kitchen Stations
  // --------------------------------------------------------------------------

  Future<List<KitchenStation>> listStations(String restaurantId) async {
    final rows = await gateway.readRows(
      'kitchen_stations',
      equals: {'restaurant_id': restaurantId, 'is_active': true},
      limit: 20,
    );
    return rows.map(KitchenStation.fromMap).toList();
  }

  Future<KitchenStation> createStation({
    required String restaurantId,
    required String name,
    required String code,
    String description = '',
    String printerName = '',
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .from('kitchen_stations')
          .insert({
            'restaurant_id': restaurantId,
            'name': name.trim(),
            'code': code.trim().toUpperCase(),
            'description': description.trim(),
            'printer_name': printerName.trim(),
            'is_active': true,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 15));

      return KitchenStation.fromMap(res);
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: only admins can manage kitchen stations.',
        );
      }
      throw AppFailure(e.message);
    } catch (_) {
      throw const AppFailure('Network failure while creating kitchen station.');
    }
  }

  // --------------------------------------------------------------------------
  // Kitchen Order Tickets (KOT)
  // --------------------------------------------------------------------------

  Future<List<KitchenOrderTicket>> listKots({
    required String restaurantId,
    String? stationId,
    KotStatus? status,
  }) async {
    final equals = <String, Object>{'restaurant_id': restaurantId};
    if (stationId != null) equals['station_id'] = stationId;
    if (status != null) equals['status'] = status.dbValue;

    final kotRows = await gateway.readRows(
      'kitchen_order_tickets',
      equals: equals,
      limit: 100,
    );

    // Fetch station name mappings
    Map<String, String> stationMap = {};
    try {
      final stations = await listStations(restaurantId);
      for (final s in stations) {
        stationMap[s.id] = s.name;
      }
    } catch (_) {}

    // Fetch items for each KOT
    final List<KitchenOrderTicket> tickets = [];
    for (final row in kotRows) {
      final kotId = row['id'] as String;
      final itemRows = await gateway.readRows(
        'kot_items',
        equals: {'kot_id': kotId},
        limit: 50,
      );
      final items = itemRows.map(KotItem.fromMap).toList();
      items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final stId = row['station_id'] as String?;

      tickets.add(
        KitchenOrderTicket.fromMap(
          row,
          items: items,
          stationName: stId != null ? stationMap[stId] : null,
        ),
      );
    }

    tickets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return tickets;
  }

  /// Create Dine-In or Takeaway Order with Automatic Initial KOT
  Future<Map<String, dynamic>> createOrderWithKot({
    required String restaurantId,
    required String tableName,
    String? tableSessionId,
    required String orderType,
    required List<OrderSubmissionItem> items,
    String specialInstructions = '',
    int discountMinor = 0,
    String discountReason = '',
    String? idempotencyKey,
    String? clientTxId,
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    final itemsPayload = items
        .map((i) => {'menu_item_id': i.menuItemId, 'quantity': i.quantity})
        .toList();

    try {
      final res = await client!
          .rpc(
            'create_order_with_kot',
            params: {
              'p_restaurant_id': restaurantId,
              'p_table_name': tableName,
              'p_table_session_id': tableSessionId,
              'p_order_type': orderType,
              'p_items': itemsPayload,
              'p_special_instructions': specialInstructions,
              'p_discount_minor': discountMinor,
              'p_discount_reason': discountReason,
              'p_idempotency_key': idempotencyKey,
              'p_client_tx_id': clientTxId,
            },
          )
          .timeout(const Duration(seconds: 15));

      return Map<String, dynamic>.from(res as Map);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    } catch (e) {
      throw AppFailure('Failed to create order with KOT: $e');
    }
  }

  /// Adds incremental items to an existing open table order (Generates new KOT)
  Future<Map<String, dynamic>> addItemsToOrder({
    required String restaurantId,
    required String orderId,
    required List<OrderSubmissionItem> newItems,
    String specialInstructions = '',
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    final itemsPayload = newItems
        .map((i) => {'menu_item_id': i.menuItemId, 'quantity': i.quantity})
        .toList();

    try {
      final res = await client!
          .rpc(
            'add_items_to_table_order',
            params: {
              'p_restaurant_id': restaurantId,
              'p_order_id': orderId,
              'p_new_items': itemsPayload,
              'p_special_instructions': specialInstructions,
            },
          )
          .timeout(const Duration(seconds: 15));

      return Map<String, dynamic>.from(res as Map);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    } catch (e) {
      throw AppFailure('Failed to add items to order: $e');
    }
  }

  /// Updates status of an individual item in a KOT
  Future<void> updateKotItemStatus({
    required String restaurantId,
    required String kotItemId,
    required KotStatus status,
    String? cancelReason,
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      await client!
          .rpc(
            'update_kot_item_status',
            params: {
              'p_restaurant_id': restaurantId,
              'p_kot_item_id': kotItemId,
              'p_status': status.dbValue,
              'p_cancel_reason': cancelReason ?? '',
            },
          )
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    } catch (e) {
      throw AppFailure('Failed to update KOT item: $e');
    }
  }

  /// Updates status of the entire KOT
  Future<void> updateKotStatus({
    required String restaurantId,
    required String kotId,
    required KotStatus status,
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      await client!
          .from('kitchen_order_tickets')
          .update({
            'status': status.dbValue,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', kotId)
          .eq('restaurant_id', restaurantId)
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    } catch (e) {
      throw AppFailure('Failed to update KOT status: $e');
    }
  }

  Stream<void> watchKitchen(String restaurantId) {
    if (realtime == null) return const Stream.empty();
    return realtime!
        .watchKitchenTickets(restaurantId: restaurantId)
        .transform(
          StreamTransformer<RealtimeSignal, void>.fromHandlers(
            handleData: (signal, sink) => sink.add(null),
            handleError: (error, stackTrace, sink) {},
          ),
        );
  }
}

final kitchenRepositoryProvider = Provider<SupabaseKitchenRepository?>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend.status != BackendStatus.initialized) {
    return null;
  }
  return SupabaseKitchenRepository(
    gateway: ref.watch(databaseGatewayProvider),
    client: backend.client,
    realtime: ref.watch(cafeRealtimeServiceProvider),
  );
});
