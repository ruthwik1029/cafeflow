import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/workspace.dart';
import '../../../core/services/backend.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cafe_components.dart';

class WorkspacePage extends ConsumerWidget {
  const WorkspacePage({
    required this.workspace,
    required this.section,
    super.key,
  });
  final WorkspaceDefinition workspace;
  final WorkspaceSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = section == workspace.sections.first;
    final backend = ref.watch(backendProvider);
    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 20,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workspace.eyebrow,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(letterSpacing: 2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    section.label,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ],
              ),
              const StatusPill(
                'Phase 01 · Foundation',
                icon: Icons.layers_outlined,
              ),
            ],
          ),
          const SizedBox(height: 28),
          if (overview) ...[
            WorkspaceHero(workspace: workspace),
            const SizedBox(height: 24),
            AdaptiveColumns(
              children: [
                const MetricCard(
                  label: 'CONNECTED VISION',
                  value: '3 platforms',
                  detail: 'Windows · Android · Web',
                  icon: Icons.devices_rounded,
                ),
                const MetricCard(
                  label: 'DESIGNED TOGETHER',
                  value: '5 workspaces',
                  detail: 'One shared business foundation',
                  icon: Icons.dashboard_customize_outlined,
                ),
                const MetricCard(
                  label: 'REALTIME',
                  value: 'Prepared',
                  detail: 'No active data subscriptions',
                  icon: Icons.wifi_tethering_rounded,
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'A place for every part of your café.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Explore the workspace structure. Operational features are planned for later phases.',
            ),
            const SizedBox(height: 20),
            AdaptiveColumns(
              minWidth: 270,
              children: [
                for (final item in workspace.sections.skip(1))
                  CafeCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.icon, size: 25),
                        const SizedBox(height: 18),
                        Text(
                          item.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(item.description),
                        const SizedBox(height: 14),
                        TextButton(
                          onPressed: () => context.go(workspace.path(item.id)),
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onSurface,
                          ),
                          child: const Text('Explore foundation →'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ] else ...[
            Text(
              section.description,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            CafeEmptyState(
              title: '${section.label} starts here',
              icon: section.icon,
              message: 'The navigation and visual foundation are ready. This module has no operational data or write actions in Phase 01.',
            ),
          ],
          const SizedBox(height: 28),
          CafeCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  backend.status == BackendStatus.initialized
                      ? Icons.cloud_queue
                      : Icons.cloud_off_outlined,
                  size: 24,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(switch (backend.status) {
                        BackendStatus.unconfigured => 'Backend not configured',
                        BackendStatus.invalidConfiguration =>
                          'Configuration needs attention',
                        BackendStatus.initialized =>
                          'Supabase client initialized',
                        BackendStatus.failed => 'Backend initialization failed',
                      }, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(backend.message),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Built with care. Ready to grow.',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class WorkspaceHero extends StatelessWidget {
  const WorkspaceHero({required this.workspace, super.key});
  final WorkspaceDefinition workspace;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final roomy = constraints.maxWidth > 760;
      return Container(
        padding: EdgeInsets.all(roomy ? 36 : 24),
        decoration: BoxDecoration(
          color: CafeColors.graphite,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF454B54)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'GOOD DAYS START WITH A BETTER FLOW',
                    style: TextStyle(
                      color: CafeColors.mint,
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    workspace.headline,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: CafeColors.ivory,
                      fontSize: roomy ? 40 : 30,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    workspace.description,
                    style: const TextStyle(
                      color: Color(0xFFC8CDCE),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  CafeButton(
                    label: 'Explore the design system',
                    onPressed: () =>
                        context.go(workspace.path('design-system')),
                  ),
                ],
              ),
            ),
            if (roomy) ...[const SizedBox(width: 32), const _CoffeeMark()],
          ],
        ),
      );
    },
  );
}

class _CoffeeMark extends StatelessWidget {
  const _CoffeeMark();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 218,
            height: 218,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF616750)),
            ),
          ),
          Container(
            width: 186,
            height: 186,
            decoration: const BoxDecoration(
              color: CafeColors.coral,
              shape: BoxShape.circle,
            ),
          ),
          const Icon(
            Icons.coffee_rounded,
            size: 100,
            color: CafeColors.charcoal,
          ),
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: CafeColors.mint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'CRAFTED FOR SERVICE',
                style: TextStyle(
                  color: CafeColors.charcoal,
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
