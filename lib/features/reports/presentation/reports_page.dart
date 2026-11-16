import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backend.dart';
import '../../../core/widgets/cafe_components.dart';
import '../../../shared/components/section_heading.dart';
import '../../auth/application/auth_controller.dart';
import '../../demo/data/demo_operations.dart';
import '../../menu/domain/catalog.dart' show money;
import '../../orders/application/orders_provider.dart';
import '../application/analytics_provider.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AnalyticsTimePreset _selectedPreset = AnalyticsTimePreset.today;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _selectCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customRange ?? _selectedPreset.getRange(),
    );
    if (picked != null) {
      setState(() {
        _selectedPreset = AnalyticsTimePreset.custom;
        _customRange = picked;
      });
    }
  }

  void _showCsvExportDialog(ComprehensiveAnalytics data) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Icon(Icons.file_download_outlined),
            Text('Export Business Reports (CSV)'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select which report dataset you want to export. The CSV payload will be copied to your system clipboard for Excel, Google Sheets, or auditing.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(
                Icons.account_balance_outlined,
                color: Colors.teal,
              ),
              title: const Text('Financial & Sales Statement'),
              subtitle: const Text(
                'Gross, net, taxes, discounts, refunds, and tenders',
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              tileColor: Theme.of(ctx).colorScheme.surfaceContainerHighest
                  .withAlpha(80),
              onTap: () {
                final csv = AnalyticsCsvExporter.exportFinancialCsv(data);
                Clipboard.setData(ClipboardData(text: csv));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Financial CSV copied to clipboard!'),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.restaurant_menu, color: Colors.orange),
              title: const Text('Product & Menu Analytics'),
              subtitle: const Text(
                'Top and least selling items, unit volume, and revenue',
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              tileColor: Theme.of(ctx).colorScheme.surfaceContainerHighest
                  .withAlpha(80),
              onTap: () {
                final csv = AnalyticsCsvExporter.exportProductSalesCsv(data);
                Clipboard.setData(ClipboardData(text: csv));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Product Sales CSV copied to clipboard!'),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.insights, color: Colors.blue),
              title: const Text('Full Multi-Dimensional Operations'),
              subtitle: const Text(
                'Inventory valuation, kitchen prep time, floor and staff',
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              tileColor: Theme.of(ctx).colorScheme.surfaceContainerHighest
                  .withAlpha(80),
              onTap: () {
                final csv = AnalyticsCsvExporter.exportOperationalCsv(data);
                Clipboard.setData(ClipboardData(text: csv));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Operational CSV copied to clipboard!'),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrintableReportDialog(ComprehensiveAnalytics data) {
    final f = data.financial;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Icon(Icons.print_outlined),
            Text('Printable Business Summary'),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest
                        .withAlpha(60),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(ctx).dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CafeFlow Executive Summary',
                        style: Theme.of(ctx).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Period: ${data.startDate.day}/${data.startDate.month}/${data.startDate.year} - ${data.endDate.day}/${data.endDate.month}/${data.endDate.year}',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      Text(
                        'Generated: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _summaryRow(ctx, 'Gross Sales', money(f.grossSalesMinor)),
                _summaryRow(
                  ctx,
                  'Discounts Given',
                  '-${money(f.discountsTotalMinor)}',
                ),
                _summaryRow(
                  ctx,
                  'Net Sales',
                  money(f.netSalesMinor),
                  isBold: true,
                ),
                _summaryRow(
                  ctx,
                  'Tax Collected (GST)',
                  money(f.taxCollectedMinor),
                ),
                _summaryRow(
                  ctx,
                  'Total Payments Collected',
                  money(f.totalPaymentsMinor),
                  isBold: true,
                ),
                _summaryRow(
                  ctx,
                  'Refunds Deducted',
                  '-${money(f.refundsTotalMinor)}',
                ),
                _summaryRow(
                  ctx,
                  'Net Funds Collected',
                  money(f.netCollectedMinor),
                  isBold: true,
                ),
                _summaryRow(
                  ctx,
                  'Outstanding Tabs / Unpaid',
                  money(f.outstandingBalanceMinor),
                  isNegative: f.outstandingBalanceMinor > 0,
                ),
                const Divider(height: 24),
                Text(
                  'Operations & Floor Snapshot',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _summaryRow(
                  ctx,
                  'Total Orders Placed',
                  '${f.totalOrdersCount} orders',
                ),
                _summaryRow(
                  ctx,
                  'Average Ticket Size',
                  money(f.avgOrderValueMinor),
                ),
                _summaryRow(
                  ctx,
                  'Avg Kitchen Prep Time',
                  data.kitchen.formattedAvgPrepTime,
                ),
                _summaryRow(
                  ctx,
                  'Floor Occupancy Rate',
                  '${data.tables.occupancyRatePercent}%',
                ),
                _summaryRow(
                  ctx,
                  'Stock Inventory Valuation',
                  money(data.inventory.stockValuationMinor),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Text'),
            onPressed: () {
              final text =
                  'CafeFlow Summary\nGross: ${money(f.grossSalesMinor)}\nNet: ${money(f.netSalesMinor)}\nCollected: ${money(f.netCollectedMinor)}\nOutstanding: ${money(f.outstandingBalanceMinor)}';
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Report summary copied to clipboard!'),
                ),
              );
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    BuildContext ctx,
    String label,
    String value, {
    bool isBold = false,
    bool isNegative = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: isNegative ? Colors.orange.shade800 : null,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(backendProvider);
    final auth = ref.watch(authControllerProvider);
    final isLive =
        backend.status == BackendStatus.initialized &&
        auth.activeMembership?.restaurantId != null;

    final filterArgs = AnalyticsFilterArgs(
      preset: _selectedPreset,
      customRange: _customRange,
    );

    final analyticsAsync = ref.watch(
      comprehensiveAnalyticsProvider(filterArgs),
    );
    final liveAnalytics =
        analyticsAsync.value ??
        DemoAnalyticsRepository.generateDemoAnalytics(
          filterArgs.resolveRange().start,
          filterArgs.resolveRange().end,
          orders: ref.watch(ordersProvider).value,
        );

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
                    Icons.query_stats,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Financial Reports · Realtime Reconciled',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              const SectionHeading(
                'Sales Reports & Analytics',
                subtitle: 'Revenue, collections, taxes, discounts, refunds and reconciliation.',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  CafeButton(
                    label: 'Export CSV',
                    icon: Icons.download_rounded,
                    secondary: true,
                    onPressed: () => _showCsvExportDialog(liveAnalytics),
                  ),
                  CafeButton(
                    label: 'Print Report',
                    icon: Icons.print_outlined,
                    secondary: true,
                    onPressed: () => _showPrintableReportDialog(liveAnalytics),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Date presets row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final preset in AnalyticsTimePreset.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(preset.label),
                      selected: _selectedPreset == preset,
                      onSelected: (selected) {
                        if (selected) {
                          if (preset == AnalyticsTimePreset.custom) {
                            _selectCustomRange();
                          } else {
                            setState(() {
                              _selectedPreset = preset;
                            });
                          }
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Tab Bar
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(
                icon: Icon(Icons.account_balance_wallet_outlined),
                text: 'Financial & Sales',
              ),
              Tab(icon: Icon(Icons.restaurant_menu), text: 'Product & Menu'),
              Tab(
                icon: Icon(Icons.inventory_2_outlined),
                text: 'Inventory & Wastage',
              ),
              Tab(
                icon: Icon(Icons.soup_kitchen_outlined),
                text: 'Kitchen & Floor',
              ),
              Tab(icon: Icon(Icons.badge_outlined), text: 'Staff & Operations'),
            ],
          ),
          const SizedBox(height: 24),

          // Tab Views
          SizedBox(
            height: 900,
            child: TabBarView(
              controller: _tabController,
              children: [
                // 1. Financial & Sales Tab
                _buildFinancialTab(context, liveAnalytics),

                // 2. Product & Menu Tab
                _buildProductTab(context, liveAnalytics),

                // 3. Inventory & Wastage Tab
                _buildInventoryTab(context, liveAnalytics),

                // 4. Kitchen & Floor Tab
                _buildKitchenFloorTab(context, liveAnalytics),

                // 5. Staff & Operations Tab
                _buildStaffOperationsTab(context, liveAnalytics),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialTab(BuildContext context, ComprehensiveAnalytics data) {
    final f = data.financial;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveColumns(
            minWidth: 220,
            children: [
              MetricCard(
                label: 'GROSS REVENUE',
                value: money(f.grossSalesMinor),
                detail:
                    'From ${f.totalOrdersCount} orders (${f.paidOrdersCount} settled)',
                icon: Icons.payments_outlined,
              ),
              MetricCard(
                label: 'NET REVENUE',
                value: money(f.netSalesMinor),
                detail: 'Gross sales less discounts',
                icon: Icons.account_balance_wallet_outlined,
              ),
              MetricCard(
                label: 'PAYMENTS COLLECTED',
                value: money(f.totalPaymentsMinor),
                detail: 'Actual funds received',
                icon: Icons.point_of_sale_outlined,
              ),
              MetricCard(
                label: 'OUTSTANDING BALANCE',
                value: money(f.outstandingBalanceMinor),
                detail: '${f.unpaidOrdersCount} unsettled / tab orders',
                icon: Icons.pending_actions_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),
          AdaptiveColumns(
            minWidth: 220,
            children: [
              MetricCard(
                label: 'TOTAL TAX (GST)',
                value: money(f.taxCollectedMinor),
                detail: 'Collected tax liability',
                icon: Icons.account_balance_outlined,
              ),
              MetricCard(
                label: 'DISCOUNTS GIVEN',
                value: money(f.discountsTotalMinor),
                detail: 'Promotional & courtesy reductions',
                icon: Icons.local_offer_outlined,
              ),
              MetricCard(
                label: 'REFUNDS ISSUED',
                value: money(f.refundsTotalMinor),
                detail: 'Audited returned funds',
                icon: Icons.replay_outlined,
              ),
              MetricCard(
                label: 'AVG TICKET SIZE',
                value: money(f.avgOrderValueMinor),
                detail: 'Average order bill',
                icon: Icons.receipt_long_outlined,
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'Payment Collections by Tender',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          AdaptiveColumns(
            minWidth: 260,
            children: [
              CafeCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Icon(Icons.money, color: Colors.green.shade700),
                        Text(
                          'Cash Tender',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      money(f.cashCollectedMinor),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      f.totalPaymentsMinor > 0
                          ? '${((f.cashCollectedMinor / f.totalPaymentsMinor) * 100).toStringAsFixed(1)}% of total collected'
                          : '0.0% of total',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              CafeCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Icon(Icons.qr_code_2, color: Colors.blue.shade700),
                        Text(
                          'UPI / QR Digital',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      money(f.upiCollectedMinor),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      f.totalPaymentsMinor > 0
                          ? '${((f.upiCollectedMinor / f.totalPaymentsMinor) * 100).toStringAsFixed(1)}% of total collected'
                          : '0.0% of total',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              CafeCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Icon(
                          Icons.credit_card,
                          color: Colors.deepPurple.shade700,
                        ),
                        Text(
                          'Card POS / Terminal',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      money(f.cardCollectedMinor),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      f.totalPaymentsMinor > 0
                          ? '${((f.cardCollectedMinor / f.totalPaymentsMinor) * 100).toStringAsFixed(1)}% of total collected'
                          : '0.0% of total',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'Order Channels (Dine-In vs Takeaway vs Delivery)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          AdaptiveColumns(
            minWidth: 200,
            children: [
              for (final ot in data.orderTypes)
                CafeCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ot.orderType,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        money(ot.revenueMinor),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${ot.orderCount} orders completed',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            'Hourly Rush Times',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          AdaptiveColumns(
            minWidth: 200,
            children: const [
              CafeCard(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '08:00 – 11:00 AM',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 6),
                    Text('Morning Rush: High latte and croissant volume.'),
                    SizedBox(height: 8),
                    StatusPill('Peak Demand'),
                  ],
                ),
              ),
              CafeCard(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '12:30 – 14:30 PM',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 6),
                    Text('Lunch Hour: Grain bowls and sourdough melts.'),
                    SizedBox(height: 8),
                    StatusPill('Moderate'),
                  ],
                ),
              ),
              CafeCard(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '16:00 – 18:00 PM',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 6),
                    Text('Evening Brew: Cold brews and sweet treats.'),
                    SizedBox(height: 8),
                    StatusPill('Steady'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductTab(BuildContext context, ComprehensiveAnalytics data) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Best-Selling Items',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          CafeCard(
            padding: const EdgeInsets.all(18),
            child: data.topProducts.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No item sales in period.'),
                    ),
                  )
                : Column(
                    children: [
                      for (int i = 0; i < data.topProducts.length; i++) ...[
                        if (i > 0) const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data.topProducts[i].productName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${data.topProducts[i].quantitySold} units sold',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Text(
                              money(data.topProducts[i].revenueMinor),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 28),
          Text(
            'Least-Selling Items (Attention Needed)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          CafeCard(
            padding: const EdgeInsets.all(18),
            child: data.leastProducts.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No least selling items detected.'),
                    ),
                  )
                : Column(
                    children: [
                      for (int i = 0; i < data.leastProducts.length; i++) ...[
                        if (i > 0) const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data.leastProducts[i].productName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${data.leastProducts[i].quantitySold} units sold',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            Text(
                              money(data.leastProducts[i].revenueMinor),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryTab(BuildContext context, ComprehensiveAnalytics data) {
    final inv = data.inventory;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveColumns(
            minWidth: 200,
            children: [
              MetricCard(
                label: 'STOCK VALUATION',
                value: money(inv.stockValuationMinor),
                detail: 'Based on current stock × unit cost',
                icon: Icons.account_balance_outlined,
              ),
              MetricCard(
                label: 'TOTAL ITEMS',
                value: '${inv.totalItemsCount}',
                detail: 'Catalogued inventory items',
                icon: Icons.inventory_2_outlined,
              ),
              MetricCard(
                label: 'LOW-STOCK ALERTS',
                value: '${inv.lowStockCount}',
                detail: 'Items at or below reorder level',
                icon: Icons.warning_amber_rounded,
              ),
              MetricCard(
                label: 'WASTAGE / DAMAGE',
                value: money(inv.wastageCostMinor),
                detail: 'Audited loss in period',
                icon: Icons.delete_outline,
              ),
            ],
          ),
          const SizedBox(height: 24),
          CafeCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inventory Replenishment Recommendations',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  inv.lowStockCount > 0
                      ? 'You have ${inv.lowStockCount} items requiring stock reordering. Open the Inventory & Suppliers workspace to generate purchase orders.'
                      : 'All inventory stock levels are healthy and within safe operating margins.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKitchenFloorTab(
    BuildContext context,
    ComprehensiveAnalytics data,
  ) {
    final k = data.kitchen;
    final t = data.tables;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveColumns(
            minWidth: 200,
            children: [
              MetricCard(
                label: 'AVG PREPARATION TIME',
                value: k.formattedAvgPrepTime,
                detail: 'From order placement to ready',
                icon: Icons.timer_outlined,
              ),
              MetricCard(
                label: 'ACTIVE KITCHEN TICKETS',
                value: '${k.activeTicketsCount}',
                detail: 'Tickets in prep queue',
                icon: Icons.soup_kitchen_outlined,
              ),
              MetricCard(
                label: 'DELAYED TICKETS (>20M)',
                value: '${k.delayedTicketsCount}',
                detail: k.delayedTicketsCount > 0
                    ? 'Urgent attention required'
                    : 'No delayed tickets',
                icon: Icons.hourglass_bottom_outlined,
              ),
              MetricCard(
                label: 'TABLE OCCUPANCY',
                value: '${t.occupancyRatePercent}%',
                detail:
                    '${t.occupiedTables} of ${t.totalTables} tables occupied',
                icon: Icons.table_restaurant_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStaffOperationsTab(
    BuildContext context,
    ComprehensiveAnalytics data,
  ) {
    final w = data.workforce;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveColumns(
            minWidth: 200,
            children: [
              MetricCard(
                label: 'CURRENTLY CLOCKED IN',
                value: '${w.currentlyClockedIn} staff',
                detail: 'Active on floor or counter',
                icon: Icons.badge_outlined,
              ),
              MetricCard(
                label: 'ON BREAK',
                value: '${w.currentlyOnBreak} staff',
                detail: 'Scheduled rest period',
                icon: Icons.coffee_outlined,
              ),
              MetricCard(
                label: 'LATE ARRIVALS',
                value: '${w.lateArrivalsCount}',
                detail: 'Clocked in past shift start',
                icon: Icons.access_time_filled,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Staff Roster on Duty Today',
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
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '· ${staff.role} (${staff.shift})',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const StatusPill('Clocked In'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
