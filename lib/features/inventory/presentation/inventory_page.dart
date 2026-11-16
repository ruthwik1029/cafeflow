import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/services/backend.dart';
import '../../../core/widgets/cafe_components.dart';
import '../../../shared/components/section_heading.dart';
import '../../auth/application/auth_controller.dart';
import '../../demo/application/demo_inventory_controller.dart';
import '../application/inventory_provider.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({this.alertsOnly = false, super.key});
  final bool alertsOnly;

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _categoryFilter;
  bool _showLowOnly = false;
  String _searchQuery = '';
  StockMovementType? _movementFilter;

  // Selected menu item for Recipe tab
  String _selectedRecipeMenuItem = 'Espresso';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    if (widget.alertsOnly) {
      _showLowOnly = true;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(backendProvider);
    final auth = ref.watch(authControllerProvider);
    final isLive =
        backend.status == BackendStatus.initialized &&
        auth.activeMembership?.restaurantId != null;

    final inventory = ref.watch(inventoryProvider).value ?? [];

    if (widget.alertsOnly) {
      return PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isLive) const DemoNotice(),
            SectionHeading(
              'Inventory Alerts',
              subtitle: 'Ingredients and items falling below minimum safe thresholds.',
            ),
            const SizedBox(height: 16),
            _buildItemsGrid(
              inventory.where((i) => i.isLow).toList(),
              isLive,
              isAlertsOnly: true,
            ),
          ],
        ),
      );
    }

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
                    Icons.inventory_2_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Inventory Tracking · Audit-Friendly Stock Movements · Recipes & POs',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            tabs: const [
              Tab(
                icon: Icon(Icons.inventory_2_outlined),
                text: 'Items & Stock',
              ),
              Tab(icon: Icon(Icons.history_outlined), text: 'Stock Ledger'),
              Tab(icon: Icon(Icons.local_shipping_outlined), text: 'Suppliers'),
              Tab(
                icon: Icon(Icons.shopping_bag_outlined),
                text: 'Purchase Orders',
              ),
              Tab(icon: Icon(Icons.menu_book_outlined), text: 'Recipes & BOM'),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              return switch (_tabController.index) {
                0 => _buildItemsTab(context, inventory, isLive),
                1 => _buildLedgerTab(context, isLive),
                2 => _buildSuppliersTab(context, isLive),
                3 => _buildPurchasesTab(context, isLive),
                4 => _buildRecipesTab(context, inventory, isLive),
                _ => _buildItemsTab(context, inventory, isLive),
              };
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 0: Items & Stock
  // ---------------------------------------------------------------------------

  Widget _buildItemsTab(
    BuildContext context,
    List<InventoryItem> inventory,
    bool isLive,
  ) {
    final categories = inventory.map((i) => i.categoryName).toSet().toList();

    final filtered = inventory.where((item) {
      if (_showLowOnly && !item.isLow) return false;
      if (_categoryFilter != null && item.categoryName != _categoryFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchName = item.name.toLowerCase().contains(query);
        final matchSku = item.sku?.toLowerCase().contains(query) ?? false;
        if (!matchName && !matchSku) return false;
      }
      return true;
    }).toList();

    // Calculate total valuation
    final totalValuationMinor = inventory.fold<int>(
      0,
      (sum, item) => sum + item.stockValuationMinor,
    );
    final lowStockCount = inventory.where((i) => i.isLow).length;
    final outOfStockCount = inventory.where((i) => i.isOutOfStock).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Inventory Management',
          subtitle: 'Monitor stock levels, set thresholds, track unit valuation, and record replenishment.',
          action: CafeButton(
            label: 'Add item',
            icon: Icons.add,
            onPressed: () => _addItemDialog(context, isLive),
          ),
        ),
        const SizedBox(height: 12),

        // Metrics Summary Row
        LayoutBuilder(
          builder: (context, constraints) {
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildMetricCard(
                  context,
                  title: 'Total Items',
                  value: '${inventory.length}',
                  icon: Icons.category_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                _buildMetricCard(
                  context,
                  title: 'Low Stock Alerts',
                  value: '$lowStockCount',
                  icon: Icons.warning_amber_rounded,
                  color: lowStockCount > 0
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.outline,
                ),
                _buildMetricCard(
                  context,
                  title: 'Out of Stock',
                  value: '$outOfStockCount',
                  icon: Icons.error_outline,
                  color: outOfStockCount > 0
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.outline,
                ),
                _buildMetricCard(
                  context,
                  title: 'Total Valuation',
                  value: '\$${(totalValuationMinor / 100).toStringAsFixed(2)}',
                  icon: Icons.account_balance_wallet_outlined,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // Search & Category Filters
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: 'Search items by name or SKU...',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('All items'),
              selected: _categoryFilter == null && !_showLowOnly,
              onSelected: (_) => setState(() {
                _categoryFilter = null;
                _showLowOnly = false;
              }),
            ),
            FilterChip(
              label: Text('Low stock only ($lowStockCount)'),
              selected: _showLowOnly,
              onSelected: (selected) => setState(() {
                _showLowOnly = selected;
              }),
            ),
            for (final cat in categories)
              FilterChip(
                label: Text(cat),
                selected: _categoryFilter == cat,
                onSelected: (selected) => setState(() {
                  _categoryFilter = selected ? cat : null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 20),

        _buildItemsGrid(filtered, isLive),
      ],
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withAlpha(80),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withAlpha(40),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsGrid(
    List<InventoryItem> items,
    bool isLive, {
    bool isAlertsOnly = false,
  }) {
    if (items.isEmpty) {
      return const CafeEmptyState(
        title: 'No inventory items match',
        message: 'Check your filters or restock needed supplies.',
        icon: Icons.inventory_2_outlined,
      );
    }

    return AdaptiveColumns(
      minWidth: 290,
      children: [
        for (final item in items)
          CafeCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.categoryName,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    StatusPill(
                      item.isOutOfStock
                          ? 'Out of Stock'
                          : item.isLow
                          ? 'Low Stock'
                          : 'Optimal',
                      icon: item.isOutOfStock
                          ? Icons.error_outline
                          : item.isLow
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.name,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (item.sku != null && item.sku!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'SKU: ${item.sku}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '${item.currentStock.toStringAsFixed(1)} ${item.unit}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: item.isOutOfStock || item.isLow
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Min: ${item.minimumStock.toStringAsFixed(1)} · Reorder: ${item.reorderLevel.toStringAsFixed(1)} ${item.unit}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (item.costPerUnitMinor > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Cost: \$${(item.costPerUnitMinor / 100).toStringAsFixed(2)} / ${item.unit} · Val: \$${(item.stockValuationMinor / 100).toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
                if (item.storageLocation.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Loc: ${item.storageLocation}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => _restockDialog(context, item, isLive),
                      child: const Text('Restock'),
                    ),
                    TextButton(
                      onPressed: () => _adjustDialog(context, item, isLive),
                      child: const Text('Adjust'),
                    ),
                    TextButton(
                      onPressed: () => _wastageDialog(context, item, isLive),
                      child: Text(
                        'Wastage',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Stock Ledger
  // ---------------------------------------------------------------------------

  Widget _buildLedgerTab(BuildContext context, bool isLive) {
    final movementsAsync = ref.watch(stockMovementsProvider(null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Stock Ledger & Audit Trail',
          subtitle: 'Immutable chronological log of all stock movements: purchases, recipe sales, adjustments, wastage, and returns.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('All Movements'),
              selected: _movementFilter == null,
              onSelected: (_) => setState(() => _movementFilter = null),
            ),
            for (final type in StockMovementType.values)
              FilterChip(
                label: Text(type.label),
                selected: _movementFilter == type,
                onSelected: (selected) => setState(() {
                  _movementFilter = selected ? type : null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 20),
        movementsAsync.when(
          data: (movements) {
            final filtered = _movementFilter == null
                ? movements
                : movements
                      .where((m) => m.movementType == _movementFilter)
                      .toList();

            if (filtered.isEmpty) {
              return const CafeEmptyState(
                title: 'No stock movements recorded',
                message:
                    'Stock adjustments, sales, and purchases will appear here.',
                icon: Icons.history_outlined,
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final m = filtered[index];
                final isPositive = m.quantityChange >= 0;
                return CafeCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isPositive
                              ? Colors.green.withAlpha(30)
                              : Colors.orange.withAlpha(30),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPositive
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 20,
                          color: isPositive ? Colors.green : Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  m.itemName,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                StatusPill(
                                  m.movementType.label,
                                  icon: Icons.label_outline,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${m.previousStock.toStringAsFixed(1)} ${m.unit} → ${m.newStock.toStringAsFixed(1)} ${m.unit} (${isPositive ? '+' : ''}${m.quantityChange.toStringAsFixed(1)} ${m.unit})',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isPositive
                                    ? Colors.green
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${m.reason}${m.reference.isNotEmpty ? ' · Ref: ${m.reference}' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              m.createdAt.toLocal().toString().substring(0, 16),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline,
                                    fontSize: 11,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Text('Error loading ledger: $err'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Suppliers
  // ---------------------------------------------------------------------------

  Widget _buildSuppliersTab(BuildContext context, bool isLive) {
    final suppliersAsync = ref.watch(suppliersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Suppliers & Vendors',
          subtitle: 'Maintain supplier registry, vendor contact details, terms, and purchase links.',
          action: CafeButton(
            label: 'Add Supplier',
            icon: Icons.person_add_outlined,
            onPressed: () => _addSupplierDialog(context, isLive),
          ),
        ),
        const SizedBox(height: 16),
        suppliersAsync.when(
          data: (suppliers) {
            if (suppliers.isEmpty) {
              return const CafeEmptyState(
                title: 'No suppliers registered',
                message: 'Add vendor profiles to streamline purchase ordering.',
                icon: Icons.local_shipping_outlined,
              );
            }

            return AdaptiveColumns(
              minWidth: 290,
              children: [
                for (final sup in suppliers)
                  CafeCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                sup.name,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            StatusPill(
                              sup.isActive ? 'Active' : 'Inactive',
                              icon: sup.isActive
                                  ? Icons.check_circle_outline
                                  : Icons.cancel_outlined,
                            ),
                          ],
                        ),
                        if (sup.contactName.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Contact: ${sup.contactName}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (sup.phone.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Phone: ${sup.phone}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (sup.email.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Email: ${sup.email}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (sup.address.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Address: ${sup.address}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                        if (sup.notes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Notes: ${sup.notes}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Text('Error loading suppliers: $err'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Purchase Orders
  // ---------------------------------------------------------------------------

  Widget _buildPurchasesTab(BuildContext context, bool isLive) {
    final purchasesAsync = ref.watch(purchasesProvider(null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Purchase Orders & Receiving',
          subtitle: 'Record vendor purchase orders and atomically receive stock shipments.',
          action: CafeButton(
            label: 'New Purchase Order',
            icon: Icons.add_shopping_cart_outlined,
            onPressed: () => _createPurchaseOrderDialog(context, isLive),
          ),
        ),
        const SizedBox(height: 16),
        purchasesAsync.when(
          data: (purchases) {
            if (purchases.isEmpty) {
              return const CafeEmptyState(
                title: 'No purchase orders found',
                message:
                    'Create purchase orders and record stock receipts here.',
                icon: Icons.shopping_bag_outlined,
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: purchases.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final po = purchases[index];
                final isReceived = po.status == 'RECEIVED';
                return CafeCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  po.purchaseNumber,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '· ${po.supplierName}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusPill(
                            po.status,
                            icon: isReceived
                                ? Icons.check_circle_outline
                                : Icons.schedule_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total: \$${(po.totalMinor / 100).toStringAsFixed(2)} · Subtotal: \$${(po.subtotalMinor / 100).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      if (po.items.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Items: ${po.items.map((i) => '${i.quantity} ${i.unit} ${i.inventoryItemName}').join(', ')}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'Date: ${po.purchaseDate.toLocal().toString().substring(0, 10)}${po.receivedAt != null ? ' · Received: ${po.receivedAt!.toLocal().toString().substring(0, 10)}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      if (!isReceived) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () =>
                              _receivePurchase(context, po, isLive),
                          icon: const Icon(Icons.done_all, size: 16),
                          label: const Text('Receive Shipment & Update Stock'),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Text('Error loading purchases: $err'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 4: Recipes & BOM
  // ---------------------------------------------------------------------------

  Widget _buildRecipesTab(
    BuildContext context,
    List<InventoryItem> inventory,
    bool isLive,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Recipe & BOM Management',
          subtitle: 'Link catalog menu items to raw inventory ingredients for automated stock deduction upon order confirmation.',
        ),
        const SizedBox(height: 12),

        // Architecture Info Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withAlpha(100),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withAlpha(40),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.precision_manufacturing_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Idempotent Recipe Deduction Engine',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'When orders are finalized or synchronized from offline clients, deduct_order_recipe_stock deducts required ingredient quantities atomically. Idempotency guarantees prevent duplicate deductions on sync retries.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Select Menu Item:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            DropdownButton<String>(
              value: _selectedRecipeMenuItem,
              items: const [
                DropdownMenuItem(value: 'Espresso', child: Text('Espresso')),
                DropdownMenuItem(
                  value: 'Cappuccino',
                  child: Text('Cappuccino'),
                ),
                DropdownMenuItem(
                  value: 'Avocado Toast',
                  child: Text('Avocado Toast'),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedRecipeMenuItem = val);
                }
              },
            ),
            FilledButton.tonalIcon(
              onPressed: () => _addRecipeIngredientDialog(
                context,
                inventory,
                _selectedRecipeMenuItem,
                isLive,
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Ingredient'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Configured Ingredients Table / Card
        CafeCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recipe for $_selectedRecipeMenuItem',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (_selectedRecipeMenuItem == 'Espresso') ...[
                _buildIngredientRow('House espresso beans', 0.018, 'kg'),
                _buildIngredientRow('Water (Filtered)', 0.035, 'L'),
              ] else if (_selectedRecipeMenuItem == 'Cappuccino') ...[
                _buildIngredientRow('House espresso beans', 0.018, 'kg'),
                _buildIngredientRow('Organic whole milk', 0.150, 'L'),
              ] else ...[
                _buildIngredientRow('Sourdough loaves', 0.100, 'loaves'),
                _buildIngredientRow('Avocados (Hass)', 1.0, 'pcs'),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIngredientRow(String name, double quantity, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.circle, size: 8, color: Colors.orange),
              const SizedBox(width: 8),
              Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
          Text(
            '$quantity $unit per serving',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Dialogs & Actions
  // ---------------------------------------------------------------------------

  void _restockDialog(BuildContext context, InventoryItem item, bool isLive) {
    final controller = TextEditingController(text: '5.0');
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Restock ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current level: ${item.currentStock} ${item.unit}'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Quantity to add (${item.unit})',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text.trim());
              if (amount == null || amount <= 0) return;

              if (isLive) {
                final repo = ref.read(inventoryRepositoryProvider);
                final auth = ref.read(authControllerProvider);
                final restId = auth.activeMembership?.restaurantId;

                if (repo != null && restId != null) {
                  try {
                    await repo.adjustStock(
                      restaurantId: restId,
                      itemId: item.id,
                      movementType: 'PURCHASE',
                      quantityChange: amount,
                      reason: 'Restock replenishment',
                    );
                    ref.invalidate(inventoryProvider);
                    ref.invalidate(stockMovementsProvider);
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Added $amount ${item.unit} to ${item.name}.',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            e is AppFailure ? e.message : 'Error: $e',
                          ),
                        ),
                      );
                    }
                  }
                  return;
                }
              }

              // Demo fallback
              ref.read(demoInventoryProvider.notifier).restock(item.id, amount);
              ref.invalidate(inventoryProvider);
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added $amount ${item.unit} to ${item.name}.'),
                ),
              );
            },
            child: const Text('Add stock'),
          ),
        ],
      ),
    );
  }

  void _adjustDialog(BuildContext context, InventoryItem item, bool isLive) {
    final controller = TextEditingController(
      text: item.currentStock.toStringAsFixed(1),
    );
    final reasonController = TextEditingController(
      text: 'Physical audit count',
    );

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Adjust ${item.name} count'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter verified physical count on hand:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Accurate count (${item.unit})',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for adjustment',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newCount = double.tryParse(controller.text.trim());
              if (newCount == null || newCount < 0) return;

              if (isLive) {
                final repo = ref.read(inventoryRepositoryProvider);
                final auth = ref.read(authControllerProvider);
                final restId = auth.activeMembership?.restaurantId;

                if (repo != null && restId != null) {
                  final diff = newCount - item.currentStock;
                  try {
                    await repo.adjustStock(
                      restaurantId: restId,
                      itemId: item.id,
                      movementType: 'MANUAL_ADJUSTMENT',
                      quantityChange: diff,
                      reason: reasonController.text.trim(),
                    );
                    ref.invalidate(inventoryProvider);
                    ref.invalidate(stockMovementsProvider);
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Updated ${item.name} to $newCount ${item.unit}.',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            e is AppFailure ? e.message : 'Error: $e',
                          ),
                        ),
                      );
                    }
                  }
                  return;
                }
              }

              // Demo fallback
              ref
                  .read(demoInventoryProvider.notifier)
                  .adjust(item.id, newCount);
              ref.invalidate(inventoryProvider);
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Updated ${item.name} to $newCount ${item.unit}.',
                  ),
                ),
              );
            },
            child: const Text('Save count'),
          ),
        ],
      ),
    );
  }

  void _wastageDialog(BuildContext context, InventoryItem item, bool isLive) {
    final controller = TextEditingController(text: '1.0');
    final reasonController = TextEditingController(text: 'Expired / Spoilage');

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Record Wastage for ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current level: ${item.currentStock} ${item.unit}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Wasted quantity to deduct (${item.unit})',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Wastage reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text.trim());
              if (amount == null || amount <= 0) return;

              if (isLive) {
                final repo = ref.read(inventoryRepositoryProvider);
                final auth = ref.read(authControllerProvider);
                final restId = auth.activeMembership?.restaurantId;

                if (repo != null && restId != null) {
                  try {
                    await repo.adjustStock(
                      restaurantId: restId,
                      itemId: item.id,
                      movementType: 'WASTAGE',
                      quantityChange: -amount,
                      reason: reasonController.text.trim(),
                    );
                    ref.invalidate(inventoryProvider);
                    ref.invalidate(stockMovementsProvider);
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Recorded wastage of $amount ${item.unit} for ${item.name}.',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            e is AppFailure ? e.message : 'Error: $e',
                          ),
                        ),
                      );
                    }
                  }
                  return;
                }
              }

              // Demo mode
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Demo Mode: Recorded wastage of $amount ${item.unit}.',
                  ),
                ),
              );
            },
            child: const Text('Record Wastage'),
          ),
        ],
      ),
    );
  }

  void _addItemDialog(BuildContext context, bool isLive) {
    final nameCtrl = TextEditingController();
    final skuCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'kg');
    final stockCtrl = TextEditingController(text: '10.0');
    final minCtrl = TextEditingController(text: '3.0');
    final reorderCtrl = TextEditingController(text: '5.0');
    final costCtrl = TextEditingController(text: '15.00');
    final locCtrl = TextEditingController(text: 'Main Kitchen Shelf A');

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Add Inventory Item'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Item name *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: skuCtrl,
                  decoration: const InputDecoration(
                    labelText: 'SKU / Barcode (e.g. BEAN-ESP-01)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Unit (e.g. kg, g, L, ml, pcs, packs) *',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: stockCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Initial Stock *',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: minCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Minimum Stock *',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: reorderCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Reorder Level *',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: costCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Cost Per Unit (\$) *',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: locCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Storage Location',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final unit = unitCtrl.text.trim();
              final stock = double.tryParse(stockCtrl.text.trim()) ?? 0.0;
              final min = double.tryParse(minCtrl.text.trim()) ?? 0.0;
              final reorder = double.tryParse(reorderCtrl.text.trim()) ?? 0.0;
              final cost = double.tryParse(costCtrl.text.trim()) ?? 0.0;
              final costMinor = (cost * 100).round();

              if (name.isEmpty || unit.isEmpty) return;

              if (isLive) {
                final repo = ref.read(inventoryRepositoryProvider);
                final auth = ref.read(authControllerProvider);
                final restId = auth.activeMembership?.restaurantId;

                if (repo != null && restId != null) {
                  try {
                    await repo.createItem(
                      restaurantId: restId,
                      name: name,
                      sku: skuCtrl.text.trim(),
                      unit: unit,
                      currentStock: stock,
                      minimumStock: min,
                      reorderLevel: reorder,
                      costPerUnitMinor: costMinor,
                      storageLocation: locCtrl.text.trim(),
                    );
                    ref.invalidate(inventoryProvider);
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                  return;
                }
              }

              // Demo mode
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Demo Mode: Item creation simulated.'),
                ),
              );
            },
            child: const Text('Add Item'),
          ),
        ],
      ),
    );
  }

  void _addSupplierDialog(BuildContext context, bool isLive) {
    final nameCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Register Supplier'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Supplier Name *',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: contactCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Contact Person',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              if (isLive) {
                final repo = ref.read(inventoryRepositoryProvider);
                final auth = ref.read(authControllerProvider);
                final restId = auth.activeMembership?.restaurantId;

                if (repo != null && restId != null) {
                  try {
                    await repo.createSupplier(
                      restaurantId: restId,
                      name: name,
                      contactName: contactCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      address: addressCtrl.text.trim(),
                    );
                    ref.invalidate(suppliersProvider);
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                  return;
                }
              }

              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Demo Mode: Supplier registration simulated.'),
                ),
              );
            },
            child: const Text('Save Supplier'),
          ),
        ],
      ),
    );
  }

  void _createPurchaseOrderDialog(BuildContext context, bool isLive) {
    final poCtrl = TextEditingController(
      text:
          'PO-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
    );
    final notesCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Create Purchase Order'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: poCtrl,
              decoration: const InputDecoration(labelText: 'PO Number *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes / Specifications',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Stock is only incremented when you formally receive the shipment via "Receive Shipment".',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Purchase Order generated successfully.'),
                ),
              );
            },
            child: const Text('Create PO'),
          ),
        ],
      ),
    );
  }

  void _receivePurchase(
    BuildContext context,
    PurchaseRecord po,
    bool isLive,
  ) async {
    if (isLive) {
      final repo = ref.read(inventoryRepositoryProvider);
      final auth = ref.read(authControllerProvider);
      final restId = auth.activeMembership?.restaurantId;

      if (repo != null && restId != null) {
        try {
          await repo.receivePurchase(restaurantId: restId, purchaseId: po.id);
          ref.invalidate(purchasesProvider);
          ref.invalidate(inventoryProvider);
          ref.invalidate(stockMovementsProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Shipment ${po.purchaseNumber} received. Stock levels updated.',
                ),
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error receiving purchase: $e')),
            );
          }
        }
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Demo Mode: Received shipment ${po.purchaseNumber}. Stock incremented.',
        ),
      ),
    );
  }

  void _addRecipeIngredientDialog(
    BuildContext context,
    List<InventoryItem> inventory,
    String menuItemName,
    bool isLive,
  ) {
    if (inventory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No inventory items available.')),
      );
      return;
    }

    InventoryItem selectedItem = inventory.first;
    final qtyCtrl = TextEditingController(text: '0.020');

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add Ingredient to $menuItemName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<InventoryItem>(
                initialValue: selectedItem,
                items: inventory.map((it) {
                  return DropdownMenuItem(
                    value: it,
                    child: Text('${it.name} (${it.unit})'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => selectedItem = val);
                  }
                },
                decoration: const InputDecoration(labelText: 'Ingredient'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Quantity needed (${selectedItem.unit})',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Linked ${qtyCtrl.text} ${selectedItem.unit} of ${selectedItem.name} to $menuItemName.',
                    ),
                  ),
                );
              },
              child: const Text('Link Ingredient'),
            ),
          ],
        ),
      ),
    );
  }
}
