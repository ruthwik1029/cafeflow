import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/cafe_components.dart';
import '../../../shared/components/product_card.dart';
import '../../../shared/components/section_heading.dart';
import '../../auth/application/auth_controller.dart';
import '../../demo/application/demo_catalog_controller.dart';
import '../application/catalog_provider.dart';
import '../data/supabase_menu_repository.dart';
import '../domain/catalog.dart';
import 'menu_editor.dart';

class MenuManagementPage extends ConsumerWidget {
  const MenuManagementPage({this.categoriesOnly = false, super.key});
  final bool categoriesOnly;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageBody(
    child: ref
        .watch(catalogProvider)
        .when(
          loading: () => const CafeLoadingState(),
          error: (_, _) => CafeErrorState(
            message: 'Catalog unavailable.',
            onRetry: () => ref.invalidate(catalogProvider),
          ),
          data: (catalog) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (catalog.isDemo) const DemoNotice(),
              if (!categoriesOnly)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Menu management starts here'),
                ),
              SectionHeading(
                categoriesOnly ? 'Categories' : 'Menu management',
                subtitle: 'A thoughtful menu, beautifully organized.',
                action: CafeButton(
                  label: categoriesOnly ? 'Add category' : 'Add menu item',
                  icon: Icons.add,
                  onPressed: () => categoriesOnly
                      ? editCategory(context, ref, null, catalog.isDemo)
                      : showDialog<void>(
                          context: context,
                          builder: (_) => const MenuEditor(),
                        ),
                ),
              ),
              if (!catalog.isDemo)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  margin: const EdgeInsets.only(bottom: 20),
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
                        'Live Catalog · Realtime synchronized with Supabase',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              if (categoriesOnly) ...[
                for (final category in catalog.categories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CafeCard(
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            category.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '${catalog.products.where((p) => p.categoryId == category.id && !p.archived).length} items',
                          ),
                          StatusPill(category.active ? 'Active' : 'Hidden'),
                          TextButton(
                            onPressed: () => editCategory(
                              context,
                              ref,
                              category,
                              catalog.isDemo,
                            ),
                            child: const Text('Edit category'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ] else ...[
                if (catalog.products.isEmpty)
                  const CafeEmptyState(
                    title: 'Your menu starts here',
                    message: 'Add the first item when management is available.',
                  ),
                for (final product in catalog.products)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CafeCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 20,
                            runSpacing: 16,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: 100,
                                child: ProductImage(
                                  product: product,
                                  height: 80,
                                ),
                              ),
                              Text(
                                product.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(money(product.priceMinor)),
                              StatusPill(
                                product.archived
                                    ? 'Archived'
                                    : product.available
                                    ? 'Available'
                                    : 'Unavailable',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(product.description),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: product.archived
                                    ? null
                                    : () => showDialog<void>(
                                        context: context,
                                        builder: (_) =>
                                            MenuEditor(product: product),
                                      ),
                                child: const Text('Edit item'),
                              ),
                              TextButton(
                                onPressed: product.archived
                                    ? null
                                    : () async {
                                        if (catalog.isDemo) {
                                          ref
                                              .read(
                                                demoCatalogProvider.notifier,
                                              )
                                              .save(
                                                product.copyWith(
                                                  available: !product.available,
                                                ),
                                              );
                                          return;
                                        }
                                        final repo = ref.read(
                                          menuRepositoryProvider,
                                        );
                                        if (repo is SupabaseMenuRepository) {
                                          await repo.setMenuItemAvailability(
                                            itemId: product.id,
                                            available: !product.available,
                                          );
                                          ref.invalidate(catalogProvider);
                                        }
                                      },
                                child: Text(
                                  product.available ? 'Disable' : 'Enable',
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  if (catalog.isDemo) {
                                    ref
                                        .read(demoCatalogProvider.notifier)
                                        .save(
                                          product.copyWith(
                                            archived: !product.archived,
                                          ),
                                        );
                                    return;
                                  }
                                  final repo = ref.read(menuRepositoryProvider);
                                  if (repo is SupabaseMenuRepository) {
                                    if (!product.archived) {
                                      await repo.archiveMenuItem(
                                        itemId: product.id,
                                      );
                                    }
                                    ref.invalidate(catalogProvider);
                                  }
                                },
                                child: Text(
                                  product.archived ? 'Restore' : 'Archive',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
  );

  Future<void> editCategory(
    BuildContext context,
    WidgetRef ref, [
    MenuCategory? category,
    bool isDemo = true,
  ]) async {
    final controller = TextEditingController(text: category?.name);
    var active = category?.active ?? true;
    String? error;
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(category == null ? 'Add category' : 'Edit category'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Category name',
                    errorText: error,
                  ),
                ),
                SwitchListTile(
                  title: const Text('Visible category'),
                  value: active,
                  onChanged: (v) => setState(() => active = v),
                ),
              ],
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
                      final name = controller.text.trim();
                      if (name.isEmpty) {
                        setState(() => error = 'Enter a valid name.');
                        return;
                      }

                      if (!isDemo) {
                        final repo = ref.read(menuRepositoryProvider);
                        final auth = ref.read(authControllerProvider);
                        final restId = auth.activeMembership?.restaurantId;

                        if (repo is SupabaseMenuRepository && restId != null) {
                          setState(() => isSaving = true);
                          try {
                            if (category == null) {
                              await repo.createCategory(
                                restaurantId: restId,
                                name: name,
                              );
                            } else {
                              await repo.updateCategory(
                                categoryId: category.id,
                                name: name,
                                active: active,
                              );
                            }
                            ref.invalidate(catalogProvider);
                            if (context.mounted) Navigator.pop(context);
                          } catch (e) {
                            setState(() {
                              isSaving = false;
                              error = e is AppFailure
                                  ? e.message
                                  : 'Failed to save category.';
                            });
                          }
                          return;
                        }
                      }

                      // Demo fallback
                      try {
                        ref
                            .read(demoCatalogProvider.notifier)
                            .category(
                              controller.text,
                              id: category?.id,
                              active: active,
                            );
                        Navigator.pop(context);
                      } on ArgumentError catch (_) {
                        setState(
                          () => error = 'Enter a unique, non-empty name.',
                        );
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isDemo ? 'Save local category' : 'Save category'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }
}
