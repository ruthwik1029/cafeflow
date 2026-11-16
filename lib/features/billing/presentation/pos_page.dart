import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/workspace.dart';
import '../../../core/services/backend.dart';
import '../../../core/sync/cafe_sync_service.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/widgets/cafe_components.dart';
import '../../../core/widgets/sync_status_badge.dart';
import '../../../shared/components/section_heading.dart';
import '../../auth/application/auth_controller.dart';
import '../../demo/application/demo_orders_controller.dart';
import '../../kitchen/data/supabase_kitchen_repository.dart';
import '../../menu/application/catalog_provider.dart';
import '../../menu/domain/catalog.dart';
import '../../menu/presentation/catalog_browser.dart';
import '../../orders/application/orders_provider.dart';
import '../../orders/data/supabase_order_repository.dart';
import '../../orders/domain/cafe_order.dart';
import '../../tables/application/tables_provider.dart';
import '../../tables/data/supabase_tables_repository.dart';
import '../../workspaces/domain/workspace_catalog.dart';
import '../../workspaces/presentation/workspace_page.dart';
import '../application/cart_controller.dart';
import '../data/supabase_payment_repository.dart';
import '../domain/payment_models.dart';
import 'checkout_dialog.dart';
import 'receipt_dialog.dart';

class PosPage extends ConsumerStatefulWidget {
  const PosPage({this.staff = false, super.key});
  final bool staff;
  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

class _PosPageState extends ConsumerState<PosPage> {
  String pane = 'Menu';
  String table = 'Takeaway';
  final notes = TextEditingController();
  final discount = TextEditingController();
  String? discountError;
  bool isSubmitting = false;

  String get scope => widget.staff ? 'staff' : 'cashier';

