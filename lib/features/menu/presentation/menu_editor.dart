import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/services/backend.dart';
import '../../auth/application/auth_controller.dart';
import '../../demo/application/demo_catalog_controller.dart';
import '../application/catalog_provider.dart';
import '../data/supabase_menu_repository.dart';
import '../domain/catalog.dart';

class MenuEditor extends ConsumerStatefulWidget {
  const MenuEditor({this.product, super.key});
  final MenuProduct? product;
  @override
  ConsumerState<MenuEditor> createState() => _MenuEditorState();
}

class _MenuEditorState extends ConsumerState<MenuEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.product?.name);
  late final price = TextEditingController(
    text: ((widget.product?.priceMinor ?? 0) / 100).toStringAsFixed(2),
  );
  late final description = TextEditingController(
    text: widget.product?.description,
  );
  late final image = TextEditingController(
    text: widget.product?.image ?? 'assets/images/coffee.jpg',
  );
  String? category;
  bool available = true;
  String? error;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    category = widget.product?.categoryId;
    available = widget.product?.available ?? true;
  }

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    description.dispose();
    image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider).value;
    final categories = catalog?.categories.isNotEmpty == true
        ? catalog!.categories
        : ref.watch(demoCatalogProvider).categories;

    category ??= categories.firstOrNull?.id;
    final backend = ref.watch(backendProvider);
    final auth = ref.watch(authControllerProvider);
    final isLive =
        backend.status == BackendStatus.initialized &&
        auth.activeMembership?.restaurantId != null &&
        catalog?.isDemo == false;

    return AlertDialog(
      title: Text(widget.product == null ? 'Add menu item' : 'Edit menu item'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isLive
                        ? Theme.of(context).colorScheme.primaryContainer
                              .withAlpha(80)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLive ? Icons.cloud_done_outlined : Icons.info_outline,
                        size: 14,
                        color: isLive
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isLive
                            ? 'Live Supabase Menu Item'
                            : 'Local demo edit. No data is sent to Supabase.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: isLive
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Item name'),
                  maxLength: 120,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a name.' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: categories
                      .map(
                        (c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                      )
                      .toList(),
                  onChanged: (v) => category = v,
                  validator: (v) => v == null ? 'Choose a category.' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Price (INR)'),
                  validator: (v) => parseMoney(v ?? '') == null
                      ? 'Use a non-negative price with up to two decimals.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: description,
                  maxLines: 3,
                  maxLength: 600,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: image,
                  decoration: const InputDecoration(
                    labelText: 'Image URL or bundled asset',
                  ),
                  validator: (v) =>
                      (v ?? '').isEmpty ||
                          (v ?? '').startsWith('assets/images/') ||
                          Uri.tryParse(v ?? '')?.scheme == 'https'
                      ? null
                      : 'Use HTTPS or a bundled image.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final asset in [
                      'coffee',
                      'pastry',
                      'bowl',
                      'sandwich',
                    ])
                      ActionChip(
                        label: Text(asset),
                        onPressed: () =>
                            image.text = 'assets/images/$asset.jpg',
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available to order'),
                  value: available,
                  onChanged: (v) => setState(() => available = v),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: isSaving
              ? null
              : () async {
                  if (!form.currentState!.validate()) return;
                  final repo = ref.read(menuRepositoryProvider);
                  final restId = auth.activeMembership?.restaurantId;

                  setState(() {
                    isSaving = true;
                    error = null;
                  });

                  if (isLive &&
                      repo is SupabaseMenuRepository &&
                      restId != null) {
                    try {
                      final priceMinor = parseMoney(price.text)!;
                      if (widget.product == null) {
                        await repo.createMenuItem(
                          restaurantId: restId,
                          categoryId: category!,
                          name: name.text.trim(),
                          priceMinor: priceMinor,
                          description: description.text.trim(),
                          imageUrl: image.text.trim(),
                          available: available,
                        );
                      } else {
                        await repo.updateMenuItem(
                          itemId: widget.product!.id,
                          name: name.text.trim(),
                          priceMinor: priceMinor,
                          description: description.text.trim(),
                          categoryId: category!,
                          imageUrl: image.text.trim(),
                          available: available,
                        );
                      }
                      ref.invalidate(catalogProvider);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      setState(() {
                        isSaving = false;
                        error = e is AppFailure
                            ? e.message
                            : 'Failed to save menu item.';
                      });
                    }
                    return;
                  }

                  // Local demo save fallback
                  final controller = ref.read(demoCatalogProvider.notifier);
                  try {
                    controller.save(
                      MenuProduct(
                        id: widget.product?.id ?? controller.newId(),
                        categoryId: category!,
                        name: name.text.trim(),
                        priceMinor: parseMoney(price.text)!,
                        description: description.text.trim(),
                        image: image.text.trim(),
                        available: available,
                        featured: widget.product?.featured ?? false,
                      ),
                    );
                    Navigator.pop(context);
                  } on ArgumentError catch (_) {
                    setState(() {
                      isSaving = false;
                      error = 'Please check the item details.';
                    });
                  }
                },
          child: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isLive ? 'Save item' : 'Save local item'),
        ),
      ],
    );
  }
}
