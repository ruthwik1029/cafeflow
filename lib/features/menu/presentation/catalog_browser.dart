import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/cafe_components.dart';
import '../../../shared/components/product_card.dart';
import '../../../shared/components/section_heading.dart';
import '../application/catalog_provider.dart';
import '../domain/catalog.dart';

class CatalogBrowser extends ConsumerStatefulWidget {
  const CatalogBrowser({this.onSelect, this.featuredOnly = false, super.key});
  final ValueChanged<MenuProduct>? onSelect;
  final bool featuredOnly;
  @override
  ConsumerState<CatalogBrowser> createState() => _CatalogBrowserState();
}

class _CatalogBrowserState extends ConsumerState<CatalogBrowser> {
  String query = '';
  String? category;
  @override
  Widget build(BuildContext context) => ref
      .watch(catalogProvider)
      .when(
        loading: () => const CafeLoadingState(label: 'Loading the menu'),
        error: (_, _) => CafeErrorState(
          message: 'The menu could not be loaded.',
          onRetry: () => ref.invalidate(catalogProvider),
        ),
        data: (catalog) {
          final products = catalog.visibleProducts
              .where(
                (p) =>
                    (!widget.featuredOnly || p.featured) &&
                    (category == null || p.categoryId == category) &&
                    '${p.name} ${p.description}'.toLowerCase().contains(
                      query.toLowerCase(),
                    ),
              )
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                catalog.isDemo
                    ? 'Sample menu · fictional prices and availability'
                    : 'Published menu',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 16),
              if (!widget.featuredOnly) ...[
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search products',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: category == null,
                      onSelected: (_) => setState(() => category = null),
                    ),
                    for (final item in catalog.categories.where(
                      (c) => c.active,
                    ))
                      ChoiceChip(
                        label: Text(item.name),
                        selected: category == item.id,
                        onSelected: (_) => setState(() => category = item.id),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
              if (products.isEmpty)
                const CafeEmptyState(
                  title: 'No products to show',
                  message: 'Try another category or search term.',
                )
              else
                AdaptiveColumns(
                  minWidth: 220,
                  children: products
                      .map(
                        (p) => ProductCard(
                          product: p,
                          onSelect: widget.onSelect == null
                              ? null
                              : () => widget.onSelect!(p),
                        ),
                      )
                      .toList(),
                ),
            ],
          );
        },
      );
}

class CatalogBrowserPage extends StatelessWidget {
  const CatalogBrowserPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [DemoNotice(), CatalogBrowser()],
      ),
    );
  }
}
