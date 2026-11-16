import 'package:cafeflow/core/theme/app_theme.dart';
import 'package:cafeflow/features/billing/presentation/pos_page.dart';
import 'package:cafeflow/features/customer_website/presentation/customer_site.dart';
import 'package:cafeflow/features/customers/presentation/customers_page.dart';
import 'package:cafeflow/features/dashboard/presentation/admin_dashboard_page.dart';
import 'package:cafeflow/features/inventory/presentation/inventory_page.dart';
import 'package:cafeflow/features/menu/presentation/menu_management_page.dart';
import 'package:cafeflow/features/orders/presentation/orders_page.dart';
import 'package:cafeflow/features/reports/presentation/reports_page.dart';
import 'package:cafeflow/features/settings/presentation/settings_page.dart';
import 'package:cafeflow/features/staff/presentation/staff_page.dart';
import 'package:cafeflow/features/tables/presentation/tables_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {Size size = const Size(1200, 900)}) {
  return ProviderScope(
    child: MaterialApp(
      theme: CafeTheme.light,
      home: SizedBox(
        width: size.width,
        height: size.height,
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
}

void main() {
  group('Phase 02 Workspaces Widget Tests', () {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.physicalSize = const Size(
        1200,
        900,
      );
      binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });
    testWidgets('AdminDashboardPage renders metrics and operational cards', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const AdminDashboardPage()));
      await tester.pumpAndSettle();

      expect(find.text('Executive Dashboard'), findsOneWidget);
      expect(find.text("TODAY'S REVENUE"), findsOneWidget);
      expect(find.text('ACTIVE KITCHEN TICKETS'), findsOneWidget);
      expect(find.text('TABLE OCCUPANCY'), findsOneWidget);
      expect(find.text('INVENTORY ALERTS'), findsOneWidget);
    });

    testWidgets('PosPage renders catalog, cart, and table selector', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const PosPage()));
      await tester.pumpAndSettle();

      expect(find.text('Point of sale'), findsOneWidget);
      expect(find.text('Current order'), findsOneWidget);
      expect(find.text('Takeaway'), findsOneWidget);
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('Grand total'), findsOneWidget);
    });

    testWidgets('KitchenPage renders 3-column ticket pass', (tester) async {
      await tester.pumpWidget(_wrap(const KitchenPage()));
      await tester.pumpAndSettle();

      expect(find.text('Kitchen display'), findsOneWidget);
      expect(find.textContaining('New orders'), findsOneWidget);
      expect(find.textContaining('Preparing orders'), findsOneWidget);
      expect(find.textContaining('Ready orders'), findsOneWidget);
    });

    testWidgets('MenuManagementPage displays product cards and actions', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const MenuManagementPage()));
      await tester.pumpAndSettle();

      expect(find.text('Menu management'), findsOneWidget);
      expect(find.text('Add menu item'), findsOneWidget);
      expect(find.text('Velvet latte'), findsOneWidget);
      expect(find.text('House espresso'), findsOneWidget);
    });

    testWidgets('InventoryPage renders ingredients and restock button', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const InventoryPage()));
      await tester.pumpAndSettle();

      expect(find.text('Inventory Management'), findsOneWidget);
      expect(find.text('House espresso beans'), findsOneWidget);
      expect(find.text('Restock'), findsWidgets);
    });

    testWidgets('TablesPage renders dining floor and seating actions', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const TablesPage()));
      await tester.pumpAndSettle();

      expect(find.text('Dining Tables Management'), findsOneWidget);
      expect(find.text('Table 01'), findsOneWidget);
      expect(find.text('Table 02'), findsOneWidget);
      expect(find.text('Seat guests'), findsWidgets);
    });

    testWidgets('StaffPage renders team roster and shift coverage', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const StaffPage()));
      await tester.pumpAndSettle();

      expect(find.text('Team & Staff Management'), findsOneWidget);
      expect(find.text('Aanya Rao'), findsOneWidget);
      expect(find.text('Kabir Shah'), findsOneWidget);
    });

    testWidgets('CustomersPage renders guest profiles', (tester) async {
      await tester.pumpWidget(_wrap(const CustomersPage()));
      await tester.pumpAndSettle();

      expect(find.text('Customer Directory'), findsOneWidget);
      expect(find.text('Rohan Mehra'), findsOneWidget);
      expect(find.text('Ananya Deshmukh'), findsOneWidget);
    });

    testWidgets('ReportsPage renders sales figures and hourly rush times', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const ReportsPage()));
      await tester.pumpAndSettle();

      expect(find.text('Sales Reports & Analytics'), findsOneWidget);
      expect(find.text('GROSS REVENUE'), findsOneWidget);
      expect(find.text('Hourly Rush Times'), findsOneWidget);
    });

    testWidgets('SettingsPage renders cafe parameters and theme controls', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const SettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text('Business & System Settings'), findsOneWidget);
      expect(find.text('CafeFlow Flagship Bistro'), findsOneWidget);
      expect(find.text('Theme Mode:'), findsOneWidget);
    });

    testWidgets('Public CustomerMenuPage renders public menu items', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const CustomerMenuPage()));
      await tester.pumpAndSettle();

      expect(find.text('Cafe Menu'), findsOneWidget);
      expect(find.text('Velvet latte'), findsOneWidget);
    });

    testWidgets('Public CustomerAboutPage renders cafe story and values', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const CustomerAboutPage()));
      await tester.pumpAndSettle();

      expect(find.text('A Little Space for Good Company'), findsOneWidget);
      expect(find.text('The Coffee Bar'), findsOneWidget);
      expect(find.text('Artisanal Bakery'), findsOneWidget);
    });

    testWidgets('Public CustomerContactPage renders hours and address', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const CustomerContactPage()));
      await tester.pumpAndSettle();

      expect(find.text('Visit & Contact Us'), findsOneWidget);
      expect(find.text('Opening Hours'), findsOneWidget);
      expect(find.textContaining('CafeFlow Flagship'), findsWidgets);
    });
  });
}
