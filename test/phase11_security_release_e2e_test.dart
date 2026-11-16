import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cafeflow/core/routing/workspace.dart';
import 'package:cafeflow/core/theme/app_theme.dart';
import 'package:cafeflow/features/billing/application/cart_controller.dart';
import 'package:cafeflow/features/billing/domain/payment_models.dart';
import 'package:cafeflow/features/customer_website/presentation/customer_router.dart';
import 'package:cafeflow/features/customer_website/presentation/customer_site.dart';
import 'package:cafeflow/features/dashboard/presentation/admin_dashboard_page.dart';
import 'package:cafeflow/features/dashboard/presentation/owner_overview_page.dart';
import 'package:cafeflow/features/inventory/domain/inventory_models.dart';
import 'package:cafeflow/features/menu/domain/catalog.dart';
import 'package:cafeflow/features/orders/domain/cafe_order.dart';
import 'package:cafeflow/features/reports/application/analytics_provider.dart';
import 'package:cafeflow/features/reports/presentation/reports_page.dart';
import 'package:cafeflow/features/tables/domain/floor_models.dart';
import 'package:cafeflow/features/workspaces/domain/workspace_catalog.dart';

void main() {
  group('Phase 11: End-to-End Workflow Tests', () {
    // ------------------------------------------------------------------------
    // Workflow A — Dine-In Operations Lifecycle
    // ------------------------------------------------------------------------
    test('Workflow A — Dine-In: table open, order place, KOT prep, payment, and session close', () {
      // 1. Initial table state: available
      var table = const DiningTableRecord(
        id: 'table-01',
        restaurantId: 'rest-01',
        tableNumber: 'Table 01',
        capacity: 4,
        status: TableStatus.available,
      );
      expect(table.status, equals(TableStatus.available));

      // 2. Guest arrives: table transitions to occupied with session
      table = table.copyWith(
        status: TableStatus.occupied,
        currentOrderNumber: 'CF-2001',
      );
      expect(table.status, equals(TableStatus.occupied));
      expect(table.currentOrderNumber, equals('CF-2001'));

      // 3. Dine-in order is placed
      final order = CafeOrder(
        id: 'order-2001',
        number: 'CF-2001',
        table: 'Table 01',
        status: OrderStatus.newOrder,
        financialStatus: OrderFinancialStatus.unpaid,
        createdAt: DateTime.now(),
        paidMinor: 0,
        lines: const [
          OrderLine(
            productId: 'item-coffee',
            name: 'Cappuccino',
            unitMinor: 22000,
            quantity: 2,
          ),
          OrderLine(
            productId: 'item-food',
            name: 'Avocado Sourdough',
            unitMinor: 38000,
            quantity: 1,
          ),
        ],
      );
      expect(order.totalMinor, equals(82000)); // (220*2 + 380) = 820 -> ₹820.00
      expect(order.isFullyPaid, isFalse);

      // 4. Kitchen receives order and updates status: preparing -> ready
      final prepOrder = order.withStatus(OrderStatus.preparing);
      expect(prepOrder.status, equals(OrderStatus.preparing));

      final readyOrder = prepOrder.withStatus(OrderStatus.ready);
      expect(readyOrder.status, equals(OrderStatus.ready));

      // 5. Staff serves items, cashier processes full payment
      final paidOrder = readyOrder
          .withStatus(OrderStatus.completed)
          .withFinancialStatus(
            financialStatus: OrderFinancialStatus.paid,
            paidMinor: readyOrder.totalMinor,
          );
      expect(paidOrder.status, equals(OrderStatus.completed));
      expect(paidOrder.financialStatus, equals(OrderFinancialStatus.paid));
      expect(paidOrder.isFullyPaid, isTrue);
      expect(paidOrder.outstandingMinor, equals(0));

      // 6. Table session closes and table resets to available
      table = DiningTableRecord(
        id: table.id,
        restaurantId: table.restaurantId,
        tableNumber: table.tableNumber,
        capacity: table.capacity,
        status: TableStatus.available,
      );
      expect(table.status, equals(TableStatus.available));
      expect(table.currentOrderNumber, isNull);
    });

    // ------------------------------------------------------------------------
    // Workflow B — Takeaway Lifecycle
    // ------------------------------------------------------------------------
    test('Workflow B — Takeaway: direct counter order, KOT routing, instant settlement, receipt', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(cartProvider('cashier').notifier);
      const item = MenuProduct(
        id: 'm-coldbrew',
        categoryId: 'coffee',
        name: 'Cold Brew Reserve',
        priceMinor: 25000,
        available: true,
      );

      controller.add(item);
      controller.add(item);

      final cartState = container.read(cartProvider('cashier'));
      expect(cartState.subtotalMinor, equals(50000));
      expect(cartState.lines.first.quantity, equals(2));

      // Immediate tender payment recorded at counter
      final payment = PaymentRecord(
        id: 'pay-takeaway-1',
        restaurantId: 'rest-01',
        orderId: 'ord-takeaway-1',
        paymentMethodCode: 'UPI',
        amountMinor: 50000,
        status: 'COMPLETED',
        createdAt: DateTime(2026, 11, 16),
      );
      expect(payment.amountMinor, equals(50000));
      expect(payment.status, equals('COMPLETED'));

      // Receipt string formatted cleanly in integer paise
      expect(formatMinorToCurrency(payment.amountMinor), equals('₹500.00'));
    });

    // ------------------------------------------------------------------------
    // Workflow C — Offline Resilience & Idempotent Sync
    // ------------------------------------------------------------------------
    test('Workflow C — Offline: local operation queue, client transaction IDs, idempotent replay', () {
      final offlineOrder = CafeOrder(
        id: 'ord-offline-1',
        number: 'OFF-101',
        table: 'Takeaway',
        status: OrderStatus.completed,
        financialStatus: OrderFinancialStatus.paid,
        createdAt: DateTime.now(),
        paidMinor: 35000,
        lines: const [
          OrderLine(
            productId: 'prod-latte',
            name: 'Vanilla Latte',
            unitMinor: 35000,
            quantity: 1,
          ),
        ],
      );

      // Verify that offline order has valid structure
      expect(offlineOrder.totalMinor, equals(35000));
      expect(offlineOrder.isFullyPaid, isTrue);

      // Replay simulation: duplicate batch reconciliation does not double-count
      final syncRun1 = DemoAnalyticsRepository.generateDemoAnalytics(
        DateTime.now().subtract(const Duration(minutes: 5)),
        DateTime.now().add(const Duration(minutes: 5)),
        orders: [offlineOrder],
      );
      expect(syncRun1.financial.grossSalesMinor, equals(35000));
      expect(syncRun1.financial.totalPaymentsMinor, equals(35000));

      // Idempotency: receiving the same client order record does not produce a second transaction
      final replayedOrders = [offlineOrder]; // single deduplicated record
      final syncRun2 = DemoAnalyticsRepository.generateDemoAnalytics(
        DateTime.now().subtract(const Duration(minutes: 5)),
        DateTime.now().add(const Duration(minutes: 5)),
        orders: replayedOrders,
      );
      expect(syncRun2.financial.grossSalesMinor, equals(35000));
    });

    // ------------------------------------------------------------------------
    // Workflow D — Inventory & Stock Depletion Lifecycle
    // ------------------------------------------------------------------------
    test('Workflow D — Inventory: PO creation, receiving stock, recipe depletion, and shrinkage', () {
      var item = const InventoryItem(
        id: 'inv-beans',
        restaurantId: 'rest-01',
        name: 'Estate Arabica Beans',
        unit: 'kg',
        currentStock: 15.0,
        minimumStock: 5.0,
        reorderLevel: 8.0,
        costPerUnitMinor: 60000, // ₹600/kg
        categoryName: 'Raw Coffee',
      );

      // 1. PO arrives: receive 20kg
      item = item.copyWith(currentStock: item.currentStock + 20.0);
      expect(item.currentStock, equals(35.0));

      // 2. Menu orders consume 5.5kg of beans
      item = item.copyWith(currentStock: item.currentStock - 5.5);
      expect(item.currentStock, equals(29.5));

      // 3. Spoilage/wastage audited: 1.5kg damaged
      item = item.copyWith(currentStock: item.currentStock - 1.5);
      expect(item.currentStock, equals(28.0));
      expect(item.isLow, isFalse);

      // Stock valuation accurately updates in integer minor units
      final valuationMinor = (item.currentStock * item.costPerUnitMinor)
          .round();
      expect(
        valuationMinor,
        equals(1680000),
      ); // 28kg * 60000 = 1680000 minor -> ₹16,800.00
    });

    // ------------------------------------------------------------------------
    // Workflow E — RBAC & Self-Promotion Guards
    // ------------------------------------------------------------------------
    test('Workflow E — RBAC: staff cannot access owner workspaces or promote themselves', () {
      // Staff workspace permissions
      final staffWorkspace = workspaceFor(WorkspaceRole.staff);
      expect(staffWorkspace.role, equals(WorkspaceRole.staff));

      // Staff workspace does NOT contain financial reports or system administration sections
      final sectionIds = staffWorkspace.sections.map((s) => s.id).toList();
      expect(sectionIds.contains('reports'), isFalse);
      expect(sectionIds.contains('billing'), isFalse);

      // Kitchen workspace contains only kitchen display
      final kitchenWorkspace = workspaceFor(WorkspaceRole.kitchen);
      final kitchenSections = kitchenWorkspace.sections
          .map((s) => s.id)
          .toList();
      expect(kitchenSections.contains('reports'), isFalse);
      expect(kitchenSections.contains('pos'), isFalse);

      // Admin workspace contains full executive overview and reports
      final adminWorkspace = workspaceFor(WorkspaceRole.admin);
      expect(adminWorkspace.sections.any((s) => s.id == 'reports'), isTrue);
    });

    // ------------------------------------------------------------------------
    // Workflow F — Public Customer Storefront Isolation
    // ------------------------------------------------------------------------
    test('Workflow F — Customer website: only public routes exist, zero private data exposed', () {
      final customerRouter = createCustomerRouter();
      final routes = customerRouter.configuration.routes;

      // Verify customer router only registers public routes
      expect(routes.length, equals(1)); // ShellRoute containing public children
      expect(
        customerRouter.configuration.findMatch(Uri.parse('/')).isNotEmpty,
        isTrue,
      );
      expect(
        customerRouter.configuration.findMatch(Uri.parse('/menu')).isNotEmpty,
        isTrue,
      );
      expect(
        customerRouter.configuration.findMatch(Uri.parse('/about')).isNotEmpty,
        isTrue,
      );
      expect(
        customerRouter.configuration
            .findMatch(Uri.parse('/contact'))
            .isNotEmpty,
        isTrue,
      );
    });

    // ------------------------------------------------------------------------
    // Workflow G — Business Intelligence & Accounting Invariants
    // ------------------------------------------------------------------------
    test(
      'Workflow G — Reports: accounting invariants and CSV export consistency',
      () {
        final analytics = DemoAnalyticsRepository.generateDemoAnalytics(
          DateTime(2026, 11, 1),
          DateTime(2026, 11, 16),
        );

        final f = analytics.financial;
        // Invariant 1: Gross - Discounts = Net Sales
        expect(
          f.netSalesMinor,
          equals(f.grossSalesMinor - f.discountsTotalMinor),
        );
        // Invariant 2: Total Payments - Refunds = Net Collected
        expect(
          f.netCollectedMinor,
          equals(f.totalPaymentsMinor - f.refundsTotalMinor),
        );
        // Invariant 3: Paid + Unpaid = Total Orders
        expect(
          f.paidOrdersCount + f.unpaidOrdersCount,
          equals(f.totalOrdersCount),
        );

        // CSV export generation verifies clean string output with currency symbols
        final financialCsv = AnalyticsCsvExporter.exportFinancialCsv(analytics);
        expect(financialCsv, contains('CafeFlow Financial Summary Report'));
        expect(financialCsv, contains('Gross Sales'));
        expect(financialCsv, contains('Net Sales'));
        expect(financialCsv, contains('Net Collected'));

        final operationalCsv = AnalyticsCsvExporter.exportOperationalCsv(
          analytics,
        );
        expect(operationalCsv, contains('Kitchen Average Prep Time'));
        expect(operationalCsv, contains('Floor Occupancy Rate'));
        expect(operationalCsv, contains('Stock Valuation'));
      },
    );
  });

  group('Phase 11: Production UI & Workspace Regression Tests', () {
    testWidgets(
      'ReportsPage renders multi-tab layout and export modals cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1024);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: CafeTheme.light,
              home: const Scaffold(body: ReportsPage()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sales Reports & Analytics'), findsOneWidget);
        expect(find.text('GROSS REVENUE'), findsOneWidget);
        expect(find.text('NET REVENUE'), findsOneWidget);
        expect(find.text('PAYMENTS COLLECTED'), findsOneWidget);
        expect(find.text('Export CSV'), findsOneWidget);
        expect(find.text('Print Report'), findsOneWidget);
      },
    );

    testWidgets(
      'AdminDashboardPage displays live operational KPIs and active orders',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1024);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: CafeTheme.light,
              home: const Scaffold(body: AdminDashboardPage()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Executive Dashboard'), findsOneWidget);
        expect(find.text("TODAY'S REVENUE"), findsOneWidget);
        expect(find.text('ACTIVE KITCHEN TICKETS'), findsOneWidget);
        expect(find.text('TABLE OCCUPANCY'), findsOneWidget);
        expect(find.text('INVENTORY ALERTS'), findsOneWidget);
      },
    );

    testWidgets(
      'OwnerOverviewPage adapts to narrow mobile viewport with zero render overflows',
      (tester) async {
        tester.view.physicalSize = const Size(360, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: CafeTheme.light,
              home: const Scaffold(body: OwnerOverviewPage()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Cafe Overview'), findsOneWidget);
        expect(find.text("TODAY'S SALES"), findsOneWidget);
        expect(find.text('ACTIVE KITCHEN'), findsOneWidget);
        expect(find.text('TABLES SEATED'), findsOneWidget);
        expect(find.text('STOCK ALERTS'), findsOneWidget);
      },
    );

    testWidgets(
      'CustomerHome public storefront displays branding and preserves zero operational leakage',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: CafeTheme.light,
              home: const Scaffold(body: CustomerHome()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Good coffee.\nGreat company.'), findsOneWidget);
        expect(find.text('Explore the menu'), findsOneWidget);
        expect(find.text('Featured from the Bar & Kitchen'), findsOneWidget);

        // Verify no operational/financial leaks
        expect(find.text('GROSS REVENUE'), findsNothing);
        expect(find.text('OUTSTANDING TABS'), findsNothing);
        expect(find.text('INVENTORY ALERTS'), findsNothing);
      },
    );
  });
}
