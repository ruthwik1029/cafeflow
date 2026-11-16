import '../../orders/domain/cafe_order.dart';

/// Models an active payment method available in the cafe (e.g. CASH, UPI, CARD).
class PaymentMethodRecord {
  const PaymentMethodRecord({
    required this.id,
    required this.restaurantId,
    required this.code,
    required this.displayName,
    required this.isActive,
  });

  final String id;
  final String restaurantId;
  final String code;
  final String displayName;
  final bool isActive;

  PaymentMethodRecord copyWith({bool? isActive}) {
    return PaymentMethodRecord(
      id: id,
      restaurantId: restaurantId,
      code: code,
      displayName: displayName,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Models a recorded payment transaction.
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.orderId,
    required this.restaurantId,
    required this.paymentMethodCode,
    required this.amountMinor,
    required this.status,
    required this.createdAt,
    this.tenderedAmountMinor,
    this.changeDueMinor = 0,
    this.transactionReference,
    this.notes = '',
    this.processedBy,
    this.processedAt,
    this.isRefunded = false,
    this.refundedAmountMinor = 0,
  });

  final String id;
  final String orderId;
  final String restaurantId;
  final String paymentMethodCode;
  final int amountMinor;
  final String status;
  final DateTime createdAt;
  final int? tenderedAmountMinor;
  final int changeDueMinor;
  final String? transactionReference;
  final String notes;
  final String? processedBy;
  final DateTime? processedAt;
  final bool isRefunded;
  final int refundedAmountMinor;

  int get netAmountMinor => amountMinor - refundedAmountMinor;
}

/// Models an authorized refund against a payment.
class RefundRecord {
  const RefundRecord({
    required this.id,
    required this.restaurantId,
    required this.orderId,
    required this.paymentId,
    required this.amountMinor,
    required this.reason,
    required this.refundedAt,
    this.refundedBy,
  });

  final String id;
  final String restaurantId;
  final String orderId;
  final String paymentId;
  final int amountMinor;
  final String reason;
  final DateTime refundedAt;
  final String? refundedBy;
}

/// Result returned from recording a payment.
class PaymentResult {
  const PaymentResult({
    required this.paymentId,
    required this.orderId,
    required this.amountMinor,
    required this.changeDueMinor,
    required this.financialStatus,
    required this.paidAmountMinor,
    required this.totalMinor,
    required this.remainingMinor,
    this.isReplay = false,
  });

  final String paymentId;
  final String orderId;
  final int amountMinor;
  final int changeDueMinor;
  final OrderFinancialStatus financialStatus;
  final int paidAmountMinor;
  final int totalMinor;
  final int remainingMinor;
  final bool isReplay;
}

/// Result returned from processing a refund.
class RefundResult {
  const RefundResult({
    required this.refundId,
    required this.paymentId,
    required this.orderId,
    required this.refundAmountMinor,
    required this.newFinancialStatus,
    required this.orderTotalRefundedMinor,
    this.isReplay = false,
  });

  final String refundId;
  final String paymentId;
  final String orderId;
  final int refundAmountMinor;
  final OrderFinancialStatus newFinancialStatus;
  final int orderTotalRefundedMinor;
  final bool isReplay;
}

/// Aggregated financial metrics for Owner / Admin reporting.
class FinancialReport {
  const FinancialReport({
    required this.startDate,
    required this.endDate,
    required this.grossSalesMinor,
    required this.netSalesMinor,
    required this.discountsTotalMinor,
    required this.taxCollectedMinor,
    required this.serviceChargeMinor,
    required this.totalPaymentsMinor,
    required this.cashCollectedMinor,
    required this.upiCollectedMinor,
    required this.cardCollectedMinor,
    required this.otherCollectedMinor,
    required this.refundsTotalMinor,
    required this.netCollectedMinor,
    required this.outstandingBalanceMinor,
    required this.totalOrdersCount,
    required this.paidOrdersCount,
    required this.unpaidOrdersCount,
  });

  final DateTime startDate;
  final DateTime endDate;
  final int grossSalesMinor;
  final int netSalesMinor;
  final int discountsTotalMinor;
  final int taxCollectedMinor;
  final int serviceChargeMinor;
  final int totalPaymentsMinor;
  final int cashCollectedMinor;
  final int upiCollectedMinor;
  final int cardCollectedMinor;
  final int otherCollectedMinor;
  final int refundsTotalMinor;
  final int netCollectedMinor;
  final int outstandingBalanceMinor;
  final int totalOrdersCount;
  final int paidOrdersCount;
  final int unpaidOrdersCount;
}

/// Configurable restaurant tax settings.
class RestaurantTaxSettings {
  const RestaurantTaxSettings({
    this.taxName = 'GST',
    this.gstRateBasisPoints = 500,
    this.taxIsInclusive = false,
    this.serviceChargeBasisPoints = 0,
    this.serviceChargeName = 'Service Charge',
    this.currency = 'INR',
  });

  final String taxName;
  final int gstRateBasisPoints;
  final bool taxIsInclusive;
  final int serviceChargeBasisPoints;
  final String serviceChargeName;
  final String currency;

  double get gstPercentage => gstRateBasisPoints / 100.0;
  double get serviceChargePercentage => serviceChargeBasisPoints / 100.0;
}
