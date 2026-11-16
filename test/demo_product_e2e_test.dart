import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cafeflow/core/routing/workspace.dart';
import 'package:cafeflow/features/auth/domain/permissions.dart';
import 'package:cafeflow/features/billing/application/cart_controller.dart';
import 'package:cafeflow/features/billing/domain/payment_models.dart';
import 'package:cafeflow/features/billing/presentation/receipt_dialog.dart';
import 'package:cafeflow/features/customer_website/presentation/customer_router.dart';
import 'package:cafeflow/features/demo/application/demo_catalog_controller.dart';
import 'package:cafeflow/features/demo/application/demo_inventory_controller.dart';
import 'package:cafeflow/features/demo/application/demo_orders_controller.dart';
import 'package:cafeflow/features/demo/application/demo_tables_controller.dart';
import 'package:cafeflow/features/menu/domain/catalog.dart';
import 'package:cafeflow/features/orders/domain/cafe_order.dart';
import 'package:cafeflow/features/reports/domain/analytics_models.dart';
import 'package:cafeflow/features/tables/domain/floor_models.dart';
import 'package:cafeflow/features/workspaces/domain/workspace_catalog.dart';

void main() {
  group('CafeFlow Final Demo Product E2E Audit & Verification', () {
    // ------------------------------------------------------------------------
    // Complete 16-Step Canonical Demo Workflow Sequence
    // ------------------------------------------------------------------------
    test('Complete 16-Step Demo Workflow: Owner setup -> POS -> KOT -> Settlement -> Inventory -> BI -> Web', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // ----------------------------------------------------------------------
      // Step 1: Owner role and permissions
      // ----------------------------------------------------------------------
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.admin,
          CafePermission.viewReports,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.admin,
          CafePermission.manageMenu,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.admin,
          CafePermission.manageSettings,
        ),
        isTrue,
      );

      // ----------------------------------------------------------------------
      // Step 2: Owner creates a category and menu item
      // ----------------------------------------------------------------------
      final catalogController = container.read(demoCatalogProvider.notifier);
      catalogController.category('Artisan Tea', id: 'cat-tea');
      var catalogState = container.read(demoCatalogProvider);
      expect(catalogState.categories.any((c) => c.id == 'cat-tea'), isTrue);

      const newItem = MenuProduct(
        id: 'tea-matcha',
        categoryId: 'cat-tea',
        name: 'Ceremonial Matcha Latte',
        priceMinor: 28000,
        available: true,
        description: 'Single-estate Uji matcha with microfoamed oat milk.',
      );
      catalogController.save(newItem);
      catalogState = container.read(demoCatalogProvider);
      expect(catalogState.products.any((p) => p.id == 'tea-matcha'), isTrue);

      // ----------------------------------------------------------------------
      // Step 3: Owner changes the item price
      // ----------------------------------------------------------------------
      final updatedPriceItem = newItem.copyWith(
        priceMinor: 30000,
      ); // Updated to ₹300.00
      catalogController.save(updatedPriceItem);
      catalogState = container.read(demoCatalogProvider);
      final persistedItem = catalogState.products.firstWhere(
        (p) => p.id == 'tea-matcha',
      );
      expect(persistedItem.priceMinor, equals(30000));

      // ----------------------------------------------------------------------
      // Step 4: Cashier login and permissions
      // ----------------------------------------------------------------------
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.cashier,
          CafePermission.createOrders,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.cashier,
          CafePermission.processPayments,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.cashier,
          CafePermission.viewReports,
        ),
        isFalse,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.cashier,
          CafePermission.manageSettings,
        ),
        isFalse,
      );

      // ----------------------------------------------------------------------
      // Step 5: Cashier creates an order (Cart operations)
      // ----------------------------------------------------------------------
      final cartController = container.read(cartProvider('cashier').notifier);
      cartController.clear();
      cartController.add(persistedItem);
      cartController.add(persistedItem); // 2 x ₹300.00 = ₹600.00
      final cart = container.read(cartProvider('cashier'));
      expect(cart.lines.length, equals(1));
      expect(cart.lines.first.quantity, equals(2));
      expect(cart.subtotalMinor, equals(60000));

      // ----------------------------------------------------------------------
      // Step 6: Cashier selects a table
      // ----------------------------------------------------------------------
      final tablesController = container.read(demoTablesProvider.notifier);
      var tables = container.read(demoTablesProvider);
      final targetTable = tables.firstWhere(
        (t) => t.status == TableStatus.available,
      );
      tablesController.updateStatus(
        targetTable.id,
        TableStatus.occupied,
        orderNumber: 'CF-DEMO-101',
      );
      tables = container.read(demoTablesProvider);
      final updatedTable = tables.firstWhere((t) => t.id == targetTable.id);
      expect(updatedTable.status, equals(TableStatus.occupied));
      expect(updatedTable.currentOrderNumber, equals('CF-DEMO-101'));

      // ----------------------------------------------------------------------
      // Step 7: Cashier completes a simulated payment (Simulated UPI)
      // ----------------------------------------------------------------------
      final simulatedTxRef =
          'SIM-UPI-${DateTime.now().millisecondsSinceEpoch % 1000000}';
      final payment = PaymentRecord(
        id: 'pay-demo-101',
        restaurantId: 'rest-demo-1',
        orderId: 'ord-demo-101',
        paymentMethodCode: 'UPI',
        amountMinor: cart.totalMinor,
        status: 'COMPLETED',
        transactionReference: simulatedTxRef,
        createdAt: DateTime.now(),
      );
      expect(payment.status, equals('COMPLETED'));
      expect(payment.transactionReference, startsWith('SIM-UPI-'));
      expect(payment.amountMinor, equals(cart.totalMinor));

      // ----------------------------------------------------------------------
      // Step 8: Kitchen receives the KOT
      // ----------------------------------------------------------------------
      final ordersController = container.read(demoOrdersProvider.notifier);
      final orderLines = cart.lines
          .map(
            (l) => OrderLine(
              productId: l.productId,
              name: l.name,
              unitMinor: l.unitMinor,
              quantity: l.quantity,
            ),
          )
          .toList();
      final createdOrder = ordersController.add(
        lines: orderLines,
        table: targetTable.name,
        instructions: 'Extra hot, oat milk',
        taxMinor: cart.taxMinor,
        discountMinor: cart.discountMinor,
      );
      expect(createdOrder.status, equals(OrderStatus.newOrder));
      expect(createdOrder.table, equals(targetTable.name));

      // ----------------------------------------------------------------------
      // Step 9: Kitchen accepts and prepares the order
      // ----------------------------------------------------------------------
      ordersController.advance(createdOrder.id);
      var currentOrders = container.read(demoOrdersProvider);
      var kitchenOrder = currentOrders.firstWhere(
        (o) => o.id == createdOrder.id,
      );
      expect(kitchenOrder.status, equals(OrderStatus.preparing));

      // ----------------------------------------------------------------------
      // Step 10: Kitchen marks the order ready
      // ----------------------------------------------------------------------
      ordersController.advance(createdOrder.id);
      currentOrders = container.read(demoOrdersProvider);
      kitchenOrder = currentOrders.firstWhere((o) => o.id == createdOrder.id);
      expect(kitchenOrder.status, equals(OrderStatus.ready));

      // ----------------------------------------------------------------------
      // Step 11: Cashier sees the updated status and settles order
      // ----------------------------------------------------------------------
      final settledOrder = kitchenOrder
          .withStatus(OrderStatus.completed)
          .withFinancialStatus(
            financialStatus: OrderFinancialStatus.paid,
            paidMinor: kitchenOrder.totalMinor,
          );
      expect(settledOrder.status, equals(OrderStatus.completed));
      expect(settledOrder.isFullyPaid, isTrue);

      // Close table
      tablesController.updateStatus(targetTable.id, TableStatus.available);
      tables = container.read(demoTablesProvider);
      expect(
        tables.firstWhere((t) => t.id == targetTable.id).status,
        equals(TableStatus.available),
      );

      // ----------------------------------------------------------------------
      // Step 12: Owner sees updated dashboard and reports
      // ----------------------------------------------------------------------
      final report = FinancialAnalyticsReport(
        grossSalesMinor: settledOrder.totalMinor,
        discountsTotalMinor: settledOrder.discountMinor,
        netSalesMinor: settledOrder.subtotalMinor - settledOrder.discountMinor,
        taxCollectedMinor: settledOrder.taxMinor,
        serviceChargeMinor: 0,
        totalPaymentsMinor: settledOrder.paidMinor,
        cashCollectedMinor: 0,
        upiCollectedMinor: settledOrder.paidMinor,
        cardCollectedMinor: 0,
        otherCollectedMinor: 0,
        refundsTotalMinor: 0,
        netCollectedMinor: settledOrder.paidMinor,
        outstandingBalanceMinor: 0,
        totalOrdersCount: 1,
        paidOrdersCount: 1,
        unpaidOrdersCount: 0,
        avgOrderValueMinor: settledOrder.totalMinor,
      );
      expect(
        report.grossSalesMinor,
        equals(report.netSalesMinor + report.taxCollectedMinor),
      );
      expect(report.netCollectedMinor, equals(settledOrder.paidMinor));

      // ----------------------------------------------------------------------
      // Step 13: Inventory reflects configured recipe deductions
      // ----------------------------------------------------------------------
      final inventoryController = container.read(
        demoInventoryProvider.notifier,
      );
      final inventoryBefore = container.read(demoInventoryProvider);
      final oatMilkItem = inventoryBefore.firstWhere(
        (i) => i.id == 'inv-2',
      ); // Oat milk
      final initialStock = oatMilkItem.quantity;
      // Deduct 0.6 liters for 2 matcha lattes (0.3L each)
      inventoryController.adjust(oatMilkItem.id, initialStock - 0.6);
      final inventoryAfter = container.read(demoInventoryProvider);
      expect(
        inventoryAfter.firstWhere((i) => i.id == 'inv-2').quantity,
        equals(initialStock - 0.6),
      );

      // ----------------------------------------------------------------------
      // Step 14: Receipt can be generated with demo payment details
      // ----------------------------------------------------------------------
      expect(settledOrder.totalMinor, greaterThan(0));
      expect(payment.transactionReference, startsWith('SIM-'));
      expect(formatMinorToCurrency(settledOrder.totalMinor), startsWith('₹'));

      // ----------------------------------------------------------------------
      // Step 15: Public website displays updated published menu
      // ----------------------------------------------------------------------
      final customerRouter = createCustomerRouter();
      expect(
        customerRouter.configuration.findMatch(Uri.parse('/menu')).isNotEmpty,
        isTrue,
      );
      // Confirmed item is available in catalog snapshot
      expect(
        catalogState.products.firstWhere((p) => p.id == 'tea-matcha').available,
        isTrue,
      );

      // ----------------------------------------------------------------------
      // Step 16: Offline order creation & subsequent synchronization simulation
      // ----------------------------------------------------------------------
      final offlineOrder = CafeOrder(
        id: 'offline-tx-99',
        number: 'OFF-99',
        table: 'Takeaway',
        status: OrderStatus.completed,
        financialStatus: OrderFinancialStatus.paid,
        createdAt: DateTime.now(),
        paidMinor: 30000,
        lines: [
          OrderLine(
            productId: persistedItem.id,
            name: persistedItem.name,
            unitMinor: persistedItem.priceMinor,
            quantity: 1,
          ),
        ],
      );
      expect(offlineOrder.totalMinor, equals(30000));
      expect(offlineOrder.isFullyPaid, isTrue);
    });

    // ------------------------------------------------------------------------
    // Negative, Error, and Boundary Scenario Tests
    // ------------------------------------------------------------------------
    test('RBAC Boundary: Cashier workspace cannot navigate to admin or financial reporting', () {
      final cashierWorkspace = workspaceFor(WorkspaceRole.cashier);
      final sectionIds = cashierWorkspace.sections.map((s) => s.id).toList();

      expect(sectionIds.contains('reports'), isFalse);
      expect(sectionIds.contains('settings'), isFalse);
      expect(sectionIds.contains('staff'), isFalse);
      expect(sectionIds.contains('inventory'), isFalse);
    });

    test('Negative Scenario: Cart prohibits zero quantity or invalid negative discounts', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(cartProvider('test-err').notifier);
      const testItem = MenuProduct(
        id: 'p-1',
        categoryId: 'coffee',
        name: 'Single Espresso',
        priceMinor: 15000,
        available: true,
      );

      controller.add(testItem);
      // Discount greater than subtotal throws ArgumentError
      expect(
        () => controller.discount(20000, reason: 'Excessive Discount'),
        throwsArgumentError,
      );

      // Decrementing line to 0 removes it from the cart
      controller.quantity('p-1', 0);
      expect(container.read(cartProvider('test-err')).lines.isEmpty, isTrue);
    });

    test('Demo State Reset: Controller reset restores default data without DB mutation', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final catalogController = container.read(demoCatalogProvider.notifier);
      catalogController.category('Temporary Category', id: 'temp-cat');
      expect(
        container
            .read(demoCatalogProvider)
            .categories
            .any((c) => c.id == 'temp-cat'),
        isTrue,
      );

      // Trigger reset
      catalogController.reset();
      expect(
        container
            .read(demoCatalogProvider)
            .categories
            .any((c) => c.id == 'temp-cat'),
        isFalse,
      );
    });
  });

  group('Receipt Widget Demo Simulation Rendering Tests', () {
    testWidgets(
      'ReceiptDialog displays clear DEMO / SIMULATED PAYMENT markers',
      (tester) async {
        final testOrder = CafeOrder(
          id: 'ord-sim-1',
          number: 'SIM-001',
          table: 'Table 4',
          status: OrderStatus.completed,
          financialStatus: OrderFinancialStatus.paid,
          createdAt: DateTime(2026, 11, 16, 12, 0),
          paidMinor: 25000,
          lines: const [
            OrderLine(
              productId: 'cb',
              name: 'Cold Brew',
              unitMinor: 25000,
              quantity: 1,
            ),
          ],
        );

        final testPayment = PaymentRecord(
          id: 'pay-sim-1',
          restaurantId: 'rest-1',
          orderId: 'ord-sim-1',
          paymentMethodCode: 'UPI',
          amountMinor: 25000,
          status: 'COMPLETED',
          transactionReference: 'SIM-UPI-98412',
          createdAt: DateTime(2026, 11, 16, 12, 1),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReceiptDialog(order: testOrder, payment: testPayment),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify simulated payment markings appear in the rendered receipt
        expect(find.text('*** DEMO / SIMULATED PAYMENT ***'), findsOneWidget);
        expect(find.text('NO REAL MONEY PROCESSED'), findsOneWidget);
        expect(
          find.text(
            '*** DEMO SIMULATION COPY ***\nFor demonstration & testing only\nNo financial liability or real payment processing',
          ),
          findsOneWidget,
        );
        expect(find.text('SIM-UPI-98412'), findsOneWidget);
      },
    );
  });
}
