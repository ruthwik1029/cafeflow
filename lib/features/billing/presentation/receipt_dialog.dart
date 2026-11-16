import 'package:flutter/material.dart';

import '../../menu/domain/catalog.dart';
import '../../orders/domain/cafe_order.dart';
import '../domain/payment_models.dart';

enum ReceiptWidth { mm80, mm58 }

class ReceiptDialog extends StatefulWidget {
  const ReceiptDialog({
    super.key,
    required this.order,
    this.payment,
    this.restaurantName = 'CafeFlow Flagship Bistro',
    this.restaurantAddress = '12 Heritage Cross, Indiranagar, Bengaluru',
    this.restaurantPhone = '+91 80 4123 4567',
    this.cashierName = 'Counter Cashier',
  });

  final CafeOrder order;
  final PaymentRecord? payment;
  final String restaurantName;
  final String restaurantAddress;
  final String restaurantPhone;
  final String cashierName;

  static Future<void> show(
    BuildContext context, {
    required CafeOrder order,
    PaymentRecord? payment,
    String? restaurantName,
    String? restaurantAddress,
    String? restaurantPhone,
    String? cashierName,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => ReceiptDialog(
        order: order,
        payment: payment,
        restaurantName: restaurantName ?? 'CafeFlow Flagship Bistro',
        restaurantAddress:
            restaurantAddress ?? '12 Heritage Cross, Indiranagar, Bengaluru',
        restaurantPhone: restaurantPhone ?? '+91 80 4123 4567',
        cashierName: cashierName ?? 'Counter Cashier',
      ),
    );
  }

  @override
  State<ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<ReceiptDialog> {
  ReceiptWidth _width = ReceiptWidth.mm80;

  @override
  Widget build(BuildContext context) {
    final isCompact = _width == ReceiptWidth.mm58;
    final cardWidth = isCompact ? 280.0 : 380.0;

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Text(
              'Customer Bill Receipt',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<ReceiptWidth>(
            segments: const [
              ButtonSegment(value: ReceiptWidth.mm80, label: Text('80mm')),
              ButtonSegment(value: ReceiptWidth.mm58, label: Text('58mm')),
            ],
            selected: {_width},
            onSelectionChanged: (set) {
              setState(() => _width = set.first);
            },
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Center(
            child: Container(
              width: cardWidth,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DefaultTextStyle(
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: isCompact ? 11 : 12,
                  color: Colors.black87,
                  height: 1.35,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Branding
                    Text(
                      widget.restaurantName.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isCompact ? 13 : 15,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.restaurantAddress,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: isCompact ? 9 : 10),
                    ),
                    Text(
                      'Tel: ${widget.restaurantPhone}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: isCompact ? 9 : 10),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '*** DEMO / SIMULATED PAYMENT ***',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isCompact ? 10 : 11,
                        color: Colors.red.shade900,
                      ),
                    ),
                    Text(
                      'NO REAL MONEY PROCESSED',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isCompact ? 8 : 9,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _dashedDivider(),
                    const SizedBox(height: 6),

                    // Order Metadata
                    _metaRow('Order Number:', widget.order.number),
                    _metaRow(
                      'Date & Time:',
                      _formatDate(widget.order.createdAt),
                    ),
                    _metaRow('Table:', widget.order.table),
                    _metaRow('Billed By:', widget.cashierName),
                    const SizedBox(height: 6),
                    _dashedDivider(),
                    const SizedBox(height: 8),

                    // Items Table
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'ITEM',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          'QTY × PRICE',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'AMOUNT',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.black54,
                    ),
                    const SizedBox(height: 6),
                    for (final item in widget.order.lines) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                          Text('${item.quantity} × ${money(item.unitMinor)}'),
                          const SizedBox(width: 8),
                          Text(
                            money(item.totalMinor),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    const SizedBox(height: 6),
                    _dashedDivider(),
                    const SizedBox(height: 6),

                    // Financial Breakdown
                    _summaryRow('Subtotal', money(widget.order.subtotalMinor)),
                    if (widget.order.discountMinor > 0)
                      _summaryRow(
                        'Discount${widget.order.discountReason.isNotEmpty ? " (${widget.order.discountReason})" : ""}',
                        '−${money(widget.order.discountMinor)}',
                      ),
                    if (widget.order.taxIsInclusive)
                      _summaryRow(
                        '${widget.order.taxName} (Included)',
                        money(widget.order.taxMinor),
                      )
                    else
                      _summaryRow(
                        '${widget.order.taxName} (${(widget.order.taxRateBps / 100).toStringAsFixed(1)}%)',
                        money(widget.order.taxMinor),
                      ),
                    if (widget.order.serviceChargeMinor > 0)
                      _summaryRow(
                        'Service Charge',
                        money(widget.order.serviceChargeMinor),
                      ),
                    const SizedBox(height: 4),
                    const Divider(
                      height: 2,
                      thickness: 1.5,
                      color: Colors.black,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'GRAND TOTAL',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isCompact ? 13 : 15,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          money(widget.order.totalMinor),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isCompact ? 13 : 15,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _dashedDivider(),
                    const SizedBox(height: 8),

                    // Payment Settlement Status
                    if (widget.payment != null) ...[
                      _summaryRow(
                        'Payment Method:',
                        widget.payment!.paymentMethodCode,
                      ),
                      if (widget.payment!.transactionReference != null &&
                          widget.payment!.transactionReference!.isNotEmpty)
                        _summaryRow(
                          'Txn Ref:',
                          widget.payment!.transactionReference!,
                        ),
                      if (widget.payment!.tenderedAmountMinor != null &&
                          widget.payment!.paymentMethodCode == 'CASH') ...[
                        _summaryRow(
                          'Cash Tendered:',
                          money(widget.payment!.tenderedAmountMinor!),
                        ),
                        _summaryRow(
                          'Change Returned:',
                          money(widget.payment!.changeDueMinor),
                        ),
                      ],
                    ],
                    _summaryRow(
                      'Bill Status:',
                      widget.order.financialStatus.label.toUpperCase(),
                      boldValue: true,
                    ),
                    const SizedBox(height: 12),
                    _dashedDivider(),
                    const SizedBox(height: 12),

                    // Thermal Receipt Footer
                    Text(
                      'THANK YOU FOR DINING WITH US!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isCompact ? 10 : 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '*** DEMO SIMULATION COPY ***\nFor demonstration & testing only\nNo financial liability or real payment processing',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: isCompact ? 8 : 9),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print Receipt'),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Receipt sent to ${_width == ReceiptWidth.mm80 ? "80mm" : "58mm"} thermal printer.',
                ),
              ),
            );
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _dashedDivider() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashHeight = 1.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return const SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black45),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool boldValue = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: boldValue ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$min';
  }
}
