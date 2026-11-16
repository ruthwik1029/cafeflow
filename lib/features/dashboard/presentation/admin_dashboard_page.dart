import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/workspace.dart';
import '../../../core/services/backend.dart';
import '../../../core/widgets/cafe_components.dart';
import '../../../shared/components/section_heading.dart';
import '../../auth/application/auth_controller.dart';
import '../../demo/application/demo_orders_controller.dart';
import '../../demo/data/demo_operations.dart';
import '../../inventory/application/inventory_provider.dart';
import '../../menu/domain/catalog.dart';
import '../../menu/presentation/menu_editor.dart';
import '../../orders/application/orders_provider.dart';
import '../../orders/domain/cafe_order.dart';
import '../../orders/presentation/orders_page.dart';
import '../../reports/application/analytics_provider.dart';
import '../../tables/application/tables_provider.dart';
import '../../workspaces/domain/workspace_catalog.dart';
import '../../workspaces/presentation/workspace_page.dart';

class AdminDashboardPage extends ConsumerStatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  ConsumerState<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends ConsumerState<AdminDashboardPage> {
  AnalyticsTimePreset _preset = AnalyticsTimePreset.today;

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(backendProvider);
    final auth = ref.watch(authControllerProvider);
    final isLive =
        backend.status == BackendStatus.initialized &&
        auth.activeMembership?.restaurantId != null;

    final List<CafeOrder> orders =
        ref.watch(ordersProvider).value ?? ref.watch(demoOrdersProvider);
    final inventory = ref.watch(inventoryProvider).value ?? [];
    final tables = ref.watch(tablesProvider).value ?? [];

    final filterArgs = AnalyticsFilterArgs(preset: _preset);
    final analyticsAsync = ref.watch(
      comprehensiveAnalyticsProvider(filterArgs),
    );
    final analytics =
        analyticsAsync.value ??
        DemoAnalyticsRepository.generateDemoAnalytics(
          _preset.getRange().start,
          _preset.getRange().end,
          orders: orders,
          inventory: inventory,
          tables: tables,
        );

