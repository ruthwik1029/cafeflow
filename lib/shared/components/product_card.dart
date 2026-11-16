import 'package:flutter/material.dart';

import '../../core/widgets/cafe_components.dart';
import '../../features/menu/domain/catalog.dart';

class ProductImage extends StatelessWidget {
  const ProductImage({required this.product, this.height = 150, super.key});
  final MenuProduct product;
  final double height;
  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext context, Object error, StackTrace? stack) =>
        SizedBox(
          height: height,
          child: const Center(child: Icon(Icons.local_cafe_outlined, size: 42)),
        );
    final image = product.image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: image.startsWith('assets/')
          ? Image.asset(
              image,
              height: height,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: fallback,
            )
          : Uri.tryParse(image)?.scheme == 'https'
          ? Image.network(
              image,
              height: height,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: fallback,
            )
          : fallback(context, '', null),
    );
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({required this.product, this.onSelect, super.key});
  final MenuProduct product;
  final VoidCallback? onSelect;
  @override
  Widget build(BuildContext context) => CafeCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProductImage(product: product),
        const SizedBox(height: 16),
        Text(product.name, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(product.description, maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              money(product.priceMinor),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!product.available) const Text('Sold out'),
            if (onSelect != null)
              FilledButton.tonal(
                onPressed: product.available ? onSelect : null,
                child: Text(
                  'Add ${product.name}',
                  semanticsLabel: 'Add ${product.name}',
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
