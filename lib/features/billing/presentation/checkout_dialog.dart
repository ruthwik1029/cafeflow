import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../menu/domain/catalog.dart';
import '../application/cart_controller.dart';
import '../application/payment_provider.dart';
import '../domain/payment_models.dart';

class CheckoutSubmission {
  const CheckoutSubmission({
    required this.paymentMethodCode,
    required this.amountMinor,
    this.tenderedAmountMinor,
    this.changeDueMinor = 0,
    this.transactionReference,
    this.settleImmediately = true,
  });

  final String paymentMethodCode;
  final int amountMinor;
  final int? tenderedAmountMinor;
  final int changeDueMinor;
  final String? transactionReference;
  final bool settleImmediately;
}

class CheckoutDialog extends ConsumerStatefulWidget {
  const CheckoutDialog({
    super.key,
    required this.cart,
    required this.tableName,
    required this.isLive,
    this.specialInstructions = '',
  });

  final CartState cart;
  final String tableName;
  final bool isLive;
  final String specialInstructions;

  static Future<CheckoutSubmission?> show(
    BuildContext context, {
    required CartState cart,
    required String tableName,
    required bool isLive,
    String specialInstructions = '',
  }) {
    return showDialog<CheckoutSubmission>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CheckoutDialog(
        cart: cart,
        tableName: tableName,
        isLive: isLive,
        specialInstructions: specialInstructions,
      ),
    );
  }

  @override
  ConsumerState<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends ConsumerState<CheckoutDialog> {
  late String _selectedMethod;
  late TextEditingController _tenderedController;
  final TextEditingController _refController = TextEditingController();
  bool _settleImmediately = true;
  String? _cashError;

  @override
  void initState() {
    super.initState();
    _selectedMethod = widget.cart.paymentMethod.toUpperCase();
    if (!['CASH', 'UPI', 'CARD'].contains(_selectedMethod)) {
      _selectedMethod = 'CASH';
    }
    _tenderedController = TextEditingController(
      text: (widget.cart.totalMinor / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _tenderedController.dispose();
    _refController.dispose();
    super.dispose();
  }

  int get _parsedTenderedMinor {
    final parsed = parseMoney(_tenderedController.text);
    return parsed ?? widget.cart.totalMinor;
  }

  int get _changeDueMinor {
    final diff = _parsedTenderedMinor - widget.cart.totalMinor;
    return diff > 0 ? diff : 0;
  }

  @override
  Widget build(BuildContext context) {
    final methodsAsync = ref.watch(paymentMethodsProvider);
    final availableMethods =
        methodsAsync.value?.where((m) => m.isActive).toList() ??
        const [
          PaymentMethodRecord(
            id: 'm1',
            restaurantId: '',
            code: 'CASH',
            displayName: 'Cash',
            isActive: true,
          ),
          PaymentMethodRecord(
            id: 'm2',
            restaurantId: '',
            code: 'UPI',
            displayName: 'UPI',
            isActive: true,
          ),
          PaymentMethodRecord(
            id: 'm3',
            restaurantId: '',
            code: 'CARD',
            displayName: 'Card',
            isActive: true,
          ),
        ];

    final totalMinor = widget.cart.totalMinor;
    final isCash = _selectedMethod == 'CASH';

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.point_of_sale_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.isLive
                  ? 'Cashier Settlement (Simulated)'
                  : 'Review Local Order (Simulated)',
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber.shade700),
            ),
            child: Text(
              'DEMO MODE',
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
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // DEMO / SIMULATED PAYMENT DISCLAIMER
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: Colors.amber.shade900,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'DEMO / SIMULATED PAYMENT: No real payment gateway, UPI API, or card terminal is connected. All payments are simulated with fake references for testing only.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Order Summary Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Table: ${widget.tableName.isEmpty ? "Takeaway" : widget.tableName}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${widget.cart.lines.length} items',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Items List
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.cart.lines.length,
                  itemBuilder: (context, i) {
                    final item = widget.cart.lines[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${item.quantity} × ${item.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            money(item.totalMinor),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 24),

              // Financial Totals
              _amountRow('Subtotal', money(widget.cart.subtotalMinor)),
              if (widget.cart.discountMinor > 0)
                _amountRow(
                  'Discount ${widget.cart.discountReason.isNotEmpty ? "(${widget.cart.discountReason})" : ""}',
                  '−${money(widget.cart.discountMinor)}',
                  color: Colors.green.shade700,
                ),
              _amountRow(
                widget.cart.taxIsInclusive
                    ? '${widget.cart.taxName} (Included in prices)'
                    : '${widget.cart.taxName} (${(widget.cart.taxBasisPoints / 100).toStringAsFixed(1)}%)',
                money(widget.cart.taxMinor),
              ),
              if (widget.cart.serviceChargeMinor > 0)
                _amountRow(
                  widget.cart.serviceChargeName,
                  money(widget.cart.serviceChargeMinor),
                ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Grand Total Due',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    money(totalMinor),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Settlement Toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Record Payment Immediately'),
                subtitle: Text(
                  _settleImmediately
                      ? 'Marks the order as PAID and produces bill receipt'
                      : 'Creates ticket as UNPAID (Collect at counter later)',
                  style: const TextStyle(fontSize: 12),
                ),
                value: _settleImmediately,
                onChanged: (val) => setState(() => _settleImmediately = val),
              ),
              const SizedBox(height: 12),

              // Payment Method Options
              if (_settleImmediately) ...[
                const Text(
                  'Select Payment Method',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in availableMethods)
                      ChoiceChip(
                        label: Text(
                          m.displayName.contains('Simulated')
                              ? m.displayName
                              : '${m.displayName} (Simulated)',
                        ),
                        selected: _selectedMethod == m.code.toUpperCase(),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedMethod = m.code.toUpperCase();
                              _cashError = null;
                            });
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Cash Input Section
                if (isCash) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tenderedController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Cash Tendered (₹)',
                            prefixText: '₹ ',
                            errorText: _cashError,
                            helperText: 'Enter amount received from customer',
                          ),
                          onChanged: (text) {
                            final tendered = parseMoney(text);
                            setState(() {
                              if (tendered != null && tendered < totalMinor) {
                                _cashError = 'Underpayment not allowed.';
                              } else {
                                _cashError = null;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _changeDueMinor > 0
                              ? Colors.green.shade50
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _changeDueMinor > 0
                                ? Colors.green.shade300
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Change Due',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              money(_changeDueMinor),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _changeDueMinor > 0
                                    ? Colors.green.shade800
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Quick Cash Buttons
                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Exact'),
                        onPressed: () {
                          setState(() {
                            _tenderedController.text = (totalMinor / 100)
                                .toStringAsFixed(2);
                            _cashError = null;
                          });
                        },
                      ),
                      for (final amt in [100, 200, 500, 2000])
                        if (amt * 100 >= totalMinor)
                          ActionChip(
                            label: Text('₹$amt'),
                            onPressed: () {
                              setState(() {
                                _tenderedController.text = amt.toStringAsFixed(
                                  2,
                                );
                                _cashError = null;
                              });
                            },
                          ),
                    ],
                  ),
                ],

                // UPI / QR Section
                if (_selectedMethod == 'UPI') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.qr_code_2,
                          size: 48,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dynamic UPI QR Ready',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Ask customer to scan counter QR and verify payment confirmation before submitting.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _refController,
                    decoration: const InputDecoration(
                      labelText: 'UPI Reference / UTR Number (Optional)',
                      hintText: 'e.g., 423984729182',
                    ),
                  ),
                ],

                // Card Section
                if (_selectedMethod == 'CARD') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.credit_card, size: 36, color: Colors.amber),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Process payment on card terminal. Do not enter card numbers or CVVs. Record external auth code below.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _refController,
                    decoration: const InputDecoration(
                      labelText: 'Card Terminal Approval Code (Optional)',
                      hintText: 'e.g., AUTH-928134',
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
        FilledButton.icon(
          icon: Icon(_settleImmediately ? Icons.payment_rounded : Icons.check),
          label: Text(
            _settleImmediately
                ? 'Confirm & Settle (Simulated) ${money(totalMinor)}'
                : 'Place Unpaid Order',
          ),
          onPressed: () {
            if (_settleImmediately && isCash) {
              if (_parsedTenderedMinor < totalMinor) {
                setState(() => _cashError = 'Underpayment not allowed.');
                return;
              }
            }

            final fakeRef = _refController.text.trim().isNotEmpty
                ? _refController.text.trim()
                : 'SIM-$_selectedMethod-${DateTime.now().millisecondsSinceEpoch % 1000000}';

            final submission = CheckoutSubmission(
              paymentMethodCode: _selectedMethod,
              amountMinor: totalMinor,
              tenderedAmountMinor: isCash ? _parsedTenderedMinor : null,
              changeDueMinor: isCash ? _changeDueMinor : 0,
              transactionReference: fakeRef,
              settleImmediately: _settleImmediately,
            );

            Navigator.of(context).pop(submission);
          },
        ),
      ],
    );
  }

  Widget _amountRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
