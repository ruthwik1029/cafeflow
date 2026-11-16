import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/database_gateway.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/backend.dart';
import '../../../core/services/cafe_realtime_service.dart';
import '../../../core/services/realtime_gateway.dart';
import '../../orders/domain/cafe_order.dart';
import '../domain/payment_models.dart';
import '../domain/payment_repository.dart';

class SupabasePaymentRepository implements PaymentRepository {
  SupabasePaymentRepository({
    required this.gateway,
    this.client,
    this.realtime,
  });

  final DatabaseGateway gateway;
  final SupabaseClient? client;
  final CafeRealtimeService? realtime;

  @override
  Future<List<PaymentMethodRecord>> fetchPaymentMethods(
    String restaurantId,
  ) async {
    try {
      final rows = await gateway.readRows(
        'payment_methods',
        equals: {'restaurant_id': restaurantId},
      );

      final methods = rows.map((r) {
        return PaymentMethodRecord(
          id: r['id'] as String,
          restaurantId: r['restaurant_id'] as String,
          code: r['code'] as String,
          displayName: (r['display_name'] as String?) ?? r['code'] as String,
          isActive: (r['is_active'] as bool?) ?? true,
        );
      }).toList();

      if (methods.isEmpty) {
        // Fallback default methods for initial restaurant setup
        return const [
          PaymentMethodRecord(
            id: 'default-cash',
            restaurantId: '',
            code: 'CASH',
            displayName: 'Cash on Counter',
            isActive: true,
          ),
          PaymentMethodRecord(
            id: 'default-upi',
            restaurantId: '',
            code: 'UPI',
            displayName: 'UPI Instant QR',
            isActive: true,
          ),
          PaymentMethodRecord(
            id: 'default-card',
            restaurantId: '',
            code: 'CARD',
            displayName: 'Credit / Debit Card',
            isActive: true,
          ),
        ];
      }
      return methods;
    } catch (_) {
      return const [
        PaymentMethodRecord(
          id: 'fallback-cash',
          restaurantId: '',
          code: 'CASH',
          displayName: 'Cash',
          isActive: true,
        ),
        PaymentMethodRecord(
          id: 'fallback-upi',
          restaurantId: '',
          code: 'UPI',
          displayName: 'UPI',
          isActive: true,
        ),
        PaymentMethodRecord(
          id: 'fallback-card',
          restaurantId: '',
          code: 'CARD',
          displayName: 'Card',
          isActive: true,
        ),
      ];
    }
  }

