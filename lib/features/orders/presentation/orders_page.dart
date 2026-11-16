import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/workspace.dart';
import '../../../core/services/backend.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/widgets/cafe_components.dart';
import '../../../core/widgets/sync_status_badge.dart';
import '../../../shared/components/section_heading.dart';
import '../../auth/application/auth_controller.dart';
import '../../billing/application/payment_provider.dart';
import '../../billing/domain/payment_models.dart';
import '../../billing/presentation/receipt_dialog.dart';
import '../../demo/application/demo_orders_controller.dart';
import '../../kitchen/application/kitchen_provider.dart';
import '../../kitchen/data/supabase_kitchen_repository.dart';
import '../../menu/domain/catalog.dart';
import '../../workspaces/domain/workspace_catalog.dart';
import '../../workspaces/presentation/workspace_page.dart';
import '../application/orders_provider.dart';
import '../data/supabase_order_repository.dart';
import '../domain/cafe_order.dart';

class OrderTicket extends StatelessWidget {
  const OrderTicket({
    required this.order,
    this.onAdvance,
    this.onSettlePayment,
    this.onViewReceipt,
    this.onRefund,
    super.key,
  });

  final CafeOrder order;
  final VoidCallback? onAdvance;
  final VoidCallback? onSettlePayment;
  final VoidCallback? onViewReceipt;
  final VoidCallback? onRefund;

