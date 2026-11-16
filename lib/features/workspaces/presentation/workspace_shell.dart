import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/workspace.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cafe_components.dart';

class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({
    required this.workspace,
    required this.available,
    required this.location,
    required this.child,
    super.key,
  });
  final WorkspaceDefinition workspace;
  final List<WorkspaceDefinition> available;
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= CafeSpace.desktop;
    return Scaffold(
      drawer: wide ? null : Drawer(child: _navigation(context, drawer: true)),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) SizedBox(width: 248, child: _navigation(context)),
            if (wide) const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 32 : 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (!wide)
                          Builder(
                            builder: (context) => IconButton(
                              tooltip: 'Open navigation',
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer(),
                              icon: const Icon(Icons.menu_rounded),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            workspace.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (wide)
                          const Padding(
                            padding: EdgeInsets.only(right: 16),
                            child: StatusPill(
                              'Development preview',
                              icon: Icons.code_rounded,
                            ),
                          ),
                        const ThemeControl(),
                      ],
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navigation(BuildContext context, {bool drawer = false}) {
    void go(String path) {
      if (drawer) Navigator.pop(context);
      context.go(path);
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 28, 16, 32),
              child: CafeBrand(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'WORKSPACE',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(letterSpacing: 2),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final section in workspace.sections)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _NavTile(
                        label: section.label,
                        icon: section.icon,
                        selected: location == workspace.path(section.id),
                        onTap: () => go(workspace.path(section.id)),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(),
                  ),
                  _NavTile(
                    label: 'Design system',
                    icon: Icons.palette_outlined,
                    selected: location.endsWith('/design-system'),
                    onTap: () => go(workspace.path('design-system')),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Different roles. One flow.',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Preview a workspace. This is not an authenticated session.',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    PopupMenuButton<WorkspaceDefinition>(
                      tooltip: 'Switch demo workspace',
                      onSelected: (value) => go(value.home),
                      itemBuilder: (_) => available
                          .map(
                            (value) => PopupMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                          )
                          .toList(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.swap_horiz_rounded, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Switch workspace',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Text(
                'CAFÉFLOW  /  FOUNDATION 01',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(letterSpacing: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    selected: selected,
    selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
    selectedColor: Theme.of(context).colorScheme.onPrimaryContainer,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    leading: Icon(icon, size: 21),
    title: Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    minLeadingWidth: 20,
    onTap: onTap,
  );
}
