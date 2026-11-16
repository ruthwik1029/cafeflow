import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/workspace.dart';
import '../../../core/services/backend.dart';
import '../../../core/widgets/cafe_components.dart';
import '../../../shared/components/section_heading.dart';
import '../../auth/application/auth_controller.dart';
import '../../demo/application/demo_orders_controller.dart';
import '../../inventory/application/inventory_provider.dart';
import '../../menu/domain/catalog.dart';
import '../../orders/application/orders_provider.dart';
import '../../orders/domain/cafe_order.dart';
import '../../reports/application/analytics_provider.dart';
import '../../tables/application/tables_provider.dart';
import '../../workspaces/domain/workspace_catalog.dart';
import '../../workspaces/presentation/workspace_page.dart';

class OwnerOverviewPage extends ConsumerStatefulWidget {
  const OwnerOverviewPage({super.key});

  @override
  ConsumerState<OwnerOverviewPage> createState() => _OwnerOverviewPageState();
}

class _OwnerOverviewPageState extends ConsumerState<OwnerOverviewPage> {
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
    final occupiedCount = tables
        .where((t) => t.status == TableStatus.occupied)
        .length;

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
                    Icons.store_mall_directory_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Owner Pocket Console · Connected to Supabase',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          WorkspaceHero(workspace: workspaceFor(WorkspaceRole.owner)),
          const SizedBox(height: 24),
          const SectionHeading(
            'Cafe Overview',
            subtitle: 'Pocket monitoring for sales, floor, and service.',
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
            minWidth: 160,
            children: [
              MetricCard(
                label: "TODAY'S SALES",
                value: money(totalSalesMinor),
                detail: '${orders.length} orders total',
                icon: Icons.currency_rupee,
              ),
              MetricCard(
                label: 'ACTIVE KITCHEN',
                value: '${activeOrders.length}',
                detail: 'Tickets in prep',
                icon: Icons.soup_kitchen_outlined,
              ),
              MetricCard(
                label: 'TABLES SEATED',
                value: tables.isEmpty
                    ? '0 / 0'
                    : '$occupiedCount / ${tables.length}',
                detail: 'Guests dining',
                icon: Icons.table_restaurant_outlined,
              ),
              MetricCard(
                label: 'STOCK ALERTS',
                value: '${lowStockItems.length}',
                detail: lowStockItems.isEmpty ? 'All safe' : 'Low ingredients',
                icon: Icons.warning_amber_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Pocket Executive Financial Quick Card
          CafeCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Financial Snapshot (${_preset.label})',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Net Collected: ${money(analytics.financial.netCollectedMinor)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(
                      'Cash: ${money(analytics.financial.cashCollectedMinor)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'UPI: ${money(analytics.financial.upiCollectedMinor)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Card: ${money(analytics.financial.cardCollectedMinor)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Tabs: ${money(analytics.financial.outstandingBalanceMinor)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Recent Order Activity',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          for (final order in orders.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CafeCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CircleAvatar(
                      backgroundColor: order.status == OrderStatus.ready
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        order.status == OrderStatus.ready
                            ? Icons.check
                            : Icons.receipt_long,
                        size: 18,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${order.number} · ${order.table}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${order.lines.length} items · ${money(order.totalMinor)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    StatusPill(order.status.label),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
