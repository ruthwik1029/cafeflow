import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/database_gateway.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/backend.dart';
import '../../../core/services/cafe_realtime_service.dart';
import '../../../core/services/realtime_gateway.dart';
import '../domain/cafe_order.dart';
import '../domain/order_repository.dart';

class SupabaseOrderRepository implements OrderRepository {
  SupabaseOrderRepository({required this.gateway, this.client, this.realtime});

  final DatabaseGateway gateway;
  final SupabaseClient? client;
  final CafeRealtimeService? realtime;

  @override
  Future<List<OrderReference>> listActive({String? restaurantId}) async {
    final equals = <String, Object>{'deleted_at': 'null'};
    if (restaurantId != null && restaurantId.isNotEmpty) {
      equals['restaurant_id'] = restaurantId;
    }
    final rows = await gateway.readRows('orders', equals: equals);
    return rows.map((row) {
      return OrderReference(
        id: row['id'] as String,
        displayNumber: row['order_number'] as String,
      );
    }).toList();
  }

  /// Maps remote orders into domain CafeOrder models
  Future<List<CafeOrder>> fetchOrders({String? restaurantId}) async {
    final equals = <String, Object>{};
    if (restaurantId != null && restaurantId.isNotEmpty) {
      equals['restaurant_id'] = restaurantId;
    }

    final orderRows = await gateway.readRows(
      'orders',
      equals: equals,
      limit: 100,
    );
    final List<CafeOrder> result = [];

    for (final row in orderRows) {
      final orderId = row['id'] as String;
      final rawStatus = row['status'] as String? ?? 'NEW';
      final status = switch (rawStatus.toUpperCase()) {
        'NEW' => OrderStatus.newOrder,
        'PREPARING' => OrderStatus.preparing,
        'READY' => OrderStatus.ready,
        'COMPLETED' => OrderStatus.completed,
        'CANCELLED' => OrderStatus.cancelled,
        _ => OrderStatus.newOrder,
      };

      // Read items for this order
      final itemRows = await gateway.readRows(
        'order_items',
        equals: {'order_id': orderId},
      );

      final lines = itemRows.map((i) {
        return OrderLine(
          productId: (i['menu_item_id'] as String?) ?? '',
          name: i['item_name'] as String,
          unitMinor: (i['unit_price_minor'] as num).toInt(),
          quantity: (i['quantity'] as num).toInt(),
        );
      }).toList();

      result.add(
        CafeOrder(
          id: orderId,
          number: row['order_number'] as String,
          createdAt:
              DateTime.tryParse(row['created_at'] as String? ?? '') ??
              DateTime.now(),
          lines: lines,
          status: status,
          financialStatus: OrderFinancialStatusX.fromDb(
            row['financial_status'] as String?,
          ),
          table: (row['table_name'] as String?) ?? 'Takeaway',
          instructions: (row['special_instructions'] as String?) ?? '',
          taxMinor: (row['tax_minor'] as num?)?.toInt() ?? 0,
          discountMinor: (row['discount_minor'] as num?)?.toInt() ?? 0,
          serviceChargeMinor:
              (row['service_charge_minor'] as num?)?.toInt() ?? 0,
          paidMinor: (row['paid_amount_minor'] as num?)?.toInt() ?? 0,
          refundedMinor: (row['refunded_amount_minor'] as num?)?.toInt() ?? 0,
          taxName: (row['tax_name'] as String?) ?? 'GST',
          taxRateBps: (row['tax_rate_basis_points'] as num?)?.toInt() ?? 500,
          taxIsInclusive: (row['tax_is_inclusive'] as bool?) ?? false,
          discountReason: (row['discount_reason'] as String?) ?? '',
        ),
      );
    }

    // Sort descending by creation date (newest first)
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// Atomically creates an order with lines via the create_order_with_items RPC
  Future<CreatedOrderResult> createOrder({
    required String restaurantId,
    required String tableName,
    required List<OrderSubmissionItem> items,
    String specialInstructions = '',
    int discountMinor = 0,
    String discountReason = '',
    String? idempotencyKey,
    String? customerId,
  }) async {
    if (items.isEmpty) {
      throw const AppFailure('Cannot create an order with no items.');
    }
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .rpc(
            'create_order_with_items',
            params: {
              'p_restaurant_id': restaurantId,
              'p_table_name': tableName.trim().isEmpty
                  ? 'Takeaway'
                  : tableName.trim(),
              'p_special_instructions': specialInstructions.trim(),
              'p_discount_minor': discountMinor,
              'p_discount_reason': discountReason.trim(),
              'p_items': items.map((i) => i.toJson()).toList(),
              'p_idempotency_key': idempotencyKey,
              'p_customer_id': customerId,
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = res as Map<String, dynamic>;
      return CreatedOrderResult(
        id: data['id'] as String,
        orderNumber: data['order_number'] as String,
        subtotalMinor: (data['subtotal_minor'] as num?)?.toInt() ?? 0,
        discountMinor: (data['discount_minor'] as num?)?.toInt() ?? 0,
        taxMinor: (data['tax_minor'] as num?)?.toInt() ?? 0,
        serviceChargeMinor:
            (data['service_charge_minor'] as num?)?.toInt() ?? 0,
        totalMinor: (data['total_minor'] as num?)?.toInt() ?? 0,
        financialStatus: OrderFinancialStatusX.fromDb(
          data['financial_status'] as String?,
        ),
        isReplay: (data['idempotent_replay'] as bool?) ?? false,
      );
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw AppFailure('Permission denied: ${e.message}');
      }
      throw AppFailure(e.message);
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw const AppFailure('Network failure while creating order.');
    }
  }

  /// Transitions status on remote database using the SEC-03 advance_order_status RPC
  Future<void> updateStatus(
    String orderId,
    OrderStatus status, {
    String notes = '',
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }
    final dbStatus = switch (status) {
      OrderStatus.newOrder => 'NEW',
      OrderStatus.preparing => 'PREPARING',
      OrderStatus.ready => 'READY',
      OrderStatus.completed => 'COMPLETED',
      OrderStatus.cancelled => 'CANCELLED',
    };

    try {
      // Use the SEC-03 controlled RPC function to enforce role lifecycle rules
      // and prevent direct modification of financial totals
      await client!
          .rpc(
            'advance_order_status',
            params: {
              'p_order_id': orderId,
              'p_next_status': dbStatus,
              'p_notes': notes,
            },
          )
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw AppFailure('Permission denied: ${e.message}');
      }
      throw AppFailure(e.message);
    } catch (_) {
      throw const AppFailure('Network failure while updating order status.');
    }
  }

  @override
  Stream<void> watchInvalidations({String? restaurantId}) {
    if (realtime == null) {
      return const Stream.empty();
    }
    return realtime!
        .watchOrders(restaurantId: restaurantId)
        .transform(
          StreamTransformer<RealtimeSignal, void>.fromHandlers(
            handleData: (signal, sink) => sink.add(null),
            handleError: (error, stackTrace, sink) {
              if (error is AppFailure) {
                // Ignore transient failures in listener
              }
            },
          ),
        );
  }
}

final orderRepositoryProvider = Provider<OrderRepository?>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend.status != BackendStatus.initialized) {
    return null;
  }
  return SupabaseOrderRepository(
    gateway: ref.watch(databaseGatewayProvider),
    client: backend.client,
    realtime: ref.watch(cafeRealtimeServiceProvider),
  );
});