  @override
  Widget build(BuildContext context) => CafeCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Text(order.number, style: Theme.of(context).textTheme.titleLarge),
            Chip(
              avatar: Icon(switch (order.status) {
                OrderStatus.newOrder => Icons.fiber_new,
                OrderStatus.preparing => Icons.soup_kitchen_outlined,
                OrderStatus.ready => Icons.check_circle_outline,
                _ => Icons.receipt_long,
              }, size: 18),
              backgroundColor: order.status == OrderStatus.ready
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : Theme.of(context).colorScheme.primaryContainer,
              label: Text(order.status.label),
            ),
            Chip(
              avatar: Icon(switch (order.financialStatus) {
                OrderFinancialStatus.paid => Icons.check_circle,
                OrderFinancialStatus.unpaid => Icons.hourglass_top,
                OrderFinancialStatus.partiallyPaid => Icons.pie_chart,
                OrderFinancialStatus.refunded => Icons.replay,
                OrderFinancialStatus.partiallyRefunded => Icons.replay,
                OrderFinancialStatus.paymentFailed => Icons.error_outline,
              }, size: 16),
              backgroundColor: switch (order.financialStatus) {
                OrderFinancialStatus.paid => Colors.green.shade100,
                OrderFinancialStatus.unpaid => Colors.amber.shade100,
                OrderFinancialStatus.partiallyPaid => Colors.blue.shade100,
                OrderFinancialStatus.refunded => Colors.red.shade100,
                _ => Colors.grey.shade200,
              },
              label: Text(
                order.financialStatus.label,
                style: TextStyle(
                  color: switch (order.financialStatus) {
                    OrderFinancialStatus.paid => Colors.green.shade900,
                    OrderFinancialStatus.unpaid => Colors.amber.shade900,
                    OrderFinancialStatus.partiallyPaid => Colors.blue.shade900,
                    OrderFinancialStatus.refunded => Colors.red.shade900,
                    _ => Colors.black87,
                  },
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (order.syncStatus != SyncStatus.synced)
              Chip(
                avatar: Icon(
                  switch (order.syncStatus) {
                    SyncStatus.pending => Icons.cloud_upload_outlined,
                    SyncStatus.processing => Icons.sync,
                    SyncStatus.failed => Icons.sync_problem,
                    SyncStatus.conflict => Icons.warning_amber_rounded,
                    _ => Icons.cloud_queue,
                  },
                  size: 16,
                  color: switch (order.syncStatus) {
                    SyncStatus.failed ||
                    SyncStatus.conflict => Colors.red.shade800,
                    _ => Colors.orange.shade800,
                  },
                ),
                backgroundColor: switch (order.syncStatus) {
                  SyncStatus.failed ||
                  SyncStatus.conflict => Colors.red.shade50,
                  _ => Colors.amber.shade50,
                },
                label: Text(
                  order.syncStatus.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: switch (order.syncStatus) {
                      SyncStatus.failed ||
                      SyncStatus.conflict => Colors.red.shade900,
                      _ => Colors.orange.shade900,
                    },
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${order.table} · ${order.createdAt.day}/${order.createdAt.month} ${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}',
        ),
        const SizedBox(height: 16),
        for (final line in order.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${line.quantity} × ${line.name}'),
          ),
        if (order.instructions.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(order.instructions),
          ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              money(order.totalMinor),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (order.paidMinor > 0)
              Text(
                'Paid: ${money(order.paidMinor)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: order.outstandingMinor > 0
                      ? Colors.amber.shade900
                      : Colors.green.shade800,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (onAdvance != null)
              FilledButton(
                onPressed: onAdvance,
                child: Text(
                  order.status == OrderStatus.newOrder
                      ? 'Start preparing'
                      : 'Mark ready',
                ),
              ),
            if (onSettlePayment != null && !order.isFullyPaid)
              OutlinedButton.icon(
                icon: const Icon(Icons.payment, size: 16),
                label: Text(
                  'Settle ${money(order.outstandingMinor > 0 ? order.outstandingMinor : order.totalMinor)}',
                ),
                onPressed: onSettlePayment,
              ),
            if (onViewReceipt != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.receipt_long, size: 16),
                label: const Text('Receipt'),
                onPressed: onViewReceipt,
              ),
            if (onRefund != null && (order.paidMinor > 0))
              TextButton.icon(
                icon: const Icon(Icons.replay, size: 16),
                label: const Text('Refund'),
                onPressed: onRefund,
              ),
          ],
        ),
      ],
    ),
  );
}

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({this.activeOnly = false, super.key});
  final bool activeOnly;
  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  OrderStatus? filter;

  Future<void> _advanceOrder(CafeOrder order, bool isLive) async {
    final nextStatus = switch (order.status) {
      OrderStatus.newOrder => OrderStatus.preparing,
      OrderStatus.preparing => OrderStatus.ready,
      OrderStatus.ready => OrderStatus.completed,
      _ => null,
    };
    if (nextStatus == null) return;

    if (isLive) {
      final repo = ref.read(orderRepositoryProvider);
      if (repo is SupabaseOrderRepository) {
        try {
          await repo.updateStatus(order.id, nextStatus);
          ref.invalidate(ordersProvider);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Order ${order.number} advanced to ${nextStatus.label}',
                ),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Status update failed: $e')));
          }
        }
        return;
      }
    }
    ref.read(demoOrdersProvider.notifier).advance(order.id);
  }

  Future<void> _viewReceipt(CafeOrder order, bool isLive) async {
    PaymentRecord? latestPayment;
    if (isLive) {
      final auth = ref.read(authControllerProvider);
      final restId = auth.activeMembership?.restaurantId;
      if (restId != null) {
        try {
          final paymentRepo = ref.read(paymentRepositoryProvider);
          final payments = await paymentRepo.fetchPaymentsForOrder(
            restaurantId: restId,
            orderId: order.id,
          );
          if (payments.isNotEmpty) {
            latestPayment = payments.first;
          }
        } catch (_) {}
      }
    }
    if (mounted) {
      await ReceiptDialog.show(context, order: order, payment: latestPayment);
    }
  }

  Future<void> _settlePayment(CafeOrder order, bool isLive) async {
    final outstandingMinor = order.outstandingMinor > 0
        ? order.outstandingMinor
        : order.totalMinor;
    String selectedMethod = 'CASH';
    final amountController = TextEditingController(
      text: (outstandingMinor / 100).toStringAsFixed(2),
    );
    final tenderedController = TextEditingController(
      text: (outstandingMinor / 100).toStringAsFixed(2),
    );
    final refController = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final parsedAmount =
              parseMoney(amountController.text) ?? outstandingMinor;
          final parsedTendered =
              parseMoney(tenderedController.text) ?? parsedAmount;
          final changeDue =
              selectedMethod == 'CASH' && parsedTendered > parsedAmount
              ? parsedTendered - parsedAmount
              : 0;

          return AlertDialog(
            title: Row(
              children: [
                Expanded(child: Text('Settle Payment · ${order.number}')),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'SIMULATED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 16,
                            color: Colors.orange,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'DEMO / SIMULATED PAYMENT: Simulated transaction only.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Table: ${order.table}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Order Total: ${money(order.totalMinor)} · Balance Due: ${money(outstandingMinor)}',
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedMethod,
                      decoration: const InputDecoration(
                        labelText: 'Payment Method',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'CASH',
                          child: Text('Cash (Simulated)'),
                        ),
                        DropdownMenuItem(
                          value: 'UPI',
                          child: Text('UPI / QR (Simulated)'),
                        ),
                        DropdownMenuItem(
                          value: 'CARD',
                          child: Text('Credit / Debit Card (Simulated)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedMethod = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Payment Amount (₹)',
                        prefixText: '₹ ',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    if (selectedMethod == 'CASH') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: tenderedController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount Tendered (₹)',
                          prefixText: '₹ ',
                        ),
                        onChanged: (_) => setDialogState(() {
                          error = null;
                        }),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('Exact'),
                            onPressed: () {
                              setDialogState(() {
                                tenderedController.text = (parsedAmount / 100)
                                    .toStringAsFixed(2);
                              });
                            },
                          ),
                          ActionChip(
                            label: const Text('+₹100'),
                            onPressed: () {
                              setDialogState(() {
                                tenderedController.text =
                                    ((parsedTendered + 10000) / 100)
                                        .toStringAsFixed(2);
                              });
                            },
                          ),
                          ActionChip(
                            label: const Text('+₹500'),
                            onPressed: () {
                              setDialogState(() {
                                tenderedController.text =
                                    ((parsedTendered + 50000) / 100)
                                        .toStringAsFixed(2);
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Change Due:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              money(changeDue),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: refController,
                        decoration: InputDecoration(
                          labelText: selectedMethod == 'UPI'
                              ? 'UPI UTR / Reference'
                              : 'Card Auth / Ref Code',
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final amountMinor = parseMoney(amountController.text);
                  if (amountMinor == null || amountMinor <= 0) {
                    setDialogState(
                      () => error = 'Enter a valid payment amount.',
                    );
                    return;
                  }
                  if (amountMinor > outstandingMinor) {
                    setDialogState(
                      () => error = 'Amount cannot exceed outstanding balance.',
                    );
                    return;
                  }
                  int? tenderedMinor;
                  if (selectedMethod == 'CASH') {
                    tenderedMinor = parseMoney(tenderedController.text);
                    if (tenderedMinor == null || tenderedMinor < amountMinor) {
                      setDialogState(
                        () => error = 'Tendered amount must be at least the payment amount.',
                      );
                      return;
                    }
                  }

                  Navigator.of(dialogCtx).pop();

                  if (isLive) {
                    final auth = ref.read(authControllerProvider);
                    final restId = auth.activeMembership?.restaurantId;
                    if (restId != null) {
                      try {
                        final paymentRepo = ref.read(paymentRepositoryProvider);
                        final result = await paymentRepo.recordPayment(
                          restaurantId: restId,
                          orderId: order.id,
                          paymentMethodCode: selectedMethod,
                          amountMinor: amountMinor,
                          tenderedAmountMinor: tenderedMinor,
                          transactionReference:
                              refController.text.trim().isEmpty
                              ? null
                              : refController.text.trim(),
                        );
                        ref.invalidate(ordersProvider);
                        ref.invalidate(financialReportProvider);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Payment of ${money(amountMinor)} recorded successfully.',
                              ),
                            ),
                          );
                          await ReceiptDialog.show(
                            context,
                            order: order.withFinancialStatus(
                              financialStatus: result.financialStatus,
                              paidMinor: result.paidAmountMinor,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Payment failed: $e')),
                          );
                        }
                      }
                      return;
                    }
                  }

                  // Fallback demo mode simulation
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Simulated payment of ${money(amountMinor)}',
                        ),
                      ),
                    );
                    await ReceiptDialog.show(
                      context,
                      order: order.withFinancialStatus(
                        financialStatus: OrderFinancialStatus.paid,
                        paidMinor: order.totalMinor,
                      ),
                    );
                  }
                },
                child: const Text('Record Simulated Payment'),
              ),
            ],
          );
        },
      ),
    );

    amountController.dispose();
    tenderedController.dispose();
    refController.dispose();
  }

  Future<void> _refundOrder(CafeOrder order, bool isLive) async {
    final maxRefundableMinor = order.paidMinor - order.refundedMinor;
    if (maxRefundableMinor <= 0) return;

    final amountController = TextEditingController(
      text: (maxRefundableMinor / 100).toStringAsFixed(2),
    );
    final reasonController = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Expanded(child: Text('Process Refund · ${order.number}')),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'SIMULATED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: Colors.orange,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'DEMO / SIMULATED REFUND: Simulated refund only. No money transferred.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text('Total Paid: ${money(order.paidMinor)}'),
                if (order.refundedMinor > 0)
                  Text('Already Refunded: ${money(order.refundedMinor)}'),
                Text(
                  'Max Refundable: ${money(maxRefundableMinor)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Refund Amount (₹)',
                    prefixText: '₹ ',
                  ),
                  onChanged: (_) => setDialogState(() => error = null),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason for Refund',
                    hintText:
                        'Customer return, item unavailable, billing issue',
                  ),
                  onChanged: (_) => setDialogState(() => error = null),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () async {
                final amountMinor = parseMoney(amountController.text);
                final reason = reasonController.text.trim();
                if (amountMinor == null || amountMinor <= 0) {
                  setDialogState(() => error = 'Enter a valid refund amount.');
                  return;
                }
                if (amountMinor > maxRefundableMinor) {
                  setDialogState(
                    () => error = 'Refund cannot exceed max refundable amount.',
                  );
                  return;
                }
                if (reason.isEmpty) {
                  setDialogState(
                    () => error = 'Refund reason is mandatory for audit trail.',
                  );
                  return;
                }

                Navigator.of(dialogCtx).pop();

                if (isLive) {
                  final auth = ref.read(authControllerProvider);
                  final restId = auth.activeMembership?.restaurantId;
                  if (restId != null) {
                    try {
                      final paymentRepo = ref.read(paymentRepositoryProvider);
                      final payments = await paymentRepo.fetchPaymentsForOrder(
                        restaurantId: restId,
                        orderId: order.id,
                      );
                      if (payments.isEmpty) {
                        throw Exception(
                          'No recorded payment found to refund against.',
                        );
                      }
                      final targetPayment = payments.first;
                      await paymentRepo.refundPayment(
                        restaurantId: restId,
                        orderId: order.id,
                        paymentId: targetPayment.id,
                        refundAmountMinor: amountMinor,
                        reason: reason,
                      );
                      ref.invalidate(ordersProvider);
                      ref.invalidate(financialReportProvider);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Refund of ${money(amountMinor)} processed successfully.',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Refund failed: $e')),
                        );
                      }
                    }
                    return;
                  }
                }

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Simulated refund of ${money(amountMinor)}',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Authorize Simulated Refund'),
            ),
          ],
        ),
      ),
    );

    amountController.dispose();
    reasonController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<CafeOrder> allOrders =
        ref.watch(ordersProvider).value ?? ref.watch(demoOrdersProvider);
    final backend = ref.watch(backendProvider);
    final auth = ref.watch(authControllerProvider);
    final isLive =
        backend.status == BackendStatus.initialized &&
        auth.activeMembership?.restaurantId != null;
    final canRefund =
        auth.activeRole == WorkspaceRole.owner ||
        auth.activeRole == WorkspaceRole.admin;

    final orders = allOrders
        .where(
          (o) =>
              (filter == null || o.status == filter) &&
              (!widget.activeOnly ||
                  ![
                    OrderStatus.completed,
                    OrderStatus.cancelled,
                  ].contains(o.status)),
        )
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
                    Icons.cloud_done_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Orders · Synchronized with Supabase',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          SectionHeading(
            widget.activeOnly ? 'Active orders' : 'Orders',
            action: const SyncStatusBadge(),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All orders'),
                selected: filter == null,
                onSelected: (_) => setState(() => filter = null),
              ),
              for (final status in OrderStatus.values)
                ChoiceChip(
                  label: Text(status.label),
                  selected: filter == status,
                  onSelected: (_) => setState(() => filter = status),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (orders.isEmpty)
            const CafeEmptyState(
              title: 'No orders in this view',
              message: 'Try another status filter.',
            )
          else
            AdaptiveColumns(
              minWidth: 280,
              children: orders.map((o) {
                final canAdvance =
                    o.status != OrderStatus.completed &&
                    o.status != OrderStatus.cancelled;
                return OrderTicket(
                  order: o,
                  onAdvance: canAdvance ? () => _advanceOrder(o, isLive) : null,
                  onSettlePayment: !o.isFullyPaid
                      ? () => _settlePayment(o, isLive)
                      : null,
                  onViewReceipt: () => _viewReceipt(o, isLive),
                  onRefund: (canRefund && o.paidMinor > o.refundedMinor)
                      ? () => _refundOrder(o, isLive)
                      : null,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

/// Kitchen Order Ticket (KOT) Card.
/// Designed specifically for kitchen staff display with item-level status controls
/// and elapsed preparation timers. Strictly avoids displaying billing or payment information.
class KotTicketCard extends StatelessWidget {
  const KotTicketCard({
    required this.ticket,
    this.onAdvanceTicket,
    this.onUpdateItemStatus,
    this.onCancelItem,
    super.key,
  });

  final KitchenOrderTicket ticket;
  final VoidCallback? onAdvanceTicket;
  final void Function(KotItem item, KotStatus nextStatus)? onUpdateItemStatus;
  final void Function(KotItem item)? onCancelItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDelayed = ticket.age.inMinutes >= 15;

    return CafeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${ticket.kotNumber} (#${ticket.sequenceNumber})',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Chip(
                backgroundColor: theme.colorScheme.primaryContainer,
                avatar: const Icon(Icons.table_restaurant, size: 16),
                label: Text(ticket.tableName),
              ),
              if (ticket.stationName != null)
                Chip(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  avatar: const Icon(Icons.soup_kitchen_outlined, size: 16),
                  label: Text(ticket.stationName!),
                ),
              Chip(
                avatar: Icon(
                  isDelayed
                      ? Icons.warning_amber_rounded
                      : Icons.timer_outlined,
                  size: 16,
                  color: isDelayed ? Colors.red.shade900 : Colors.black87,
                ),
                backgroundColor: isDelayed
                    ? Colors.red.shade100
                    : Colors.grey.shade200,
                label: Text(
                  ticket.elapsedLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDelayed ? Colors.red.shade900 : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (ticket.specialInstructions.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.note_alt_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ticket.specialInstructions,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(),
          const SizedBox(height: 6),
          for (final item in ticket.items) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.quantity} × ${item.itemName}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: item.status == KotStatus.cancelled
                                ? TextDecoration.lineThrough
                                : null,
                            color: item.status == KotStatus.cancelled
                                ? Colors.grey
                                : null,
                          ),
                        ),
                        if (item.selectedVariant != null)
                          Text(
                            'Variant: ${item.selectedVariant}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        if (item.selectedAddons.isNotEmpty)
                          Text(
                            'Addons: ${item.selectedAddons.join(', ')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        if (item.notes.isNotEmpty)
                          Text(
                            'Note: ${item.notes}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        if (item.status == KotStatus.cancelled &&
                            item.cancelReason != null)
                          Text(
                            'Cancelled: ${item.cancelReason}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red.shade800,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: switch (item.status) {
                            KotStatus.newOrder ||
                            KotStatus.accepted => Colors.blue.shade50,
                            KotStatus.preparing => Colors.amber.shade50,
                            KotStatus.ready => Colors.green.shade50,
                            KotStatus.served => Colors.grey.shade200,
                            KotStatus.cancelled => Colors.red.shade50,
                          },
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: switch (item.status) {
                              KotStatus.newOrder ||
                              KotStatus.accepted => Colors.blue.shade200,
                              KotStatus.preparing => Colors.amber.shade200,
                              KotStatus.ready => Colors.green.shade200,
                              KotStatus.served => Colors.grey.shade400,
                              KotStatus.cancelled => Colors.red.shade200,
                            },
                          ),
                        ),
                        child: Text(
                          item.status.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: switch (item.status) {
                              KotStatus.newOrder ||
                              KotStatus.accepted => Colors.blue.shade900,
                              KotStatus.preparing => Colors.amber.shade900,
                              KotStatus.ready => Colors.green.shade900,
                              KotStatus.served => Colors.grey.shade800,
                              KotStatus.cancelled => Colors.red.shade900,
                            },
                          ),
                        ),
                      ),
                      if (item.status != KotStatus.served &&
                          item.status != KotStatus.cancelled) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.status == KotStatus.newOrder ||
                                item.status == KotStatus.accepted)
                              IconButton(
                                icon: const Icon(
                                  Icons.soup_kitchen_outlined,
                                  size: 18,
                                ),
                                tooltip: 'Start preparing',
                                onPressed: onUpdateItemStatus != null
                                    ? () => onUpdateItemStatus!(
                                        item,
                                        KotStatus.preparing,
                                      )
                                    : null,
                              )
                            else if (item.status == KotStatus.preparing)
                              IconButton(
                                icon: const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: Colors.green,
                                ),
                                tooltip: 'Mark ready',
                                onPressed: onUpdateItemStatus != null
                                    ? () => onUpdateItemStatus!(
                                        item,
                                        KotStatus.ready,
                                      )
                                    : null,
                              )
                            else if (item.status == KotStatus.ready)
                              IconButton(
                                icon: const Icon(
                                  Icons.done_all,
                                  size: 18,
                                  color: Colors.blue,
                                ),
                                tooltip: 'Mark served',
                                onPressed: onUpdateItemStatus != null
                                    ? () => onUpdateItemStatus!(
                                        item,
                                        KotStatus.served,
                                      )
                                    : null,
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.red,
                              ),
                              tooltip: 'Cancel item',
                              onPressed: onCancelItem != null
                                  ? () => onCancelItem!(item)
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (onAdvanceTicket != null) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onAdvanceTicket,
                child: Text(
                  ticket.status == KotStatus.newOrder ||
                          ticket.status == KotStatus.accepted
                      ? 'Start preparing ticket'
                      : ticket.status == KotStatus.preparing
                      ? 'Mark ticket ready'
                      : 'Mark ticket served',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class KitchenPage extends ConsumerStatefulWidget {
  const KitchenPage({this.incomingOnly = false, super.key});
  final bool incomingOnly;

  @override
  ConsumerState<KitchenPage> createState() => _KitchenPageState();
}

class _KitchenPageState extends ConsumerState<KitchenPage> {
  String? selectedStationId;

  Future<void> _advanceTicket(KitchenOrderTicket ticket) async {
    final nextStatus = switch (ticket.status) {
      KotStatus.newOrder || KotStatus.accepted => KotStatus.preparing,
      KotStatus.preparing => KotStatus.ready,
      KotStatus.ready => KotStatus.served,
      _ => null,
    };
    if (nextStatus == null) return;

    final auth = ref.read(authControllerProvider);
    final restId = auth.activeMembership?.restaurantId;
    if (restId == null) return;

    final repo = ref.read(kitchenRepositoryProvider);
    if (repo != null) {
      try {
        await repo.updateKotStatus(
          restaurantId: restId,
          kotId: ticket.id,
          status: nextStatus,
        );
        ref.invalidate(activeKotsProvider);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update ticket: $e')),
          );
        }
      }
    }
  }

  Future<void> _updateItemStatus(KotItem item, KotStatus status) async {
    final auth = ref.read(authControllerProvider);
    final restId = auth.activeMembership?.restaurantId;
    if (restId == null) return;

    final repo = ref.read(kitchenRepositoryProvider);
    if (repo != null) {
      try {
        await repo.updateKotItemStatus(
          restaurantId: restId,
          kotItemId: item.id,
          status: status,
        );
        ref.invalidate(activeKotsProvider);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to update item: $e')));
        }
      }
    }
  }

  Future<void> _cancelItem(KotItem item) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Cancel Item · ${item.itemName}'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason for cancellation *',
            hintText: 'e.g. 86 / Out of stock, Customer request',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Confirm Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true && reasonCtrl.text.trim().isNotEmpty) {
      final auth = ref.read(authControllerProvider);
      final restId = auth.activeMembership?.restaurantId;
      if (restId == null) return;

      final repo = ref.read(kitchenRepositoryProvider);
      if (repo != null) {
        try {
          await repo.updateKotItemStatus(
            restaurantId: restId,
            kotItemId: item.id,
            status: KotStatus.cancelled,
            cancelReason: reasonCtrl.text.trim(),
          );
          ref.invalidate(activeKotsProvider);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to cancel item: $e')),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<CafeOrder> allOrders =
        ref.watch(ordersProvider).value ?? ref.watch(demoOrdersProvider);
    final backend = ref.watch(backendProvider);
    final auth = ref.watch(authControllerProvider);
    final isLive =
        backend.status == BackendStatus.initialized &&
        auth.activeMembership?.restaurantId != null;

    final stations = ref.watch(kitchenStationsProvider).value ?? [];
    final liveKots =
        ref
            .watch(activeKotsProvider(KotFilter(stationId: selectedStationId)))
            .value ??
        [];
    final hasLiveKots = isLive && liveKots.isNotEmpty;

    final statuses = widget.incomingOnly
        ? [OrderStatus.newOrder]
        : [OrderStatus.newOrder, OrderStatus.preparing, OrderStatus.ready];

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
                    Icons.soup_kitchen_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Kitchen Display · Realtime Subscribed to Orders & KOTs',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          WorkspaceHero(workspace: workspaceFor(WorkspaceRole.kitchen)),
          const SizedBox(height: 24),
          const SectionHeading(
            'Kitchen display',
            subtitle: 'Every order. A clear next step.',
            action: SyncStatusBadge(),
          ),

          // Kitchen Station Filter
          if (stations.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All Stations'),
                  selected: selectedStationId == null,
                  onSelected: (_) => setState(() => selectedStationId = null),
                ),
                for (final st in stations)
                  ChoiceChip(
                    label: Text(st.name),
                    selected: selectedStationId == st.id,
                    onSelected: (_) =>
                        setState(() => selectedStationId = st.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          AdaptiveColumns(
            minWidth: 290,
            children: [
              for (final status in statuses)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasLiveKots) ...[
                      // Live KOT Columns
                      Builder(
                        builder: (ctx) {
                          final kotsInCol = liveKots.where((k) {
                            if (status == OrderStatus.newOrder) {
                              return k.status == KotStatus.newOrder ||
                                  k.status == KotStatus.accepted;
                            } else if (status == OrderStatus.preparing) {
                              return k.status == KotStatus.preparing;
                            } else {
                              return k.status == KotStatus.ready;
                            }
                          }).toList();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${status.label} orders · ${kotsInCol.length}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 18),
                              if (kotsInCol.isEmpty)
                                const CafeEmptyState(
                                  title: 'All clear',
                                  message: 'No tickets in this column.',
                                ),
                              for (final ticket in kotsInCol)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: KotTicketCard(
                                    ticket: ticket,
                                    onAdvanceTicket: status == OrderStatus.ready
                                        ? () => _advanceTicket(ticket)
                                        : () => _advanceTicket(ticket),
                                    onUpdateItemStatus: _updateItemStatus,
                                    onCancelItem: _cancelItem,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ] else ...[
                      // Demo Orders Column Fallback
                      Text(
                        '${status.label} orders · ${allOrders.where((o) => o.status == status).length}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 18),
                      if (!allOrders.any((o) => o.status == status))
                        const CafeEmptyState(
                          title: 'All clear',
                          message: 'No tickets in this column.',
                        ),
                      for (final order in allOrders.where(
                        (o) => o.status == status,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: OrderTicket(
                            order: order,
                            onAdvance: status == OrderStatus.ready
                                ? null
                                : () async {
                                    final nextStatus =
                                        status == OrderStatus.newOrder
                                        ? OrderStatus.preparing
                                        : OrderStatus.ready;
                                    if (isLive) {
                                      final repo = ref.read(
                                        orderRepositoryProvider,
                                      );
                                      if (repo is SupabaseOrderRepository) {
                                        try {
                                          await repo.updateStatus(
                                            order.id,
                                            nextStatus,
                                          );
                                          ref.invalidate(ordersProvider);
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Update failed: $e',
                                                    ),
                                                  ),
                                                );
                                          }
                                        }
                                        return;
                                      }
                                    }
                                    ref
                                        .read(demoOrdersProvider.notifier)
                                        .advance(order.id);
                                  },
                          ),
                        ),
                    ],
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
