import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../menu/domain/catalog.dart';
import '../../orders/domain/cafe_order.dart';

class CartState {
  CartState({
    List<OrderLine> lines = const [],
    this.discountMinor = 0,
    this.discountReason = '',
    this.taxBasisPoints = 500,
    this.taxName = 'GST',
    this.taxIsInclusive = false,
    this.serviceChargeBasisPoints = 0,
    this.serviceChargeName = 'Service Charge',
    this.paymentMethod = 'Cash',
  }) : lines = List.unmodifiable(lines);

  final List<OrderLine> lines;
  final int discountMinor;
  final String discountReason;
  final int taxBasisPoints;
  final String taxName;
  final bool taxIsInclusive;
  final int serviceChargeBasisPoints;
  final String serviceChargeName;
  final String paymentMethod;

  int get subtotalMinor =>
      lines.fold(0, (value, line) => value + line.totalMinor);

  int get taxableMinor =>
      (subtotalMinor - discountMinor).clamp(0, subtotalMinor);

  int get taxMinor {
    if (taxBasisPoints <= 0 || taxableMinor <= 0) return 0;
    if (taxIsInclusive) {
      // Extracted from gross price
      return (taxableMinor * taxBasisPoints) ~/ (10000 + taxBasisPoints);
    }
    // Added on top
    return (taxableMinor * taxBasisPoints + 5000) ~/ 10000;
  }

  int get serviceChargeMinor {
    if (serviceChargeBasisPoints <= 0 || taxableMinor <= 0) return 0;
    return (taxableMinor * serviceChargeBasisPoints + 5000) ~/ 10000;
  }

  int get totalMinor {
    if (taxIsInclusive) {
      return taxableMinor + serviceChargeMinor;
    }
    return taxableMinor + taxMinor + serviceChargeMinor;
  }

  CartState copyWith({
    List<OrderLine>? lines,
    int? discountMinor,
    String? discountReason,
    int? taxBasisPoints,
    String? taxName,
    bool? taxIsInclusive,
    int? serviceChargeBasisPoints,
    String? serviceChargeName,
    String? paymentMethod,
  }) {
    return CartState(
      lines: lines ?? this.lines,
      discountMinor: discountMinor ?? this.discountMinor,
      discountReason: discountReason ?? this.discountReason,
      taxBasisPoints: taxBasisPoints ?? this.taxBasisPoints,
      taxName: taxName ?? this.taxName,
      taxIsInclusive: taxIsInclusive ?? this.taxIsInclusive,
      serviceChargeBasisPoints:
          serviceChargeBasisPoints ?? this.serviceChargeBasisPoints,
      serviceChargeName: serviceChargeName ?? this.serviceChargeName,
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
  }
}

final cartProvider = NotifierProvider.family<CartController, CartState, String>(
  CartController.new,
);

class CartController extends Notifier<CartState> {
  CartController(this.workspace);
  final String workspace;

  @override
  CartState build() => CartState();

  void add(MenuProduct product) {
    if (!product.available || product.archived) {
      throw StateError('This item is unavailable.');
    }
    final existing = state.lines
        .where((l) => l.productId == product.id)
        .firstOrNull;
    if (existing != null) {
      quantity(product.id, existing.quantity + 1);
      return;
    }
    _lines([
      ...state.lines,
      OrderLine(
        productId: product.id,
        name: product.name,
        unitMinor: product.priceMinor,
        quantity: 1,
      ),
    ]);
  }

  void quantity(String id, int value) {
    if (value < 0 || value > 99) {
      throw ArgumentError('Quantity must be between 0 and 99.');
    }
    _lines([
      for (final line in state.lines)
        if (line.productId != id)
          line
        else if (value > 0)
          OrderLine(
            productId: id,
            name: line.name,
            unitMinor: line.unitMinor,
            quantity: value,
          ),
    ]);
  }

  void _lines(List<OrderLine> lines) {
    final subtotal = lines.fold(0, (sum, line) => sum + line.totalMinor);
    state = state.copyWith(
      lines: lines,
      discountMinor: state.discountMinor.clamp(0, subtotal),
    );
  }

  void discount(int value, {String reason = ''}) {
    if (value < 0 || value > state.subtotalMinor) {
      throw ArgumentError('Discount must not exceed the subtotal.');
    }
    state = state.copyWith(discountMinor: value, discountReason: reason.trim());
  }

  void discountPercentage(double percent, {String reason = ''}) {
    if (percent < 0 || percent > 100) {
      throw ArgumentError('Discount percentage must be between 0 and 100.');
    }
    final discountMinor = (state.subtotalMinor * percent / 100).round();
    discount(discountMinor, reason: reason);
  }

  void configureTax({
    int? taxBps,
    String? taxName,
    bool? isInclusive,
    int? serviceChargeBps,
    String? serviceChargeName,
  }) {
    state = state.copyWith(
      taxBasisPoints: taxBps ?? state.taxBasisPoints,
      taxName: taxName ?? state.taxName,
      taxIsInclusive: isInclusive ?? state.taxIsInclusive,
      serviceChargeBasisPoints:
          serviceChargeBps ?? state.serviceChargeBasisPoints,
      serviceChargeName: serviceChargeName ?? state.serviceChargeName,
    );
  }

  void payment(String method) {
    final normalized = method.trim();
    if (!['Cash', 'Card', 'UPI', 'CASH', 'CARD', 'UPI'].contains(normalized)) {
      throw ArgumentError('Unknown payment method.');
    }
    state = state.copyWith(paymentMethod: normalized);
  }

  void clear() => state = CartState(
    taxBasisPoints: state.taxBasisPoints,
    taxName: state.taxName,
    taxIsInclusive: state.taxIsInclusive,
    serviceChargeBasisPoints: state.serviceChargeBasisPoints,
    serviceChargeName: state.serviceChargeName,
    paymentMethod: state.paymentMethod,
  );
}
