import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backend.dart';
import '../../auth/application/auth_controller.dart';
import '../data/supabase_payment_repository.dart';
import '../domain/payment_models.dart';

export '../data/supabase_payment_repository.dart'
    show paymentRepositoryProvider;

final paymentMethodsProvider = FutureProvider<List<PaymentMethodRecord>>((
  ref,
) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(paymentRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      restaurantId != null &&
      repo is SupabasePaymentRepository) {
    try {
      final sub = repo
          .watchPaymentInvalidations(restaurantId: restaurantId)
          .listen((_) {
            ref.invalidateSelf();
          });
      ref.onDispose(sub.cancel);

      return await repo.fetchPaymentMethods(restaurantId);
    } catch (_) {}
  }

  return const [
    PaymentMethodRecord(
      id: 'demo-cash',
      restaurantId: 'demo',
      code: 'CASH',
      displayName: 'Cash on Counter',
      isActive: true,
    ),
    PaymentMethodRecord(
      id: 'demo-upi',
      restaurantId: 'demo',
      code: 'UPI',
      displayName: 'UPI Instant QR',
      isActive: true,
    ),
    PaymentMethodRecord(
      id: 'demo-card',
      restaurantId: 'demo',
      code: 'CARD',
      displayName: 'Credit / Debit Card',
      isActive: true,
    ),
  ];
});

final restaurantTaxSettingsProvider = FutureProvider<RestaurantTaxSettings>((
  ref,
) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(paymentRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      restaurantId != null &&
      repo is SupabasePaymentRepository) {
    try {
      return await repo.fetchTaxSettings(restaurantId);
    } catch (_) {}
  }

  return const RestaurantTaxSettings(
    taxName: 'GST',
    gstRateBasisPoints: 500,
    taxIsInclusive: false,
    serviceChargeBasisPoints: 0,
    serviceChargeName: 'Service Charge',
    currency: 'INR',
  );
});

final orderPaymentsProvider =
    FutureProvider.family<List<PaymentRecord>, String>((ref, orderId) async {
      final backend = ref.watch(backendProvider);
      final repo = ref.watch(paymentRepositoryProvider);
      final auth = ref.watch(authControllerProvider);
      final restaurantId = auth.activeMembership?.restaurantId;

      if (backend.status == BackendStatus.initialized &&
          restaurantId != null &&
          repo is SupabasePaymentRepository) {
        try {
          final sub = repo
              .watchPaymentInvalidations(restaurantId: restaurantId)
              .listen((_) {
                ref.invalidateSelf();
              });
          ref.onDispose(sub.cancel);

          return await repo.fetchPaymentsForOrder(
            restaurantId: restaurantId,
            orderId: orderId,
          );
        } catch (_) {}
      }

      return const [];
    });

class ReportDateRange {
  const ReportDateRange({required this.startDate, required this.endDate});
  final DateTime startDate;
  final DateTime endDate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportDateRange &&
          other.startDate == startDate &&
          other.endDate == endDate;

  @override
  int get hashCode => Object.hash(startDate, endDate);
}

final financialReportProvider =
    FutureProvider.family<FinancialReport, ReportDateRange?>((
      ref,
      range,
    ) async {
      final backend = ref.watch(backendProvider);
      final repo = ref.watch(paymentRepositoryProvider);
      final auth = ref.watch(authControllerProvider);
      final restaurantId = auth.activeMembership?.restaurantId;

      if (backend.status == BackendStatus.initialized &&
          restaurantId != null &&
          repo is SupabasePaymentRepository) {
        try {
          final sub = repo
              .watchPaymentInvalidations(restaurantId: restaurantId)
              .listen((_) {
                ref.invalidateSelf();
              });
          ref.onDispose(sub.cancel);

          return await repo.fetchFinancialReport(
            restaurantId: restaurantId,
            startDate: range?.startDate,
            endDate: range?.endDate,
          );
        } catch (_) {}
      }

      final start = range?.startDate ?? DateTime(2025, 1, 1);
      final end = range?.endDate ?? DateTime.now();

      // Demo fallback
      return FinancialReport(
        startDate: start,
        endDate: end,
        grossSalesMinor: 258000,
        netSalesMinor: 242000,
        discountsTotalMinor: 16000,
        taxCollectedMinor: 12100,
        serviceChargeMinor: 0,
        totalPaymentsMinor: 242000,
        cashCollectedMinor: 110000,
        upiCollectedMinor: 82000,
        cardCollectedMinor: 50000,
        otherCollectedMinor: 0,
        refundsTotalMinor: 0,
        netCollectedMinor: 242000,
        outstandingBalanceMinor: 0,
        totalOrdersCount: 8,
        paidOrdersCount: 8,
        unpaidOrdersCount: 0,
      );
    });
