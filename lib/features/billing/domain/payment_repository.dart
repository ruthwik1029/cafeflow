import 'payment_models.dart';

abstract interface class PaymentRepository {
  Future<List<PaymentMethodRecord>> fetchPaymentMethods(String restaurantId);

  Future<void> updatePaymentMethodStatus({
    required String restaurantId,
    required String code,
    required bool isActive,
  });

  Future<PaymentResult> recordPayment({
    required String restaurantId,
    required String orderId,
    required String paymentMethodCode,
    required int amountMinor,
    int? tenderedAmountMinor,
    String? transactionReference,
    String notes = '',
    String? idempotencyKey,
  });

  Future<RefundResult> refundPayment({
    required String restaurantId,
    required String orderId,
    required String paymentId,
    required int refundAmountMinor,
    required String reason,
    String? idempotencyKey,
  });

  Future<List<PaymentRecord>> fetchPaymentsForOrder({
    required String restaurantId,
    required String orderId,
  });

  Future<FinancialReport> fetchFinancialReport({
    required String restaurantId,
    DateTime? startDate,
    DateTime? endDate,
  });

  Future<RestaurantTaxSettings> fetchTaxSettings(String restaurantId);

  Future<void> updateTaxSettings({
    required String restaurantId,
    required String taxName,
    required int gstRateBasisPoints,
    required bool taxIsInclusive,
    required int serviceChargeBasisPoints,
    required String serviceChargeName,
  });

  Stream<void> watchPaymentInvalidations({String? restaurantId});
}