    final totalSalesMinor = orders
        .where((o) => o.status != OrderStatus.cancelled)
        .fold(0, (sum, o) => sum + o.totalMinor);
    final activeOrders = orders
        .where(
          (o) =>
              o.status == OrderStatus.newOrder ||
              o.status == OrderStatus.preparing,
        )
        .toList();
    final lowStockItems = inventory.where((i) => i.isLow).toList();
    final occupiedTables = tables
        .where((t) => t.status == TableStatus.occupied)
        .toList();

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isLive) const DemoNotice(),
          if (isLive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer
                    .withAlpha(90),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.dashboard_customize_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Executive Dashboard · Connected to Supabase',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          WorkspaceHero(workspace: workspaceFor(WorkspaceRole.admin)),
          const SizedBox(height: 24),
          SectionHeading(
            'Executive Dashboard',
            subtitle: 'Real-time overview of sales, active orders, and floor operations.',
            action: Wrap(
              spacing: 8,
              children: [
                CafeButton(
                  label: 'New POS order',
                  icon: Icons.point_of_sale_rounded,
                  onPressed: () => context.go('/cashier/pos'),
                ),
                CafeButton(
                  label: 'Add item',
                  secondary: true,
                  icon: Icons.add,
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const MenuEditor(),
                  ),
                ),
              ],
            ),
          ),

          // Date preset filter chips
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in [
                    AnalyticsTimePreset.today,
                    AnalyticsTimePreset.yesterday,
                    AnalyticsTimePreset.last7Days,
                    AnalyticsTimePreset.thisMonth,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p.label),
                        selected: _preset == p,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _preset = p);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          AdaptiveColumns(
            minWidth: 220,
            children: [
              MetricCard(
                label: "TODAY'S REVENUE",
                value: money(totalSalesMinor),
                detail: '${orders.length} total orders placed',
                icon: Icons.currency_rupee_rounded,
              ),
              MetricCard(
                label: 'ACTIVE KITCHEN TICKETS',
                value: '${activeOrders.length} tickets',
                detail: 'Requiring preparation or readying',
                icon: Icons.soup_kitchen_outlined,
              ),
              MetricCard(
                label: 'TABLE OCCUPANCY',
                value: tables.isEmpty
                    ? '0 tables'
                    : '${occupiedTables.length}/${tables.length} tables',
                detail: tables.isEmpty
                    ? 'No dining tables configured'
                    : '${((occupiedTables.length / tables.length) * 100).round()}% capacity seated',
                icon: Icons.table_restaurant_outlined,
              ),
              MetricCard(
                label: 'INVENTORY ALERTS',
                value: '${lowStockItems.length} items',
                detail: lowStockItems.isEmpty
                    ? 'All stock above minimums'
                    : 'Attention needed immediately',
                icon: Icons.warning_amber_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Additional Financial & Operations Quick Row
          AdaptiveColumns(
            minWidth: 220,
            children: [
              MetricCard(
                label: 'COLLECTED PAYMENTS',
                value: money(analytics.financial.totalPaymentsMinor),
                detail:
                    '${analytics.financial.paidOrdersCount} orders fully settled',
                icon: Icons.account_balance_wallet_outlined,
              ),
              MetricCard(
                label: 'OUTSTANDING TABS',
                value: money(analytics.financial.outstandingBalanceMinor),
                detail:
                    '${analytics.financial.unpaidOrdersCount} unpaid / tab orders',
                icon: Icons.pending_actions_outlined,
              ),
              MetricCard(
                label: 'AVG PREP TIME',
                value: analytics.kitchen.formattedAvgPrepTime,
                detail: 'Average kitchen ticket time',
                icon: Icons.timer_outlined,
              ),
              MetricCard(
                label: 'ACTIVE STAFF',
                value: '${analytics.workforce.currentlyClockedIn} on duty',
                detail:
                    '${analytics.workforce.currentlyOnBreak} currently on break',
                icon: Icons.badge_outlined,
              ),
            ],
          ),
          const SizedBox(height: 36),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 850;

              final ordersColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active Orders at the Pass',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (activeOrders.isEmpty)
                    const CafeEmptyState(
                      title: 'Kitchen is clear',
                      message: 'No pending orders need attention right now.',
                      icon: Icons.check_circle_outline,
                    )
                  else
                    for (final order in activeOrders.take(3))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OrderTicket(order: order),
                      ),
                  TextButton.icon(
                    onPressed: () => context.go('/admin/orders'),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('View all orders'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Top-Selling Menu Items',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  CafeCard(
                    padding: const EdgeInsets.all(16),
                    child: analytics.topProducts.isEmpty
                        ? const Text('No sales recorded in period.')
                        : Column(
                            children: [
                              for (
                                int i = 0;
                                i < analytics.topProducts.take(4).length;
                                i++
                              ) ...[
                                if (i > 0) const Divider(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${i + 1}. ${analytics.topProducts[i].productName}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${analytics.topProducts[i].quantitySold} sold (${money(analytics.topProducts[i].revenueMinor)})',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              );

              final alertsColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stock & Operational Alerts',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (lowStockItems.isEmpty)
                    const CafeCard(
                      child: Text('All ingredient stocks are in safe ranges.'),
                    )
                  else
                    for (final item in lowStockItems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: CafeCard(
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Icon(
                                Icons.inventory_2_outlined,
                                color: Colors.orange,
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  Text(
                                    'Current: ${item.currentStock} ${item.unit} (Min: ${item.reorderLevel} ${item.unit})',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                              const StatusPill('Low Stock'),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 20),
                  Text(
                    'Staff on Duty Today',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  for (final staff in demoStaff.where((s) => s.active))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: CafeCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Icon(Icons.person_outline, size: 20),
                            Text(
                              staff.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '· ${staff.role} (${staff.shift})',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );

              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: ordersColumn),
                        const SizedBox(width: 28),
                        Expanded(flex: 5, child: alertsColumn),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ordersColumn,
                        const SizedBox(height: 32),
                        alertsColumn,
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}
