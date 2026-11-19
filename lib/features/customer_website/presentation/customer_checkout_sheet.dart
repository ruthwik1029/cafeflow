import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../billing/application/cart_controller.dart';
import '../../menu/domain/catalog.dart';
import '../application/customer_order_service.dart';
import 'customer_order_tracking_dialog.dart';

class CustomerCheckoutSheet extends ConsumerStatefulWidget {
  const CustomerCheckoutSheet({super.key});

  static Future<void> show(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    if (wide) {
      return showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 780),
            child: const CustomerCheckoutSheet(),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.sizeOf(context).height * 0.9,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: const CustomerCheckoutSheet(),
      ),
    );
  }

  @override
  ConsumerState<CustomerCheckoutSheet> createState() =>
      _CustomerCheckoutSheetState();
}

class _CustomerCheckoutSheetState extends ConsumerState<CustomerCheckoutSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _tableController;
  late final TextEditingController _notesController;
  late final TextEditingController _pairingCodeController;

  String _orderType = 'DINE_IN';
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _tableController = TextEditingController(text: 'Table 04');
    _notesController = TextEditingController();
    _pairingCodeController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _tableController.dispose();
    _notesController.dispose();
    _pairingCodeController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;

    final cart = ref.read(cartProvider('customer'));
    if (cart.lines.isEmpty) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final orderService = ref.read(customerOrderServiceProvider);
      final items = cart.lines
          .map(
            (l) =>
                CustomerOrderItem(productId: l.productId, quantity: l.quantity),
          )
          .toList();

      final submission = CustomerOrderSubmission(
        customerName: _nameController.text.trim(),
        customerPhone: _phoneController.text.trim(),
        orderType: _orderType,
        tableName: _orderType == 'DINE_IN'
            ? _tableController.text.trim()
            : 'Takeaway',
        specialInstructions: _notesController.text.trim(),
        items: items,
        pairingCode: _pairingCodeController.text.trim().isEmpty
            ? null
            : _pairingCodeController.text.trim(),
      );

      final result = await orderService.submitOrder(submission);

      ref.read(cartProvider('customer').notifier).clear();

      if (mounted) {
        Navigator.of(context).pop();
        await CustomerOrderTrackingDialog.show(
          context,
          orderId: result.orderId,
          orderNumber: result.orderNumber,
          pairingCode: result.pairingCode,
        );
      }
    } on AppFailure catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Failed to submit order. Please check details and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider('customer'));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.receipt_long_rounded,
                  color: theme.colorScheme.primary,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Review & Place Order',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: theme.colorScheme.onErrorContainer,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Cart Items Section
                    Text(
                      'Your Items',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final line in cart.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    line.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    money(line.unitMinor),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 20,
                              ),
                              onPressed: () {
                                ref
                                    .read(cartProvider('customer').notifier)
                                    .quantity(
                                      line.productId,
                                      line.quantity - 1,
                                    );
                              },
                            ),
                            Text(
                              '${line.quantity}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 20,
                              ),
                              onPressed: () {
                                ref
                                    .read(cartProvider('customer').notifier)
                                    .quantity(
                                      line.productId,
                                      line.quantity + 1,
                                    );
                              },
                            ),
                            SizedBox(
                              width: 72,
                              child: Text(
                                money(line.totalMinor),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const Divider(height: 24),

                    // Financial Summary
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal'),
                        Text(money(cart.subtotalMinor)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('GST (${cart.taxBasisPoints / 100}%)'),
                        Text(money(cart.taxMinor)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Payable',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          money(cart.totalMinor),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),

                    const Divider(height: 32),

                    // Customer Details
                    Text(
                      'Customer Information',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Your Name *',
                        hintText: 'e.g. Alex Sharma',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().length < 2) {
                          return 'Please enter your name (min 2 characters).';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number (Optional)',
                        hintText: '+91 98765 43210',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 18),

                    // Dining Option
                    Text(
                      'Dining Option',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'DINE_IN',
                          label: Text('Dine-In'),
                          icon: Icon(Icons.table_restaurant_outlined),
                        ),
                        ButtonSegment(
                          value: 'TAKEAWAY',
                          label: Text('Takeaway'),
                          icon: Icon(Icons.takeout_dining_outlined),
                        ),
                      ],
                      selected: {_orderType},
                      onSelectionChanged: (val) {
                        setState(() => _orderType = val.first);
                      },
                    ),
                    const SizedBox(height: 14),

                    if (_orderType == 'DINE_IN') ...[
                      TextFormField(
                        controller: _tableController,
                        decoration: const InputDecoration(
                          labelText: 'Table Number',
                          hintText: 'Table 04',
                          prefixIcon: Icon(Icons.pin_drop_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children:
                            ['Table 01', 'Table 02', 'Table 03', 'Table 04']
                                .map(
                                  (t) => ActionChip(
                                    label: Text(t),
                                    onPressed: () {
                                      setState(() => _tableController.text = t);
                                    },
                                  ),
                                )
                                .toList(),
                      ),
                      const SizedBox(height: 14),
                    ],

                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Special Instructions',
                        hintText: 'e.g. Oat milk, extra hot, less ice',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),

                    // Demonstrator Pairing Channel Box
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? theme.colorScheme.surfaceContainerHighest
                            : theme.colorScheme.primaryContainer.withAlpha(80),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: theme.colorScheme.primary.withAlpha(80),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.sensors_rounded,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Demonstrator Channel Pairing',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Enter the 6-digit channel code from your CafeFlow Desktop or Mobile screen to route this order directly to your demonstrator session.',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _pairingCodeController,
                            decoration: const InputDecoration(
                              labelText: '6-Digit Pairing Code (Optional)',
                              hintText: 'e.g. 482910',
                              prefixIcon: Icon(Icons.tag_rounded),
                            ),
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isSubmitting ? null : _placeOrder,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Place Order · ${money(cart.totalMinor)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
