import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/services/backend.dart';
import '../../../core/services/cafe_realtime_service.dart';
import '../../orders/domain/cafe_order.dart';

class CustomerOrderSubmission {
  const CustomerOrderSubmission({
    required this.customerName,
    this.customerPhone = '',
    required this.orderType,
    this.tableName = 'Table 01',
    this.specialInstructions = '',
    required this.items,
    this.pairingCode,
  });

  final String customerName;
  final String customerPhone;
  final String orderType; // 'DINE_IN' or 'TAKEAWAY'
  final String tableName;
  final String specialInstructions;
  final List<CustomerOrderItem> items;
  final String? pairingCode;
}

class CustomerOrderItem {
  const CustomerOrderItem({required this.productId, required this.quantity});

  final String productId;
  final int quantity;

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'quantity': quantity,
  };
}

class CustomerOrderResult {
  const CustomerOrderResult({
    required this.orderId,
    required this.orderNumber,
    required this.subtotalMinor,
    required this.taxMinor,
    required this.totalMinor,
    this.pairingCode,
  });

  final String orderId;
  final String orderNumber;
  final int subtotalMinor;
  final int taxMinor;
  final int totalMinor;
  final String? pairingCode;

  factory CustomerOrderResult.fromJson(Map<String, dynamic> json) =>
      CustomerOrderResult(
        orderId: json['order_id'] as String? ?? '',
        orderNumber: json['order_number'] as String? ?? '',
        subtotalMinor: (json['subtotal_minor'] as num?)?.toInt() ?? 0,
        taxMinor: (json['tax_minor'] as num?)?.toInt() ?? 0,
        totalMinor: (json['total_minor'] as num?)?.toInt() ?? 0,
        pairingCode: json['pairing_code'] as String?,
      );
}

class CustomerTrackedOrder {
  const CustomerTrackedOrder({
    required this.orderId,
    required this.orderNumber,
    required this.status,
    required this.financialStatus,
    required this.subtotalMinor,
    required this.taxMinor,
    required this.totalMinor,
    required this.tableName,
    required this.orderType,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
  });

  final String orderId;
  final String orderNumber;
  final OrderStatus status;
  final OrderFinancialStatus financialStatus;
  final int subtotalMinor;
  final int taxMinor;
  final int totalMinor;
  final String tableName;
  final String orderType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Map<String, dynamic>> items;

  factory CustomerTrackedOrder.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] as String? ?? 'NEW').toUpperCase();
    final status = switch (rawStatus) {
      'NEW' => OrderStatus.newOrder,
      'PREPARING' => OrderStatus.preparing,
      'READY' => OrderStatus.ready,
      'COMPLETED' => OrderStatus.completed,
      'CANCELLED' => OrderStatus.cancelled,
      _ => OrderStatus.newOrder,
    };

    final rawFinancial = (json['financial_status'] as String? ?? 'UNPAID')
        .toUpperCase();
    final financial = OrderFinancialStatusX.fromDb(rawFinancial);

    return CustomerTrackedOrder(
      orderId: json['order_id'] as String? ?? '',
      orderNumber: json['order_number'] as String? ?? '',
      status: status,
      financialStatus: financial,
      subtotalMinor: (json['subtotal_minor'] as num?)?.toInt() ?? 0,
      taxMinor: (json['tax_minor'] as num?)?.toInt() ?? 0,
      totalMinor: (json['total_minor'] as num?)?.toInt() ?? 0,
      tableName: json['table_name'] as String? ?? 'Table 01',
      orderType: json['order_type'] as String? ?? 'DINE_IN',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      items:
          (json['items'] as List<dynamic>?)
              ?.map((i) => i as Map<String, dynamic>)
              .toList() ??
          const [],
    );
  }
}

class CustomerOrderService {
  CustomerOrderService({required this.client, this.realtime});

  final SupabaseClient? client;
  final CafeRealtimeService? realtime;

  /// Places a public customer online order via server-enforced RPC.
  Future<CustomerOrderResult> submitOrder(
    CustomerOrderSubmission submission,
  ) async {
    final supabase = client;
    if (supabase == null) {
      throw const AppFailure('Online ordering service is unavailable.');
    }

    if (submission.customerName.trim().length < 2) {
      throw const AppFailure(
        'Please provide your name (at least 2 characters).',
      );
    }

    if (submission.items.isEmpty) {
      throw const AppFailure(
        'Your cart is empty. Please add items to place an order.',
      );
    }

    try {
      final res = await supabase
          .rpc(
            'create_public_online_order',
            params: {
              'p_customer_name': submission.customerName.trim(),
              'p_customer_phone': submission.customerPhone.trim(),
              'p_order_type': submission.orderType,
              'p_table_name': submission.tableName.trim(),
              'p_special_instructions': submission.specialInstructions.trim(),
              'p_items': submission.items.map((i) => i.toJson()).toList(),
              if (submission.pairingCode != null &&
                  submission.pairingCode!.trim().isNotEmpty)
                'p_pairing_code': submission.pairingCode!.trim(),
              'p_client_ip': 'web-guest',
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = res as Map<String, dynamic>;
      return CustomerOrderResult.fromJson(data);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw const AppFailure(
        'Failed to submit online order. Please check your connection.',
      );
    }
  }

  /// Fetches latest status of a customer order via secure RPC.
  Future<CustomerTrackedOrder> fetchOrderStatus(String orderId) async {
    final supabase = client;
    if (supabase == null) {
      throw const AppFailure('Online ordering service is unavailable.');
    }

    try {
      final res = await supabase
          .rpc('get_customer_order_status', params: {'p_order_id': orderId})
          .timeout(const Duration(seconds: 10));

      final data = res as Map<String, dynamic>;
      return CustomerTrackedOrder.fromJson(data);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw const AppFailure('Unable to load order status.');
    }
  }

  /// Subscribes to Realtime status changes for this specific order.
  Stream<OrderStatus> watchOrderStatus(String orderId) {
    final supabase = client;
    if (supabase == null) return const Stream.empty();

    final controller = StreamController<OrderStatus>();
    final channel = supabase.channel('order_tracking:$orderId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'orders',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: orderId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        final rawStatus = (newRecord['status'] as String? ?? 'NEW')
            .toUpperCase();
        final status = switch (rawStatus) {
          'NEW' => OrderStatus.newOrder,
          'PREPARING' => OrderStatus.preparing,
          'READY' => OrderStatus.ready,
          'COMPLETED' => OrderStatus.completed,
          'CANCELLED' => OrderStatus.cancelled,
          _ => OrderStatus.newOrder,
        };
        if (!controller.isClosed) {
          controller.add(status);
        }
      },
    );

    channel.subscribe();

    controller.onCancel = () async {
      await supabase.removeChannel(channel);
    };

    return controller.stream;
  }
}

final customerOrderServiceProvider = Provider<CustomerOrderService>((ref) {
  final backend = ref.watch(backendProvider);
  return CustomerOrderService(
    client: backend.client,
    realtime: ref.watch(cafeRealtimeServiceProvider),
  );
});
