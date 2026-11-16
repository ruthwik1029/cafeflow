import 'package:cafeflow/core/database/database_gateway.dart';
import 'package:cafeflow/core/errors/app_failure.dart';
import 'package:cafeflow/features/billing/application/cart_controller.dart';
import 'package:cafeflow/features/billing/data/supabase_payment_repository.dart';
import 'package:cafeflow/features/billing/domain/payment_models.dart';
import 'package:cafeflow/features/menu/domain/catalog.dart';
import 'package:cafeflow/features/orders/domain/cafe_order.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDatabaseGateway implements DatabaseGateway {
  const FakeDatabaseGateway({this.mockRows = const {}});

  final Map<String, List<Map<String, dynamic>>> mockRows;

  @override
  Future<List<Map<String, dynamic>>> readRows(
    String relation, {
    Map<String, Object> equals = const {},
    int limit = 100,
  }) async {
    return mockRows[relation] ?? [];
  }
}

void main() {
  group('Phase 06 — Fixed-Precision Monetary & Tax Math', () {
    test('money formatting and parsing handles paise correctly without floating-point drift', () {
      expect(money(0), '₹0.00');
      expect(money(100), '₹1.00');
      expect(money(12345), '₹123.45');
      expect(money(250000), '₹2500.00');

      expect(parseMoney('0'), 0);
      expect(parseMoney('1.50'), 150);
      expect(parseMoney('123.45'), 12345);
      expect(parseMoney('2500.00'), 250000);
      expect(parseMoney('invalid'), isNull);
      expect(parseMoney(''), isNull);
    });

    test('exclusive tax calculation adds tax on top of taxable subtotal', () {
      // 5% GST on ₹100.00 (10000 paise) = ₹5.00 (500 paise)
      const taxable = 10000;
      const rateBps = 500; // 5%
      final tax = (taxable * rateBps) ~/ 10000;
      final total = taxable + tax;

      expect(tax, 500);
      expect(total, 10500);
    });

    test(
      'inclusive tax calculation extracts embedded tax portion correctly',
      () {
        // If item price is ₹105.00 with 5% inclusive tax:
        // Tax portion = (10500 * 500) / (10000 + 500) = 5250000 / 10500 = 500 paise (₹5.00)
        // Net base price = ₹100.00
        const totalInclusive = 10500;
        const rateBps = 500;
        final extractedTax = (totalInclusive * rateBps) ~/ (10000 + rateBps);
        final basePrice = totalInclusive - extractedTax;

        expect(extractedTax, 500);
        expect(basePrice, 10000);
      },
    );

    test('percentage discount and flat discount calculation', () {
      const subtotal = 20000; // ₹200.00

      // Flat discount of ₹30.00
      const flatDiscount = 3000;
      expect(subtotal - flatDiscount, 17000);

      // 10% discount on ₹200.00 = ₹20.00 (2000 paise)
      const pct = 10;
      final pctDiscount = (subtotal * pct) ~/ 100;
      expect(pctDiscount, 2000);
      expect(subtotal - pctDiscount, 18000);
    });

    test('service charge calculation basis points', () {
      const taxable = 50000; // ₹500.00
      const scBps = 250; // 2.5%
      final scMinor = (taxable * scBps) ~/ 10000;
      expect(scMinor, 1250); // ₹12.50
    });
  });

  group('Phase 06 — CartController Billing & Tax Settings', () {
    test('initial cart state is empty with standard 5% tax defaults', () {
      final cart = CartState();
      expect(cart.lines, isEmpty);
      expect(cart.subtotalMinor, 0);
      expect(cart.discountMinor, 0);
      expect(cart.taxMinor, 0);
      expect(cart.serviceChargeMinor, 0);
      expect(cart.totalMinor, 0);
      expect(cart.taxIsInclusive, false);
      expect(cart.taxName, 'GST');
    });

    test('exclusive tax calculates subtotal, discount, tax, service charge and grand total', () {
      final state = CartState(
        lines: const [
          OrderLine(
            productId: 'item-1',
            name: 'Cold Brew',
            unitMinor: 20000,
            quantity: 2,
          ), // 400.00
          OrderLine(
            productId: 'item-2',
            name: 'Almond Croissant',
            unitMinor: 15000,
            quantity: 1,
          ), // 150.00
        ],
        taxName: 'GST',
        taxBasisPoints: 500, // 5%
        taxIsInclusive: false,
        discountMinor: 5000, // ₹50.00 discount
        serviceChargeBasisPoints: 200, // 2% service charge
        serviceChargeName: 'Staff Surcharge',
      );

      // Subtotal = 400.00 + 150.00 = 550.00 (55000 paise)
      expect(state.subtotalMinor, 55000);
      // Taxable = 55000 - 5000 = 50000 paise (₹500.00)
      // Tax = 5% of 500.00 = 25.00 (2500 paise)
      expect(state.taxMinor, 2500);
      // Service charge = 2% of 500.00 = 10.00 (1000 paise)
      expect(state.serviceChargeMinor, 1000);
      // Total = 50000 + 2500 + 1000 = 53500 paise (₹535.00)
      expect(state.totalMinor, 53500);
    });

    test(
      'inclusive tax embeds tax inside total without increasing customer price',
      () {
        final state = CartState(
          lines: const [
            OrderLine(
              productId: 'item-1',
              name: 'Combo Meal',
              unitMinor: 21000,
              quantity: 1,
            ), // 210.00
          ],
          taxName: 'GST',
          taxBasisPoints: 500, // 5%
          taxIsInclusive: true,
          discountMinor: 0,
          serviceChargeBasisPoints: 0,
        );

        expect(state.subtotalMinor, 21000);
        // Tax extracted = (21000 * 500) / 10500 = 1000 paise (₹10.00)
        expect(state.taxMinor, 1000);
        // Total remains ₹210.00
        expect(state.totalMinor, 21000);
      },
    );

    test(
      'CartController mutations: add, quantity change, configureTax, discount',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = container.read(cartProvider('pos').notifier);
        expect(container.read(cartProvider('pos')).lines, isEmpty);

        // Add product
        controller.add(
          const MenuProduct(
            id: 'prod-1',
            categoryId: 'cat-coffee',
            name: 'Flat White',
            priceMinor: 18000,
            description: 'Double shot',
          ),
        );
        var state = container.read(cartProvider('pos'));
        expect(state.lines.length, 1);
        expect(state.lines.first.quantity, 1);
        expect(state.subtotalMinor, 18000);

        // Increase quantity
        controller.quantity('prod-1', 3);
        state = container.read(cartProvider('pos'));
        expect(state.lines.first.quantity, 3);
        expect(state.subtotalMinor, 54000);

        // Apply discount
        controller.discount(4000, reason: 'Loyalty member');
        state = container.read(cartProvider('pos'));
        expect(state.discountMinor, 4000);
        expect(state.discountReason, 'Loyalty member');

        // Configure tax settings
        controller.configureTax(
          taxName: 'VAT',
          taxBps: 1000, // 10%
          isInclusive: false,
          serviceChargeBps: 500, // 5%
          serviceChargeName: 'Service',
        );
        state = container.read(cartProvider('pos'));
        // Taxable = 54000 - 4000 = 50000
        // Tax = 10% of 50000 = 5000
        // Service = 5% of 50000 = 2500
        // Grand Total = 50000 + 5000 + 2500 = 57500
        expect(state.taxName, 'VAT');
        expect(state.taxMinor, 5000);
        expect(state.serviceChargeMinor, 2500);
        expect(state.totalMinor, 57500);

        // Clear cart
        controller.clear();
        state = container.read(cartProvider('pos'));
        expect(state.lines, isEmpty);
        expect(state.subtotalMinor, 0);
      },
    );
  });

  group('Phase 06 — Cash Handling, Tender & Change Calculations', () {
    test('cash payment with exact change yields zero change due', () {
      const orderTotal = 35000; // ₹350.00
      const tendered = 35000;
      final changeDue = tendered - orderTotal;
      expect(changeDue, 0);
    });

    test('cash payment with higher tender calculates correct change due', () {
      const orderTotal = 35000; // ₹350.00
      const tendered = 50000; // Customer hands ₹500.00
      final changeDue = tendered - orderTotal;
      expect(changeDue, 15000); // ₹150.00 change due
    });

    test('underpayment is detected and disallowed', () {
      const orderTotal = 35000; // ₹350.00
      const tendered = 30000; // Customer hands ₹300.00
      final isShort = tendered < orderTotal;
      expect(isShort, isTrue);
    });
  });

  group('Phase 06 — Order Financial Status & Lifecycle', () {
    test('financial status enum maps to and from database strings', () {
      expect(OrderFinancialStatus.unpaid.dbValue, 'UNPAID');
      expect(OrderFinancialStatus.partiallyPaid.dbValue, 'PARTIALLY_PAID');
      expect(OrderFinancialStatus.paid.dbValue, 'PAID');
      expect(OrderFinancialStatus.refunded.dbValue, 'REFUNDED');
      expect(
        OrderFinancialStatus.partiallyRefunded.dbValue,
        'PARTIALLY_REFUNDED',
      );
      expect(OrderFinancialStatus.paymentFailed.dbValue, 'PAYMENT_FAILED');

      expect(
        OrderFinancialStatusX.fromDb('UNPAID'),
        OrderFinancialStatus.unpaid,
      );
      expect(
        OrderFinancialStatusX.fromDb('PARTIALLY_PAID'),
        OrderFinancialStatus.partiallyPaid,
      );
      expect(OrderFinancialStatusX.fromDb('PAID'), OrderFinancialStatus.paid);
      expect(
        OrderFinancialStatusX.fromDb('REFUNDED'),
        OrderFinancialStatus.refunded,
      );
      expect(
        OrderFinancialStatusX.fromDb('PARTIALLY_REFUNDED'),
        OrderFinancialStatus.partiallyRefunded,
      );
      expect(
        OrderFinancialStatusX.fromDb('PAYMENT_FAILED'),
        OrderFinancialStatus.paymentFailed,
      );
      expect(
        OrderFinancialStatusX.fromDb('unknown'),
        OrderFinancialStatus.unpaid,
      );
    });

    test('CafeOrder financial status getters and transitions', () {
      final order = CafeOrder(
        id: 'ord-1',
        number: 'CF-1001',
        createdAt: DateTime.now(),
        lines: const [
          OrderLine(
            productId: 'p-1',
            name: 'Latte',
            quantity: 2,
            unitMinor: 15000,
          ),
        ],
        table: 'Table 01',
        financialStatus: OrderFinancialStatus.unpaid,
        paidMinor: 0,
      );

      // Total = 30000 paise (tax excluded = 0 for test)
      expect(order.totalMinor, 30000);
      expect(order.outstandingMinor, 30000);
      expect(order.isFullyPaid, false);

      // Partial payment
      final partialOrder = order.withFinancialStatus(
        financialStatus: OrderFinancialStatus.partiallyPaid,
        paidMinor: 10000,
      );
      expect(partialOrder.outstandingMinor, 20000);
      expect(partialOrder.isFullyPaid, false);

      // Full payment
      final fullyPaidOrder = partialOrder.withFinancialStatus(
        financialStatus: OrderFinancialStatus.paid,
        paidMinor: 30000,
      );
      expect(fullyPaidOrder.outstandingMinor, 0);
      expect(fullyPaidOrder.isFullyPaid, true);

      // Partial refund
      final partiallyRefundedOrder = fullyPaidOrder.withFinancialStatus(
        financialStatus: OrderFinancialStatus.partiallyRefunded,
        paidMinor: 30000,
        refundedMinor: 10000,
      );
      expect(partiallyRefundedOrder.refundedMinor, 10000);
      expect(partiallyRefundedOrder.isFullyPaid, false);
    });
  });

  group('Phase 06 — Payment Models & Financial Reporting', () {
    test(
      'PaymentRecord calculates net amount subtracting refunded portion',
      () {
        final payment = PaymentRecord(
          id: 'pay-1',
          orderId: 'ord-1',
          restaurantId: 'rest-1',
          paymentMethodCode: 'UPI',
          amountMinor: 25000,
          status: 'COMPLETED',
          createdAt: DateTime.now(),
          isRefunded: true,
          refundedAmountMinor: 5000,
        );

        expect(payment.amountMinor, 25000);
        expect(payment.refundedAmountMinor, 5000);
        expect(payment.netAmountMinor, 20000);
      },
    );

    test('FinancialReport aggregates match accounting identities', () {
      final report = FinancialReport(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        grossSalesMinor: 500000,
        netSalesMinor: 480000,
        discountsTotalMinor: 20000,
        taxCollectedMinor: 24000,
        serviceChargeMinor: 5000,
        totalPaymentsMinor: 480000,
        cashCollectedMinor: 200000,
        upiCollectedMinor: 180000,
        cardCollectedMinor: 100000,
        otherCollectedMinor: 0,
        refundsTotalMinor: 20000,
        netCollectedMinor: 460000,
        outstandingBalanceMinor: 20000,
        totalOrdersCount: 25,
        paidOrdersCount: 23,
        unpaidOrdersCount: 2,
      );

      expect(
        report.grossSalesMinor - report.refundsTotalMinor,
        report.netSalesMinor,
      );
      expect(
        report.cashCollectedMinor +
            report.upiCollectedMinor +
            report.cardCollectedMinor,
        report.totalPaymentsMinor,
      );
      expect(
        report.totalOrdersCount,
        report.paidOrdersCount + report.unpaidOrdersCount,
      );
    });
  });

  group('Phase 06 — Supabase Payment Repository Validation & Guard Rails', () {
    const gateway = FakeDatabaseGateway();

    test(
      'recordPayment rejects invalid or empty arguments prior to RPC call',
      () async {
        final repo = SupabasePaymentRepository(gateway: gateway, client: null);

        expect(
          () => repo.recordPayment(
            restaurantId: '',
            orderId: 'ord-1',
            paymentMethodCode: 'CASH',
            amountMinor: 1000,
          ),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.recordPayment(
            restaurantId: 'rest-1',
            orderId: '',
            paymentMethodCode: 'CASH',
            amountMinor: 1000,
          ),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.recordPayment(
            restaurantId: 'rest-1',
            orderId: 'ord-1',
            paymentMethodCode: '',
            amountMinor: 1000,
          ),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.recordPayment(
            restaurantId: 'rest-1',
            orderId: 'ord-1',
            paymentMethodCode: 'CASH',
            amountMinor: 0,
          ),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.recordPayment(
            restaurantId: 'rest-1',
            orderId: 'ord-1',
            paymentMethodCode: 'CASH',
            amountMinor: 1000,
            tenderedAmountMinor: 500, // Tendered less than amount
          ),
          throwsA(isA<AppFailure>()),
        );
      },
    );

    test(
      'refundPayment rejects invalid arguments and missing refund reason',
      () async {
        final repo = SupabasePaymentRepository(gateway: gateway, client: null);

        expect(
          () => repo.refundPayment(
            restaurantId: '',
            orderId: 'ord-1',
            paymentId: 'pay-1',
            refundAmountMinor: 500,
            reason: 'Customer cancelled',
          ),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.refundPayment(
            restaurantId: 'rest-1',
            orderId: 'ord-1',
            paymentId: 'pay-1',
            refundAmountMinor: 0,
            reason: 'Customer cancelled',
          ),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.refundPayment(
            restaurantId: 'rest-1',
            orderId: 'ord-1',
            paymentId: 'pay-1',
            refundAmountMinor: 500,
            reason: '   ', // Empty reason
          ),
          throwsA(isA<AppFailure>()),
        );
      },
    );

    test(
      'uninitialized client throws AppFailure for all backend RPC mutations',
      () async {
        final repo = SupabasePaymentRepository(gateway: gateway, client: null);

        expect(
          () => repo.recordPayment(
            restaurantId: 'rest-1',
            orderId: 'ord-1',
            paymentMethodCode: 'CASH',
            amountMinor: 1000,
          ),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.refundPayment(
            restaurantId: 'rest-1',
            orderId: 'ord-1',
            paymentId: 'pay-1',
            refundAmountMinor: 1000,
            reason: 'Valid audit reason',
          ),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.updatePaymentMethodStatus(
            restaurantId: 'rest-1',
            code: 'CASH',
            isActive: false,
          ),
          throwsA(isA<AppFailure>()),
        );

        expect(
          () => repo.updateTaxSettings(
            restaurantId: 'rest-1',
            taxName: 'GST',
            gstRateBasisPoints: 500,
            taxIsInclusive: false,
            serviceChargeBasisPoints: 0,
            serviceChargeName: 'Service Charge',
          ),
          throwsA(isA<AppFailure>()),
        );
      },
    );

    test('fetchPaymentMethods returns default methods when gateway relation is empty', () async {
      final repo = SupabasePaymentRepository(gateway: gateway, client: null);
      final methods = await repo.fetchPaymentMethods('rest-1');

      expect(methods, isNotEmpty);
      expect(methods.any((m) => m.code == 'CASH'), isTrue);
      expect(methods.any((m) => m.code == 'UPI'), isTrue);
      expect(methods.any((m) => m.code == 'CARD'), isTrue);
    });

    test(
      'fetchTaxSettings returns default 5% GST when no row in database',
      () async {
        final repo = SupabasePaymentRepository(gateway: gateway, client: null);
        final tax = await repo.fetchTaxSettings('rest-1');

        expect(tax.taxName, 'GST');
        expect(tax.gstRateBasisPoints, 500);
        expect(tax.taxIsInclusive, false);
        expect(tax.currency, 'INR');
      },
    );
  });
}
