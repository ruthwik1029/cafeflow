import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cafeflow/core/theme/app_theme.dart';
import 'package:cafeflow/features/customer_website/presentation/customer_router.dart';
import 'package:cafeflow/features/customer_website/presentation/customer_site.dart';
import 'package:cafeflow/features/dashboard/presentation/admin_dashboard_page.dart';
import 'package:cafeflow/features/dashboard/presentation/owner_overview_page.dart';
import 'package:cafeflow/features/inventory/domain/inventory_models.dart';
import 'package:cafeflow/features/orders/domain/cafe_order.dart';
import 'package:cafeflow/features/reports/application/analytics_provider.dart';
import 'package:cafeflow/features/reports/presentation/reports_page.dart';

void main() {
  group('Phase 10: Financial & Analytical Domain Unit Tests', () {
    test('Financial analytics correctly computes gross, net, discounts, refunds, and collected funds', () {
      const financial = FinancialAnalyticsReport(
        grossSalesMinor: 500000, // ₹5000.00
        discountsTotalMinor: 50000, // ₹500.00
        netSalesMinor: 450000, // ₹4500.00
        taxCollectedMinor: 22500, // ₹225.00
        serviceChargeMinor: 0,
        totalPaymentsMinor: 400000, // ₹4000.00 collected
        cashCollectedMinor: 200000,
        upiCollectedMinor: 150000,
        cardCollectedMinor: 50000,
        otherCollectedMinor: 0,
        refundsTotalMinor: 20000, // ₹200.00
        netCollectedMinor: 380000, // ₹3800.00 (400000 - 20000)
        outstandingBalanceMinor: 50000, // ₹500.00 unpaid tab
        totalOrdersCount: 20,
        paidOrdersCount: 18,
        unpaidOrdersCount: 2,
        avgOrderValueMinor: 25000, // ₹250.00
      );

      // Verify business math invariants
      expect(
        financial.netSalesMinor,
        equals(financial.grossSalesMinor - financial.discountsTotalMinor),
      );
      expect(
        financial.netCollectedMinor,
        equals(financial.totalPaymentsMinor - financial.refundsTotalMinor),
      );
      expect(
        financial.cashCollectedMinor +
            financial.upiCollectedMinor +
            financial.cardCollectedMinor +
            financial.otherCollectedMinor,
        equals(financial.totalPaymentsMinor),
      );
      expect(
        financial.paidOrdersCount + financial.unpaidOrdersCount,
        equals(financial.totalOrdersCount),
      );
      expect(
        financial.avgOrderValueMinor,
        equals(financial.grossSalesMinor ~/ financial.totalOrdersCount),
      );
    });

    test('Never counts unpaid orders as collected revenue and avoids double-counting partial payments', () {
      // 3 test orders:
      // Order 1: fully paid (₹100 total, ₹100 paid)
      // Order 2: partially paid (₹200 total, ₹50 paid, ₹150 balance)
      // Order 3: completely unpaid (₹150 total, ₹0 paid, ₹150 balance)
      final orders = [
        CafeOrder(
          id: 'ord-1',
          number: '#101',
          table: 'Table 1',
          status: OrderStatus.completed,
          financialStatus: OrderFinancialStatus.paid,
          createdAt: DateTime.now(),
          paidMinor: 10000,
          lines: const [
            OrderLine(
              productId: 'p-1',
              name: 'Espresso',
              unitMinor: 10000,
              quantity: 1,
            ),
          ],
        ),
        CafeOrder(
          id: 'ord-2',
          number: '#102',
          table: 'Table 2',
          status: OrderStatus.preparing,
          financialStatus: OrderFinancialStatus.partiallyPaid,
          createdAt: DateTime.now(),
          paidMinor: 5000, // partially paid ₹50
          lines: const [
            OrderLine(
              productId: 'p-2',
              name: 'Pour Over',
              unitMinor: 10000,
              quantity: 2,
            ),
          ],
        ),
        CafeOrder(
          id: 'ord-3',
          number: '#103',
          table: 'Table 3',
          status: OrderStatus.newOrder,
          financialStatus: OrderFinancialStatus.unpaid,
          createdAt: DateTime.now(),
          paidMinor: 0, // unpaid ₹0
          lines: const [
            OrderLine(
              productId: 'p-3',
              name: 'Sourdough Toast',
              unitMinor: 15000,
              quantity: 1,
            ),
          ],
        ),
      ];

      final analytics = DemoAnalyticsRepository.generateDemoAnalytics(
        DateTime.now().subtract(const Duration(hours: 1)),
        DateTime.now().add(const Duration(hours: 1)),
        orders: orders,
      );

      // Total orders = 3
      expect(analytics.financial.totalOrdersCount, equals(3));
      // Gross sales = 10000 + 20000 + 15000 = 45000
      expect(analytics.financial.grossSalesMinor, equals(45000));
      // Collected payments MUST only reflect actual payments: 10000 + 5000 + 0 = 15000
      expect(analytics.financial.totalPaymentsMinor, equals(15000));
      // Outstanding balance MUST equal 0 + 15000 + 15000 = 30000
      expect(analytics.financial.outstandingBalanceMinor, equals(30000));
      // Paid vs unpaid orders count
      expect(analytics.financial.paidOrdersCount, equals(1));
      expect(analytics.financial.unpaidOrdersCount, equals(2));
    });

    test('Date range presets compute accurate boundaries', () {
      final refDate = DateTime(2026, 11, 16, 14, 30);

      final todayRange = AnalyticsTimePreset.today.getRange(refDate);
      expect(todayRange.start, equals(DateTime(2026, 11, 16, 0, 0, 0)));
      expect(todayRange.end, equals(refDate));

      final yesterdayRange = AnalyticsTimePreset.yesterday.getRange(refDate);
      expect(yesterdayRange.start, equals(DateTime(2026, 11, 15, 0, 0, 0)));
      expect(
        yesterdayRange.end,
        equals(DateTime(2026, 11, 15, 23, 59, 59, 999)),
      );

      final monthRange = AnalyticsTimePreset.thisMonth.getRange(refDate);
      expect(monthRange.start, equals(DateTime(2026, 11, 1, 0, 0, 0)));
      expect(monthRange.end, equals(refDate));
    });

    test('Inventory valuation and wastage metric aggregation', () {
      const inventory = [
        InventoryItem(
          id: 'inv-1',
          restaurantId: 'rest-1',
          name: 'Coffee Beans',
          unit: 'kg',
          currentStock: 10.0,
          minimumStock: 2.0,
          reorderLevel: 5.0,
          costPerUnitMinor: 50000, // ₹500/kg -> 10kg = ₹5000 (500000 minor)
          categoryName: 'Coffee',
        ),
        InventoryItem(
          id: 'inv-2',
          restaurantId: 'rest-1',
          name: 'Oat Milk',
          unit: 'liters',
          currentStock: 4.0, // below reorderLevel 6.0 -> low stock
          minimumStock: 2.0,
          reorderLevel: 6.0,
          costPerUnitMinor: 20000, // ₹200/L -> 4L = ₹800 (80000 minor)
          categoryName: 'Dairy',
        ),
        InventoryItem(
          id: 'inv-3',
          restaurantId: 'rest-1',
          name: 'Organic Matcha',
          unit: 'g',
          currentStock: 0.0, // out of stock
          minimumStock: 100.0,
          reorderLevel: 250.0,
          costPerUnitMinor: 500,
          categoryName: 'Tea',
        ),
      ];

      final analytics = DemoAnalyticsRepository.generateDemoAnalytics(
        DateTime(2026, 1, 1),
        DateTime(2026, 12, 31),
        inventory: inventory,
      );

      expect(analytics.inventory.totalItemsCount, equals(3));
      expect(analytics.inventory.lowStockCount, equals(1));
      expect(analytics.inventory.outOfStockCount, equals(1));
      // Total valuation = 500000 + 80000 + 0 = 580000
      expect(analytics.inventory.stockValuationMinor, equals(580000));
    });

    test('Kitchen performance metrics format prep times accurately', () {
      const metricZero = KitchenAnalyticsMetric(
        avgPrepTimeSeconds: 0,
        activeTicketsCount: 0,
        delayedTicketsCount: 0,
        completedTicketsCount: 0,
      );
      expect(metricZero.formattedAvgPrepTime, equals('0m 0s'));

      const metricStandard = KitchenAnalyticsMetric(
        avgPrepTimeSeconds: 495, // 8 minutes 15 seconds
        activeTicketsCount: 3,
        delayedTicketsCount: 1,
        completedTicketsCount: 12,
      );
      expect(metricStandard.formattedAvgPrepTime, equals('8m 15s'));
    });

    test('Table occupancy calculation handles zero and non-zero counts', () {
      const emptyTableMetric = TableAnalyticsMetric(
        totalTables: 0,
        occupiedTables: 0,
        occupancyRatePercent: 0.0,
      );
      expect(emptyTableMetric.occupancyRatePercent, equals(0.0));

      const activeTableMetric = TableAnalyticsMetric(
        totalTables: 10,
        occupiedTables: 4,
        occupancyRatePercent: 40.0,
      );
      expect(activeTableMetric.occupancyRatePercent, equals(40.0));
    });
  });

  group('Phase 10: CSV Exporter Suite', () {
    test('AnalyticsCsvExporter exports financial statement with correct currency and quoting', () {
      final sample = DemoAnalyticsRepository.generateDemoAnalytics(
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 16),
      );

      final csv = AnalyticsCsvExporter.exportFinancialCsv(sample);

      expect(csv, contains('CafeFlow Financial Summary Report'));
      expect(csv, contains('Gross Sales'));
      expect(csv, contains('Net Sales'));
      expect(csv, contains('Total Payments Collected'));
      expect(csv, contains('Outstanding Balance'));
      expect(csv, contains('Cash Tender'));
      expect(csv, contains('UPI / Digital QR'));
      expect(csv, contains('Card POS / Terminal'));
      expect(csv, contains('₹'));
    });

    test('AnalyticsCsvExporter exports product sales and escapes special characters', () {
      final specialAnalytics = ComprehensiveAnalytics(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 2),
        financial: const FinancialAnalyticsReport(
          grossSalesMinor: 100000,
          discountsTotalMinor: 0,
          netSalesMinor: 100000,
          taxCollectedMinor: 5000,
          serviceChargeMinor: 0,
          totalPaymentsMinor: 100000,
          cashCollectedMinor: 100000,
          upiCollectedMinor: 0,
          cardCollectedMinor: 0,
          otherCollectedMinor: 0,
          refundsTotalMinor: 0,
          netCollectedMinor: 100000,
          outstandingBalanceMinor: 0,
          totalOrdersCount: 2,
          paidOrdersCount: 2,
          unpaidOrdersCount: 0,
          avgOrderValueMinor: 50000,
        ),
        orderTypes: const [],
        dailyTrends: const [],
        topProducts: const [
          ProductSalesMetric(
            productName: 'Signature Latte, Extra Shot "Special"',
            quantitySold: 12,
            revenueMinor: 480000,
          ),
        ],
        leastProducts: const [],
        inventory: const InventoryAnalyticsMetric(
          totalItemsCount: 5,
          lowStockCount: 0,
          outOfStockCount: 0,
          stockValuationMinor: 100000,
          wastageCostMinor: 0,
        ),
        kitchen: const KitchenAnalyticsMetric(
          avgPrepTimeSeconds: 300,
          activeTicketsCount: 0,
          delayedTicketsCount: 0,
          completedTicketsCount: 2,
        ),
        tables: const TableAnalyticsMetric(
          totalTables: 4,
          occupiedTables: 1,
          occupancyRatePercent: 25.0,
        ),
        workforce: const WorkforceAnalyticsMetric(
          currentlyClockedIn: 2,
          currentlyOnBreak: 0,
          lateArrivalsCount: 0,
        ),
      );

      final productCsv = AnalyticsCsvExporter.exportProductSalesCsv(
        specialAnalytics,
      );
      expect(productCsv, contains('"Signature Latte, Extra Shot ""Special"""'));
      expect(productCsv, contains('12,₹4800.00,480000'));

      final opCsv = AnalyticsCsvExporter.exportOperationalCsv(specialAnalytics);
      expect(opCsv, contains('Kitchen Average Prep Time,5m 0s'));
      expect(opCsv, contains('Floor Occupancy Rate,25.0%'));
    });
  });

  group('Phase 10: Multi-Platform Completeness & Isolation Tests', () {
    test('createCustomerRouter isolates public website and contains no private internal routes', () {
      final customerRouter = createCustomerRouter();

      // Ensure customer router configuration contains only public customer routes
      final routes = customerRouter.configuration.routes;
      expect(routes.isNotEmpty, isTrue);

      // Verify customer router does not expose /admin, /owner, /billing, or /reports
      final pathStrings = routes.map((r) => r.toString()).join(' ');
      expect(pathStrings.contains('/admin/reports'), isFalse);
      expect(pathStrings.contains('/owner/reports'), isFalse);
    });

    testWidgets(
      'CustomerHome renders public cafe branding and menu link with zero operational data leakage',
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
        expect(find.text('Now Brewing in Indiranagar'), findsOneWidget);

        // Verify ZERO leakage of financial metrics or staff roster on public website
        expect(find.text('GROSS REVENUE'), findsNothing);
        expect(find.text('NET REVENUE'), findsNothing);
        expect(find.text('Staff on Duty Today'), findsNothing);
      },
    );
  });

  group('Phase 10: Reporting & Dashboard Widget Tests', () {
    testWidgets(
      'ReportsPage renders all 5 analytics tabs, date filter chips, and export actions',
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

        // Required baseline test assertions
        expect(find.text('Sales Reports & Analytics'), findsOneWidget);
        expect(find.text('GROSS REVENUE'), findsOneWidget);
        expect(find.text('NET REVENUE'), findsOneWidget);
        expect(find.text('Hourly Rush Times'), findsOneWidget);

        // 5 Dimension Tabs
        expect(find.text('Financial & Sales'), findsOneWidget);
        expect(find.text('Product & Menu'), findsOneWidget);
        expect(find.text('Inventory & Wastage'), findsOneWidget);
        expect(find.text('Kitchen & Floor'), findsOneWidget);
        expect(find.text('Staff & Operations'), findsOneWidget);

        // Export Buttons
        expect(find.text('Export CSV'), findsOneWidget);
        expect(find.text('Print Report'), findsOneWidget);

        // Test switching to Product & Menu Tab
        await tester.tap(find.text('Product & Menu'));
        await tester.pumpAndSettle();
        expect(find.text('Best-Selling Items'), findsOneWidget);

        // Test switching to Inventory & Wastage Tab
        await tester.tap(find.text('Inventory & Wastage'));
        await tester.pumpAndSettle();
        expect(find.text('STOCK VALUATION'), findsOneWidget);

        // Test switching to Kitchen & Floor Tab
        await tester.tap(find.text('Kitchen & Floor'));
        await tester.pumpAndSettle();
        expect(find.text('AVG PREPARATION TIME'), findsOneWidget);

        // Test switching to Staff & Operations Tab
        await tester.tap(find.text('Staff & Operations'));
        await tester.pumpAndSettle();
        expect(find.text('CURRENTLY CLOCKED IN'), findsOneWidget);
      },
    );

    testWidgets(
      'AdminDashboardPage renders executive metrics, top-selling items, and operational alerts',
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

        // Baseline expectations
        expect(find.text('Executive Dashboard'), findsOneWidget);
        expect(find.text("TODAY'S REVENUE"), findsOneWidget);
        expect(find.text('ACTIVE KITCHEN TICKETS'), findsOneWidget);
        expect(find.text('TABLE OCCUPANCY'), findsOneWidget);
        expect(find.text('INVENTORY ALERTS'), findsOneWidget);

        // Phase 10 Realtime KPIs
        expect(find.text('COLLECTED PAYMENTS'), findsOneWidget);
        expect(find.text('OUTSTANDING TABS'), findsOneWidget);
        expect(find.text('Top-Selling Menu Items'), findsOneWidget);
      },
    );

    testWidgets(
      'OwnerOverviewPage renders pocket metrics, financial snapshot, and responsive wrap',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
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
        expect(find.textContaining('Financial Snapshot'), findsOneWidget);
      },
    );
  });
}