  @override
  void dispose() {
    notes.dispose();
    discount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider(scope));
    final catalogAsync = ref.watch(catalogProvider);
    final isDemo = catalogAsync.value?.isDemo ?? true;
    final backend = ref.watch(backendProvider);
    final auth = ref.watch(authControllerProvider);
    final isLive =
        backend.status == BackendStatus.initialized &&
        auth.activeMembership?.restaurantId != null &&
        !isDemo;

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDemo) const DemoNotice(),
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
                    Icons.cloud_done_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live POS Terminal · Connected to Supabase',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          WorkspaceHero(
            workspace: workspaceFor(
              widget.staff ? WorkspaceRole.staff : WorkspaceRole.cashier,
            ),
          ),
          const SizedBox(height: 24),
          SectionHeading(
            widget.staff ? 'Take an order' : 'Point of sale',
            subtitle: 'Good service starts with the little details.',
            action: const SyncStatusBadge(),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final menu = CatalogBrowser(
                onSelect: (product) {
                  if (!product.available) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('This item is unavailable.'),
                      ),
                    );
                    return;
                  }
                  try {
                    ref.read(cartProvider(scope).notifier).add(product);
                  } on StateError catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('This item is unavailable.'),
                      ),
                    );
                  }
                },
              );
              final summary = _cart(context, cart, isLive);
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: menu),
                        const SizedBox(width: 24),
                        SizedBox(width: 340, child: summary),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SegmentedButton<String>(
                          segments: [
                            const ButtonSegment(
                              value: 'Menu',
                              label: Text('Menu'),
                            ),
                            ButtonSegment(
                              value: 'Cart',
                              label: Text(
                                'Cart (${cart.lines.fold(0, (n, l) => n + l.quantity)})',
                              ),
                            ),
                          ],
                          selected: {pane},
                          onSelectionChanged: (value) =>
                              setState(() => pane = value.first),
                        ),
                        const SizedBox(height: 24),
                        pane == 'Menu' ? menu : summary,
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }

  Widget _cart(BuildContext context, CartState cart, bool isLive) {
    final controller = ref.read(cartProvider(scope).notifier);
    final tables = ref.watch(tablesProvider).value ?? [];
    final tableOptions = <String>[
      'Takeaway',
      ...tables.map((t) => t.tableNumber),
    ];
    if (!tableOptions.contains(table)) {
      tableOptions.add(table);
    }
    final activeTable = tables.where((t) => t.tableNumber == table).firstOrNull;

    return CafeCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Current order', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: table,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Table / service'),
            items: tableOptions.map((v) {
              final matching = tables
                  .where((t) => t.tableNumber == v)
                  .firstOrNull;
              final statusText = matching != null
                  ? ' (${matching.status.label})'
                  : '';
              return DropdownMenuItem(value: v, child: Text('$v$statusText'));
            }).toList(),
            onChanged: (v) {
              if (v != null) setState(() => table = v);
            },
          ),
          if (activeTable != null &&
              activeTable.currentOrderNumber != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.amber.shade900,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Table has active order (${activeTable.currentOrderNumber}). Adding items will send an incremental KOT ticket to the kitchen.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (cart.lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Your cart is empty. Select a product to begin.'),
            ),
          for (final line in cart.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 2,
                    children: [
                      IconButton(
                        tooltip: 'Decrease ${line.name}',
                        onPressed: () => controller.quantity(
                          line.productId,
                          line.quantity - 1,
                        ),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '${line.quantity}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      IconButton(
                        tooltip: 'Increase ${line.name}',
                        onPressed: () => controller.quantity(
                          line.productId,
                          line.quantity + 1,
                        ),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      Text('× ${money(line.unitMinor)}'),
                      const SizedBox(width: 8),
                      Text(
                        money(line.totalMinor),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (cart.lines.isNotEmpty) ...[
            TextField(
              controller: notes,
              decoration: const InputDecoration(
                labelText: 'Special instructions',
                hintText: 'e.g., Oat milk, dressing on side',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: discount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Discount (INR)',
                errorText: discountError,
                suffixIcon: IconButton(
                  tooltip: 'Apply discount',
                  icon: const Icon(Icons.check),
                  onPressed: () {
                    final value = parseMoney(discount.text);
                    if (value == null || value > cart.subtotalMinor) {
                      setState(
                        () => discountError =
                            'Enter a valid discount up to the subtotal.',
                      );
                      return;
                    }
                    controller.discount(value);
                    setState(() => discountError = null);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: cart.paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Payment method (preview)',
              ),
              items: [
                'Cash',
                'Card',
                'UPI',
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (value) => controller.payment(value!),
            ),
          ],
          const SizedBox(height: 24),
          _amount('Subtotal', money(cart.subtotalMinor)),
          if (cart.discountMinor > 0)
            _amount('Discount', '−${money(cart.discountMinor)}'),
          _amount(
            cart.taxIsInclusive
                ? '${cart.taxName} (Included)'
                : '${cart.taxName} (${(cart.taxBasisPoints / 100).toStringAsFixed(1)}%)',
            money(cart.taxMinor),
          ),
          if (cart.serviceChargeMinor > 0)
            _amount(cart.serviceChargeName, money(cart.serviceChargeMinor)),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _amount('Grand total', money(cart.totalMinor)),
          ),
          CafeButton(
            label: isLive
                ? 'Proceed to payment (Simulated)'
                : 'Checkout local order (Simulated)',
            onPressed: cart.lines.isEmpty || isSubmitting
                ? null
                : () => _review(context, cart, isLive),
          ),
          const SizedBox(height: 12),
          Text(
            'DEMO MODE: All payments and receipts are simulated for demonstration.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.amber.shade900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _amount(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Future<void> _review(
    BuildContext context,
    CartState cart,
    bool isLive,
  ) async {
    final submission = await CheckoutDialog.show(
      context,
      cart: cart,
      tableName: table,
      isLive: isLive,
      specialInstructions: notes.text.trim(),
    );

    if (submission == null || !mounted) return;

    if (isLive) {
      setState(() => isSubmitting = true);
      final repo = ref.read(orderRepositoryProvider);
      final paymentRepo = ref.read(paymentRepositoryProvider);
      final auth = ref.read(authControllerProvider);
      final restId = auth.activeMembership?.restaurantId;

      if (repo is SupabaseOrderRepository && restId != null) {
        try {
          final submissionItems = cart.lines.map((l) {
            return OrderSubmissionItem(
              menuItemId: l.productId,
              quantity: l.quantity,
            );
          }).toList();

          final idempotencyKey =
              'ord_${DateTime.now().millisecondsSinceEpoch}_${cart.totalMinor}';

          final tables = ref.read(tablesProvider).value ?? [];
          final matchingTable = tables
              .where((t) => t.tableNumber == table)
              .firstOrNull;
          String? tableSessionId;
          final orderType = table == 'Takeaway' ? 'TAKEAWAY' : 'DINE_IN';

          if (matchingTable != null) {
            tableSessionId = matchingTable.activeSessionId;
            if (tableSessionId == null) {
              final tablesRepo = ref.read(tablesRepositoryProvider);
              if (tablesRepo != null) {
                try {
                  final sessRes = await tablesRepo.openSession(
                    restaurantId: restId,
                    tableId: matchingTable.id,
                  );
                  tableSessionId = sessRes['session_id'] as String?;
                  ref.invalidate(tablesProvider);
                } catch (_) {}
              }
            }
          }

          final kitchenRepo = ref.read(kitchenRepositoryProvider);
          Map<String, dynamic>? kotResult;
          if (kitchenRepo != null) {
            try {
              kotResult = await kitchenRepo.createOrderWithKot(
                restaurantId: restId,
                tableName: table,
                tableSessionId: tableSessionId,
                orderType: orderType,
                items: submissionItems,
                specialInstructions: notes.text.trim(),
                discountMinor: cart.discountMinor,
                discountReason: cart.discountReason,
                idempotencyKey: idempotencyKey,
              );
            } catch (_) {}
          }

          final result = kotResult != null
              ? CreatedOrderResult(
                  id: kotResult['order_id'] as String,
                  orderNumber: kotResult['order_number'] as String,
                  subtotalMinor: (kotResult['subtotal_minor'] as num).toInt(),
                  taxMinor: (kotResult['tax_minor'] as num).toInt(),
                  totalMinor: (kotResult['total_minor'] as num).toInt(),
                  discountMinor: cart.discountMinor,
                )
              : await repo.createOrder(
                  restaurantId: restId,
                  tableName: table,
                  items: submissionItems,
                  specialInstructions: notes.text.trim(),
                  discountMinor: cart.discountMinor,
                  discountReason: cart.discountReason,
                  idempotencyKey: idempotencyKey,
                );

          PaymentRecord? paymentRecord;
          if (submission.settleImmediately) {
            final payIdempotency =
                'pay_${DateTime.now().millisecondsSinceEpoch}_${result.id}';
            final payResult = await paymentRepo.recordPayment(
              restaurantId: restId,
              orderId: result.id,
              paymentMethodCode: submission.paymentMethodCode,
              amountMinor: submission.amountMinor,
              tenderedAmountMinor: submission.tenderedAmountMinor,
              transactionReference: submission.transactionReference,
              idempotencyKey: payIdempotency,
            );

            paymentRecord = PaymentRecord(
              id: payResult.paymentId,
              orderId: result.id,
              restaurantId: restId,
              paymentMethodCode: submission.paymentMethodCode,
              amountMinor: submission.amountMinor,
              status: 'COMPLETED',
              createdAt: DateTime.now(),
              tenderedAmountMinor: submission.tenderedAmountMinor,
              changeDueMinor: payResult.changeDueMinor,
              transactionReference: submission.transactionReference,
            );
          }

          ref.read(cartProvider(scope).notifier).clear();
          notes.clear();
          discount.clear();
          ref.invalidate(ordersProvider);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  submission.settleImmediately
                      ? 'Order ${result.orderNumber} placed & settled (${submission.paymentMethodCode}).'
                      : 'Order ${result.orderNumber} placed (Unpaid).',
                ),
              ),
            );

            // Construct order for receipt preview
            final createdOrder = CafeOrder(
              id: result.id,
              number: result.orderNumber,
              createdAt: DateTime.now(),
              lines: cart.lines,
              status: OrderStatus.newOrder,
              financialStatus: submission.settleImmediately
                  ? OrderFinancialStatus.paid
                  : OrderFinancialStatus.unpaid,
              table: table,
              instructions: notes.text.trim(),
              taxMinor: result.taxMinor,
              discountMinor: result.discountMinor,
              serviceChargeMinor: result.serviceChargeMinor,
              paidMinor: submission.settleImmediately
                  ? submission.amountMinor
                  : 0,
              taxName: cart.taxName,
              taxRateBps: cart.taxBasisPoints,
              taxIsInclusive: cart.taxIsInclusive,
              discountReason: cart.discountReason,
            );

            await ReceiptDialog.show(
              context,
              order: createdOrder,
              payment: paymentRecord,
              restaurantName:
                  auth.activeMembership?.restaurantName ??
                  'CafeFlow Flagship Bistro',
              cashierName: auth.user?.fullName ?? 'Counter Cashier',
            );
          }
        } catch (e) {
          // If network / cloud failure occurred, safely fall back to offline-first local persistence
          try {
            final syncService = ref.read(syncServiceProvider);
            final tables = ref.read(tablesProvider).value ?? [];
            final matchingTable = tables
                .where((t) => t.tableNumber == table)
                .firstOrNull;
            final localOrderId = await syncService.saveOfflineOrder(
              restaurantId: restId,
              tableName: table,
              tableSessionId: matchingTable?.activeSessionId,
              orderType: table == 'Takeaway' ? 'TAKEAWAY' : 'DINE_IN',
              lines: cart.lines,
              discountMinor: cart.discountMinor,
              discountReason: cart.discountReason,
              specialInstructions: notes.text.trim(),
              taxMinor: cart.taxMinor,
              serviceChargeMinor: cart.serviceChargeMinor,
              taxName: cart.taxName,
              taxRateBps: cart.taxBasisPoints,
              taxIsInclusive: cart.taxIsInclusive,
            );

            PaymentRecord? offlinePayment;
            if (submission.settleImmediately) {
              await syncService.recordOfflinePayment(
                restaurantId: restId,
                localOrderId: localOrderId,
                paymentMethodCode: submission.paymentMethodCode,
                amountMinor: submission.amountMinor,
                tenderedAmountMinor: submission.tenderedAmountMinor,
                transactionReference: submission.transactionReference,
                notes: submission.paymentMethodCode.toUpperCase() == 'CASH'
                    ? 'Offline Cash Settlement'
                    : 'Offline Digital Payment (Requires Reconciliation)',
              );

              offlinePayment = PaymentRecord(
                id: 'local_pay_${DateTime.now().millisecondsSinceEpoch}',
                orderId: localOrderId,
                restaurantId: restId,
                paymentMethodCode: submission.paymentMethodCode,
                amountMinor: submission.amountMinor,
                status: submission.paymentMethodCode.toUpperCase() == 'CASH'
                    ? 'PENDING_SYNC'
                    : 'PENDING_RECONCILIATION',
                createdAt: DateTime.now(),
                tenderedAmountMinor: submission.tenderedAmountMinor,
                changeDueMinor: submission.changeDueMinor,
                transactionReference: submission.transactionReference,
              );
            }

            ref.read(cartProvider(scope).notifier).clear();
            notes.clear();
            discount.clear();
            ref.invalidate(ordersProvider);

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Offline: Order saved locally. Queued for automatic cloud synchronization.',
                  ),
                  backgroundColor: Colors.amber.shade900,
                ),
              );

              final offlineOrder = CafeOrder(
                id: localOrderId,
                number:
                    'OFFLINE-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
                createdAt: DateTime.now(),
                lines: cart.lines,
                status: OrderStatus.newOrder,
                financialStatus: submission.settleImmediately
                    ? OrderFinancialStatus.paid
                    : OrderFinancialStatus.unpaid,
                syncStatus: SyncStatus.pending,
                table: table,
                instructions: notes.text.trim(),
                taxMinor: cart.taxMinor,
                discountMinor: cart.discountMinor,
                serviceChargeMinor: cart.serviceChargeMinor,
                paidMinor: submission.settleImmediately
                    ? submission.amountMinor
                    : 0,
                taxName: cart.taxName,
                taxRateBps: cart.taxBasisPoints,
                taxIsInclusive: cart.taxIsInclusive,
                discountReason: cart.discountReason,
              );

              await ReceiptDialog.show(
                context,
                order: offlineOrder,
                payment: offlinePayment,
                restaurantName:
                    auth.activeMembership?.restaurantName ??
                    'CafeFlow Flagship Bistro',
                cashierName:
                    '${auth.user?.fullName ?? "Counter Cashier"} (Offline)',
              );
            }
          } catch (offlineErr) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Order submission failed: $e. Offline save also failed: $offlineErr',
                  ),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
          }
        } finally {
          if (mounted) setState(() => isSubmitting = false);
        }
        return;
      }
    }

    // Demo fallback
    final order = ref
        .read(demoOrdersProvider.notifier)
        .add(
          lines: cart.lines,
          table: table,
          instructions: notes.text.trim(),
          taxMinor: cart.taxMinor,
          discountMinor: cart.discountMinor,
        );
    ref.read(cartProvider(scope).notifier).clear();
    notes.clear();
    discount.clear();

    if (context.mounted) {
      PaymentRecord? demoPayment;
      if (submission.settleImmediately) {
        demoPayment = PaymentRecord(
          id: 'demo-pay-001',
          orderId: order.id,
          restaurantId: 'demo',
          paymentMethodCode: submission.paymentMethodCode,
          amountMinor: submission.amountMinor,
          status: 'COMPLETED',
          createdAt: DateTime.now(),
          tenderedAmountMinor: submission.tenderedAmountMinor,
          changeDueMinor: submission.changeDueMinor,
          transactionReference: submission.transactionReference,
        );
      }

      await ReceiptDialog.show(
        context,
        order: order,
        payment: demoPayment,
        restaurantName: 'CafeFlow Flagship Bistro (Demo)',
      );
    }
  }
}