  @override
  Future<void> updatePaymentMethodStatus({
    required String restaurantId,
    required String code,
    required bool isActive,
  }) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      throw const AppFailure('Payment method code cannot be empty.');
    }
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      await client!
          .rpc(
            'update_payment_method_status',
            params: {
              'p_restaurant_id': restaurantId,
              'p_code': cleanCode,
              'p_is_active': isActive,
            },
          )
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: only Owners and Admins can configure payment methods.',
        );
      }
      throw AppFailure(e.message);
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw const AppFailure('Failed to update payment method status.');
    }
  }

  @override
  Future<PaymentResult> recordPayment({
    required String restaurantId,
    required String orderId,
    required String paymentMethodCode,
    required int amountMinor,
    int? tenderedAmountMinor,
    String? transactionReference,
    String notes = '',
    String? idempotencyKey,
  }) async {
    final cleanCode = paymentMethodCode.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      throw const AppFailure('Payment method cannot be empty.');
    }
    if (amountMinor <= 0) {
      throw const AppFailure('Payment amount must be greater than zero.');
    }
    if (cleanCode == 'CASH' &&
        tenderedAmountMinor != null &&
        tenderedAmountMinor < amountMinor) {
      throw const AppFailure(
        'Tendered cash cannot be less than payment amount.',
      );
    }
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .rpc(
            'record_order_payment',
            params: {
              'p_restaurant_id': restaurantId,
              'p_order_id': orderId,
              'p_payment_method_code': cleanCode,
              'p_amount_minor': amountMinor,
              'p_tendered_amount_minor': tenderedAmountMinor,
              'p_transaction_reference': transactionReference?.trim(),
              'p_notes': notes.trim(),
              'p_idempotency_key': idempotencyKey?.trim(),
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = res as Map<String, dynamic>;
      return PaymentResult(
        paymentId: data['payment_id'] as String,
        orderId: data['order_id'] as String,
        amountMinor: (data['amount_minor'] as num).toInt(),
        changeDueMinor: (data['change_due_minor'] as num?)?.toInt() ?? 0,
        financialStatus: OrderFinancialStatusX.fromDb(
          data['financial_status'] as String?,
        ),
        paidAmountMinor: (data['paid_amount_minor'] as num).toInt(),
        totalMinor: (data['total_minor'] as num).toInt(),
        remainingMinor: (data['remaining_minor'] as num?)?.toInt() ?? 0,
        isReplay: (data['idempotent_replay'] as bool?) ?? false,
      );
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: role cannot record payments for this restaurant.',
        );
      }
      throw AppFailure(e.message);
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw const AppFailure('Network failure during payment recording.');
    }
  }

  @override
  Future<RefundResult> refundPayment({
    required String restaurantId,
    required String orderId,
    required String paymentId,
    required int refundAmountMinor,
    required String reason,
    String? idempotencyKey,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw const AppFailure('Refund reason cannot be empty.');
    }
    if (refundAmountMinor <= 0) {
      throw const AppFailure('Refund amount must be greater than zero.');
    }
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .rpc(
            'refund_order_payment',
            params: {
              'p_restaurant_id': restaurantId,
              'p_order_id': orderId,
              'p_payment_id': paymentId,
              'p_refund_amount_minor': refundAmountMinor,
              'p_reason': cleanReason,
              'p_idempotency_key': idempotencyKey?.trim(),
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = res as Map<String, dynamic>;
      return RefundResult(
        refundId: data['refund_id'] as String,
        paymentId: data['payment_id'] as String,
        orderId: data['order_id'] as String,
        refundAmountMinor: (data['refund_amount_minor'] as num).toInt(),
        newFinancialStatus: OrderFinancialStatusX.fromDb(
          data['new_financial_status'] as String?,
        ),
        orderTotalRefundedMinor:
            (data['order_total_refunded_minor'] as num?)?.toInt() ?? 0,
        isReplay: (data['idempotent_replay'] as bool?) ?? false,
      );
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: only Owners and Admins can process refunds.',
        );
      }
      throw AppFailure(e.message);
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw const AppFailure('Network failure during refund processing.');
    }
  }

  @override
  Future<List<PaymentRecord>> fetchPaymentsForOrder({
    required String restaurantId,
    required String orderId,
  }) async {
    try {
      final rows = await gateway.readRows(
        'payments',
        equals: {'order_id': orderId, 'restaurant_id': restaurantId},
      );

      final list = rows.map((r) {
        return PaymentRecord(
          id: r['id'] as String,
          orderId: r['order_id'] as String,
          restaurantId: (r['restaurant_id'] as String?) ?? restaurantId,
          paymentMethodCode: (r['payment_method_code'] as String?) ?? 'CASH',
          amountMinor: (r['amount_minor'] as num).toInt(),
          status: (r['status'] as String?) ?? 'COMPLETED',
          createdAt:
              DateTime.tryParse(r['created_at'] as String? ?? '') ??
              DateTime.now(),
          tenderedAmountMinor: (r['tendered_amount_minor'] as num?)?.toInt(),
          changeDueMinor: (r['change_due_minor'] as num?)?.toInt() ?? 0,
          transactionReference: r['transaction_reference'] as String?,
          notes: (r['notes'] as String?) ?? '',
          processedBy: r['processed_by'] as String?,
          processedAt: DateTime.tryParse(r['processed_at'] as String? ?? ''),
          isRefunded: (r['is_refunded'] as bool?) ?? false,
          refundedAmountMinor:
              (r['refunded_amount_minor'] as num?)?.toInt() ?? 0,
        );
      }).toList();

      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<FinancialReport> fetchFinancialReport({
    required String restaurantId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    final start = startDate ?? DateTime.now().subtract(const Duration(days: 1));
    final end = endDate ?? DateTime.now();

    try {
      final res = await client!
          .rpc(
            'get_financial_report',
            params: {
              'p_restaurant_id': restaurantId,
              'p_start_date': start.toIso8601String(),
              'p_end_date': end.toIso8601String(),
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = res as Map<String, dynamic>;
      return FinancialReport(
        startDate: start,
        endDate: end,
        grossSalesMinor: (data['gross_sales_minor'] as num?)?.toInt() ?? 0,
        netSalesMinor: (data['net_sales_minor'] as num?)?.toInt() ?? 0,
        discountsTotalMinor:
            (data['discounts_total_minor'] as num?)?.toInt() ?? 0,
        taxCollectedMinor: (data['tax_collected_minor'] as num?)?.toInt() ?? 0,
        serviceChargeMinor:
            (data['service_charge_minor'] as num?)?.toInt() ?? 0,
        totalPaymentsMinor:
            (data['total_payments_minor'] as num?)?.toInt() ?? 0,
        cashCollectedMinor:
            (data['cash_collected_minor'] as num?)?.toInt() ?? 0,
        upiCollectedMinor: (data['upi_collected_minor'] as num?)?.toInt() ?? 0,
        cardCollectedMinor:
            (data['card_collected_minor'] as num?)?.toInt() ?? 0,
        otherCollectedMinor:
            (data['other_collected_minor'] as num?)?.toInt() ?? 0,
        refundsTotalMinor: (data['refunds_total_minor'] as num?)?.toInt() ?? 0,
        netCollectedMinor: (data['net_collected_minor'] as num?)?.toInt() ?? 0,
        outstandingBalanceMinor:
            (data['outstanding_balance_minor'] as num?)?.toInt() ?? 0,
        totalOrdersCount: (data['total_orders_count'] as num?)?.toInt() ?? 0,
        paidOrdersCount: (data['paid_orders_count'] as num?)?.toInt() ?? 0,
        unpaidOrdersCount: (data['unpaid_orders_count'] as num?)?.toInt() ?? 0,
      );
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: only Owners and Admins can view financial reports.',
        );
      }
      throw AppFailure(e.message);
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw const AppFailure(
        'Network failure while fetching financial report.',
      );
    }
  }

  @override
  Future<RestaurantTaxSettings> fetchTaxSettings(String restaurantId) async {
    try {
      final rows = await gateway.readRows(
        'restaurant_settings',
        equals: {'restaurant_id': restaurantId},
      );
      if (rows.isNotEmpty) {
        final r = rows.first;
        return RestaurantTaxSettings(
          taxName: (r['tax_name'] as String?) ?? 'GST',
          gstRateBasisPoints:
              (r['gst_rate_basis_points'] as num?)?.toInt() ?? 500,
          taxIsInclusive: (r['tax_is_inclusive'] as bool?) ?? false,
          serviceChargeBasisPoints:
              (r['service_charge_basis_points'] as num?)?.toInt() ?? 0,
          serviceChargeName:
              (r['service_charge_name'] as String?) ?? 'Service Charge',
          currency: (r['currency'] as String?) ?? 'INR',
        );
      }
    } catch (_) {}
    return const RestaurantTaxSettings();
  }

  @override
  Future<void> updateTaxSettings({
    required String restaurantId,
    required String taxName,
    required int gstRateBasisPoints,
    required bool taxIsInclusive,
    required int serviceChargeBasisPoints,
    required String serviceChargeName,
  }) async {
    final cleanTaxName = taxName.trim();
    if (cleanTaxName.isEmpty) {
      throw const AppFailure('Tax name cannot be empty.');
    }
    if (gstRateBasisPoints < 0) {
      throw const AppFailure('Tax percentage cannot be negative.');
    }
    if (serviceChargeBasisPoints < 0) {
      throw const AppFailure('Service charge cannot be negative.');
    }
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      await client!
          .from('restaurant_settings')
          .update({
            'tax_name': cleanTaxName,
            'gst_rate_basis_points': gstRateBasisPoints,
            'tax_is_inclusive': taxIsInclusive,
            'service_charge_basis_points': serviceChargeBasisPoints,
            'service_charge_name': serviceChargeName.trim(),
          })
          .eq('restaurant_id', restaurantId)
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: only Owners and Admins can update tax settings.',
        );
      }
      throw AppFailure(e.message);
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw const AppFailure('Network failure while updating tax settings.');
    }
  }

  @override
  Stream<void> watchPaymentInvalidations({String? restaurantId}) {
    if (realtime == null) return const Stream.empty();
    final paymentStream = realtime!.watchPayments(restaurantId: restaurantId);
    final refundStream = realtime!.watchRefunds(restaurantId: restaurantId);
    return paymentStream
        .where((signal) => signal == RealtimeSignal.changed)
        .mergeWith([
          refundStream.where((signal) => signal == RealtimeSignal.changed),
        ]);
  }
}

extension _StreamMerge<T> on Stream<T> {
  Stream<T> mergeWith(Iterable<Stream<T>> others) {
    final controller = StreamController<T>.broadcast();
    final subscriptions = <StreamSubscription<T>>[];

    void handleData(T data) {
      if (!controller.isClosed) controller.add(data);
    }

    void handleError(Object error, StackTrace stack) {
      if (!controller.isClosed) controller.addError(error, stack);
    }

    subscriptions.add(listen(handleData, onError: handleError));
    for (final other in others) {
      subscriptions.add(other.listen(handleData, onError: handleError));
    }

    controller.onCancel = () async {
      for (final s in subscriptions) {
        await s.cancel();
      }
    };

    return controller.stream;
  }
}

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend.status == BackendStatus.initialized) {
    return SupabasePaymentRepository(
      gateway: ref.watch(databaseGatewayProvider),
      client: ref.watch(supabaseClientProvider),
      realtime: ref.watch(cafeRealtimeServiceProvider),
    );
  }
  return SupabasePaymentRepository(
    gateway: ref.watch(databaseGatewayProvider),
    client: null,
  );
});
