import 'package:flutter/material.dart';

import '../../../core/routing/workspace.dart';
import '../../billing/presentation/pos_page.dart';
import '../../customers/presentation/customers_page.dart';
import '../../dashboard/presentation/admin_dashboard_page.dart';
import '../../dashboard/presentation/owner_overview_page.dart';
import '../../inventory/presentation/inventory_page.dart';
import '../../menu/presentation/catalog_browser.dart';
import '../../menu/presentation/menu_management_page.dart';
import '../../menu/presentation/popular_items_page.dart';
import '../../orders/presentation/orders_page.dart';
import '../../reports/presentation/reports_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../staff/presentation/staff_page.dart';
import '../../tables/presentation/tables_page.dart';
import 'workspace_page.dart';

class WorkspaceSectionDispatcher extends StatelessWidget {
  const WorkspaceSectionDispatcher({
    required this.workspace,
    required this.section,
    super.key,
  });

  final WorkspaceDefinition workspace;
  final WorkspaceSection section;

  @override
  Widget build(BuildContext context) {
    return switch (workspace.role) {
      WorkspaceRole.admin => switch (section.id) {
        'dashboard' => const AdminDashboardPage(),
        'orders' => const OrdersPage(),
        'menu' => const MenuManagementPage(),
        'categories' => const MenuManagementPage(categoriesOnly: true),
        'inventory' => const InventoryPage(),
        'tables' => const TablesPage(),
        'staff' => const StaffPage(),
        'customers' => const CustomersPage(),
        'reports' => const ReportsPage(),
        'settings' => const SettingsPage(),
        _ => WorkspacePage(workspace: workspace, section: section),
      },
      WorkspaceRole.cashier => switch (section.id) {
        'pos' || 'billing' => const PosPage(),
        'orders' => const OrdersPage(),
        _ => WorkspacePage(workspace: workspace, section: section),
      },
      WorkspaceRole.kitchen => switch (section.id) {
        'display' || 'preparation' => const KitchenPage(),
        'incoming' => const KitchenPage(incomingOnly: true),
        _ => WorkspacePage(workspace: workspace, section: section),
      },
      WorkspaceRole.owner => switch (section.id) {
        'overview' => const OwnerOverviewPage(),
        'orders' => const OrdersPage(),
        'popular' => const PopularItemsPage(),
        'inventory' => const InventoryPage(alertsOnly: true),
        'staff' => const StaffPage(compact: true),
        _ => WorkspacePage(workspace: workspace, section: section),
      },
      WorkspaceRole.staff => switch (section.id) {
        'orders' => const PosPage(staff: true),
        'menu' => const CatalogBrowserPage(),
        'tables' => const TablesPage(staff: true),
        'status' => const OrdersPage(activeOnly: true),
        _ => WorkspacePage(workspace: workspace, section: section),
      },
    };
  }
}
