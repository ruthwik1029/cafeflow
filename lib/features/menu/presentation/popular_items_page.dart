import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/cafe_components.dart';
import '../../../shared/components/section_heading.dart';
import '../../demo/application/demo_catalog_controller.dart';
import '../application/catalog_provider.dart';
import '../domain/catalog.dart';

class PopularItemsPage extends ConsumerWidget {
  const PopularItemsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CatalogSnapshot catalog =
        ref.watch(catalogProvider).asData?.value ??
        ref.watch(demoCatalogProvider);
    final popular = catalog.products.where((p) => p.featured).toList();

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (catalog.isDemo) const DemoNotice(),
          const SectionHeading(
            'Popular Menu Items',
            subtitle:
                'Customer favorites and highest-velocity ordered products.',
          ),
          AdaptiveColumns(
            minWidth: 280,
            children: [
              for (var i = 0; i < popular.length; i++)
                CafeCard(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        child: Text(
                          '#${i + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              popular[i].name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(money(popular[i].priceMinor)),
                          ],
                        ),
                      ),
                      StatusPill(
                        popular[i].available ? 'In Stock' : 'Sold Out',
                        icon: popular[i].available
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
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
}
