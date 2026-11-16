import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/routing/workspace.dart';
import '../../../core/services/backend.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/cafe_components.dart';
import '../../../shared/components/section_heading.dart';
import '../../auth/application/auth_controller.dart';
import '../../billing/application/payment_provider.dart';
import '../../billing/domain/payment_models.dart';
import '../../demo/application/demo_catalog_controller.dart';
import '../../demo/application/demo_inventory_controller.dart';
import '../../demo/application/demo_orders_controller.dart';
import '../../demo/application/demo_tables_controller.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _taxNameController = TextEditingController();
  final _taxRateController = TextEditingController();
  final _serviceChargeNameController = TextEditingController();
  final _serviceChargeRateController = TextEditingController();
  bool _taxIsInclusive = false;
  bool _isSavingTax = false;
  bool _initializedFromSettings = false;

  @override
  void dispose() {
    _taxNameController.dispose();
    _taxRateController.dispose();
    _serviceChargeNameController.dispose();
    _serviceChargeRateController.dispose();
    super.dispose();
  }

  void _syncSettings(RestaurantTaxSettings settings) {
    if (!_initializedFromSettings) {
      _taxNameController.text = settings.taxName;
      _taxRateController.text = (settings.gstRateBasisPoints / 100)
          .toStringAsFixed(1);
      _serviceChargeNameController.text = settings.serviceChargeName;
      _serviceChargeRateController.text =
          (settings.serviceChargeBasisPoints / 100).toStringAsFixed(1);
      _taxIsInclusive = settings.taxIsInclusive;
      _initializedFromSettings = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(backendProvider);
    final theme = ref.watch(themeControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final isLive =
        backend.status == BackendStatus.initialized &&
        auth.activeMembership?.restaurantId != null;
    final isPrivileged =
        auth.activeRole == WorkspaceRole.owner ||
        auth.activeRole == WorkspaceRole.admin;

    final taxSettingsAsync = ref.watch(restaurantTaxSettingsProvider);
    final paymentMethodsAsync = ref.watch(paymentMethodsProvider);

    taxSettingsAsync.whenData((settings) {
      if (!_initializedFromSettings) {
        _syncSettings(settings);
      }
    });

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
                    Icons.tune,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Settings · Managed in Supabase PostgreSQL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          const SectionHeading(
            'Business & System Settings',
            subtitle: 'Configure outlet profile, billing parameters, payment methods, and theme.',
          ),
          AdaptiveColumns(
            minWidth: 320,
            children: [
              CafeCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cafe Profile',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.storefront_outlined),
                      title: Text('Business Name'),
                      subtitle: Text('CafeFlow Flagship Bistro'),
                    ),
                    const Divider(),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.location_on_outlined),
                      title: Text('Address'),
                      subtitle: Text(
                        '12 Heritage Cross, Indiranagar, Bengaluru',
                      ),
                    ),
                    const Divider(),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.email_outlined),
                      title: Text('Contact Email'),
                      subtitle: Text('hello@cafeflow.local'),
                    ),
                    const Divider(),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.currency_rupee),
                      title: Text('Default Currency'),
                      subtitle: Text('INR (Indian Rupee - ₹)'),
                    ),
                  ],
                ),
              ),
              CafeCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tax & Monetary Parameters',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _taxNameController,
                      enabled: isPrivileged,
                      decoration: const InputDecoration(
                        labelText: 'Tax Display Name (e.g. GST, VAT)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _taxRateController,
                      enabled: isPrivileged,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Tax Rate (%)',
                        suffixText: '%',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Inclusive Tax (Tax included in menu price)',
                      ),
                      subtitle: Text(
                        _taxIsInclusive
                            ? 'Prices on menu already include tax'
                            : 'Tax is added on top of item prices at checkout',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _taxIsInclusive,
                      onChanged: isPrivileged
                          ? (val) => setState(() => _taxIsInclusive = val)
                          : null,
                    ),
                    const Divider(),
                    TextField(
                      controller: _serviceChargeNameController,
                      enabled: isPrivileged,
                      decoration: const InputDecoration(
                        labelText: 'Surcharge / Service Charge Name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _serviceChargeRateController,
                      enabled: isPrivileged,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Service Charge Rate (%)',
                        suffixText: '%',
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (isPrivileged)
                      CafeButton(
                        label: _isSavingTax
                            ? 'Saving...'
                            : 'Save Tax & Surcharge Settings',
                        onPressed: _isSavingTax ? null : _saveTaxSettings,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          AdaptiveColumns(
            minWidth: 320,
            children: [
              CafeCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Accepted Payment Methods',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enable or disable tender options for cashiers.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    paymentMethodsAsync.when(
                      data: (methods) {
                        final displayMethods = methods.isNotEmpty
                            ? methods
                            : const [
                                PaymentMethodRecord(
                                  id: '1',
                                  restaurantId: 'demo',
                                  code: 'CASH',
                                  displayName: 'Cash',
                                  isActive: true,
                                ),
                                PaymentMethodRecord(
                                  id: '2',
                                  restaurantId: 'demo',
                                  code: 'UPI',
                                  displayName: 'UPI / Digital QR',
                                  isActive: true,
                                ),
                                PaymentMethodRecord(
                                  id: '3',
                                  restaurantId: 'demo',
                                  code: 'CARD',
                                  displayName: 'Credit / Debit Card',
                                  isActive: true,
                                ),
                              ];

                        return Column(
                          children: [
                            for (final method in displayMethods) ...[
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                secondary: Icon(switch (method.code
                                    .toUpperCase()) {
                                  'CASH' => Icons.payments_outlined,
                                  'UPI' => Icons.qr_code_2_outlined,
                                  'CARD' => Icons.credit_card_outlined,
                                  _ => Icons.account_balance_wallet_outlined,
                                }),
                                title: Text(method.displayName),
                                subtitle: Text(
                                  method.isActive
                                      ? 'Active at checkout'
                                      : 'Disabled',
                                ),
                                value: method.isActive,
                                onChanged: isPrivileged
                                    ? (active) => _togglePaymentMethod(
                                        method.code,
                                        active,
                                      )
                                    : null,
                              ),
                              const Divider(),
                            ],
                          ],
                        );
                      },
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (e, _) =>
                          Text('Error loading payment methods: $e'),
                    ),
                  ],
                ),
              ),
              CafeCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Environment & Theme',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        const Text('Theme Mode:'),
                        SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('System'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('Light'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('Dark'),
                            ),
                          ],
                          selected: {theme},
                          onSelectionChanged: (selected) {
                            ref
                                .read(themeControllerProvider.notifier)
                                .setMode(selected.first);
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        const Text('Supabase Backend:'),
                        StatusPill(
                          backend.status == BackendStatus.initialized
                              ? 'Connected'
                              : 'Demo Mode (Offline)',
                          icon: backend.status == BackendStatus.initialized
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_off_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      backend.message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SectionHeading(
                'Demo Environment & Data Controls',
                subtitle: 'Reset in-memory sample catalog, orders, and tables without modifying the live database.',
              ),
              const SizedBox(height: 12),
              CafeCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.amber.shade900,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Demo Reset Action: Restores sample categories, products, inventory items, and orders back to baseline demo values. Live Supabase database records are preserved.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reset In-Memory Demo Data',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Restore sample catalog, orders, tables, and stock',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reset Demo State'),
                          onPressed: () {
                            ref.read(demoCatalogProvider.notifier).reset();
                            ref.read(demoOrdersProvider.notifier).reset();
                            ref.read(demoTablesProvider.notifier).reset();
                            ref.read(demoInventoryProvider.notifier).reset();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Demo catalog, orders, tables, and inventory reset to factory defaults.',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveTaxSettings() async {
    final auth = ref.read(authControllerProvider);
    final restId = auth.activeMembership?.restaurantId;
    final taxRatePercent = double.tryParse(_taxRateController.text) ?? 5.0;
    final scRatePercent =
        double.tryParse(_serviceChargeRateController.text) ?? 0.0;
    final gstBps = (taxRatePercent * 100).round();
    final scBps = (scRatePercent * 100).round();

    setState(() => _isSavingTax = true);

    if (restId != null) {
      try {
        final paymentRepo = ref.read(paymentRepositoryProvider);
        await paymentRepo.updateTaxSettings(
          restaurantId: restId,
          taxName: _taxNameController.text.trim().isEmpty
              ? 'GST'
              : _taxNameController.text.trim(),
          gstRateBasisPoints: gstBps,
          taxIsInclusive: _taxIsInclusive,
          serviceChargeBasisPoints: scBps,
          serviceChargeName: _serviceChargeNameController.text.trim().isEmpty
              ? 'Service Charge'
              : _serviceChargeNameController.text.trim(),
        );
        ref.invalidate(restaurantTaxSettingsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tax and surcharge settings updated successfully.'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update settings: $e')),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Simulated update: Tax settings saved locally.'),
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isSavingTax = false);
    }
  }

  Future<void> _togglePaymentMethod(String code, bool isActive) async {
    final auth = ref.read(authControllerProvider);
    final restId = auth.activeMembership?.restaurantId;

    if (restId != null) {
      try {
        final paymentRepo = ref.read(paymentRepositoryProvider);
        await paymentRepo.updatePaymentMethodStatus(
          restaurantId: restId,
          code: code,
          isActive: isActive,
        );
        ref.invalidate(paymentMethodsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Payment method $code ${isActive ? "activated" : "disabled"}.',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update payment method: $e')),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Simulated toggle: $code is now ${isActive ? "active" : "disabled"}.',
            ),
          ),
        );
      }
    }
  }
}
