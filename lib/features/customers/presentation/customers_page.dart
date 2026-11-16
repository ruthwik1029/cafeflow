import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backend.dart';
import '../../../core/widgets/cafe_components.dart';
import '../../../shared/components/section_heading.dart';
import '../../auth/application/auth_controller.dart';
import '../../menu/domain/catalog.dart';
import '../application/customers_provider.dart';
import '../data/supabase_customers_repository.dart';

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  String search = '';

  @override
  Widget build(BuildContext context) {
    final backend = ref.watch(backendProvider);
    final auth = ref.watch(authControllerProvider);
    final isLive =
        backend.status == BackendStatus.initialized &&
        auth.activeMembership?.restaurantId != null;

    final customersAsync = ref.watch(customersProvider(search));
    final filtered = customersAsync.value ?? [];

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
                    Icons.people_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Customer Directory · Connected to Supabase',
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
            'Customer Directory',
            subtitle:
                'Guest profiles, repeat visit loyalty, and order preferences.',
            action: CafeButton(
              label: 'Add Customer',
              icon: Icons.person_add_outlined,
              onPressed: () => _addCustomerDialog(context, isLive),
            ),
          ),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search customers by name or phone',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (val) => setState(() => search = val),
          ),
          const SizedBox(height: 24),
          if (filtered.isEmpty)
            const CafeEmptyState(
              title: 'No customer records match',
              message: 'Try a different search query.',
              icon: Icons.person_search_outlined,
            )
          else
            AdaptiveColumns(
              minWidth: 280,
              children: [
                for (final customer in filtered)
                  CafeCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              customer.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            StatusPill(
                              customer.visitsCount >= 20
                                  ? 'Gold Member'
                                  : customer.visitsCount >= 10
                                  ? 'Silver Member'
                                  : 'Guest',
                              icon: Icons.star_border_rounded,
                            ),
                          ],
                        ),
                        if (customer.phone.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            customer.phone,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const Divider(height: 24),
                        Row(
                          children: [
                            const Text('Visits:'),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${customer.visitsCount} times',
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (customer.favoriteItem.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Text('Favorite:'),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  customer.favoriteItem,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text('Lifetime spend:'),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                money(customer.totalSpendMinor),
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
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

  void _addCustomerDialog(BuildContext context, bool isLive) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final favCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('New Customer Profile'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Customer Name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: favCtrl,
                decoration: const InputDecoration(
                  labelText: 'Favorite Item (Optional)',
                ),
              ),
            ],
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
                final repo = ref.read(customersRepositoryProvider);
                final auth = ref.read(authControllerProvider);
                final restId = auth.activeMembership?.restaurantId;

                if (repo != null && restId != null) {
                  try {
                    await repo.createCustomer(
                      restaurantId: restId,
                      name: name,
                      phone: phoneCtrl.text.trim(),
                      favoriteItem: favCtrl.text.trim(),
                    );
                    ref.invalidate(customersProvider);
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
                const SnackBar(content: Text('Demo Mode: Customer added.')),
              );
            },
            child: const Text('Add Customer'),
          ),
        ],
      ),
    );
  }
}
