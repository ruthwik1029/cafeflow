import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class CafeBrand extends StatelessWidget {
  const CafeBrand({super.key});
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: CafeColors.coral,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.local_cafe_rounded,
            color: CafeColors.charcoal,
            size: 23,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'CafeFlow',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 25),
        ),
      ],
    ),
  );
}

class CafeButton extends StatelessWidget {
  const CafeButton({
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
    this.secondary = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool secondary;
  @override
  Widget build(BuildContext context) => secondary
      ? OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        )
      : FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
}

class CafeCard extends StatelessWidget {
  const CafeCard({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class CafeInput extends StatelessWidget {
  const CafeInput({
    required this.label,
    this.hint,
    this.controller,
    this.onChanged,
    super.key,
  });
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {this.icon = Icons.circle_outlined, super.key});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 7),
        Flexible(
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
      ],
    ),
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    super.key,
  });
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  @override
  Widget build(BuildContext context) => CafeCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
            Icon(icon, size: 20),
          ],
        ),
        const SizedBox(height: 20),
        Text(value, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 6),
        Text(
          detail,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class CafeEmptyState extends StatelessWidget {
  const CafeEmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    super.key,
  });
  final String title;
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => CafeCard(
    child: Column(
      children: [
        Icon(
          icon,
          size: 36,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}

class CafeErrorState extends StatelessWidget {
  const CafeErrorState({required this.message, this.onRetry, super.key});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => CafeCard(
    child: Column(
      children: [
        Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          CafeButton(
            label: 'Try again',
            icon: Icons.refresh,
            onPressed: onRetry,
          ),
        ],
      ],
    ),
  );
}

class CafeLoadingState extends StatelessWidget {
  const CafeLoadingState({this.label = 'Loading', super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: label,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: MediaQuery.disableAnimationsOf(context) ? 0.7 : null,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    ),
  );
}

Future<void> showCafeDialog(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Got it'),
      ),
    ],
  ),
);

class ThemeControl extends ConsumerWidget {
  const ThemeControl({super.key});
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => PopupMenuButton<ThemeMode>(
    tooltip: 'Change theme',
    initialValue: ref.watch(themeControllerProvider),
    icon: Icon(
      Theme.of(context).brightness == Brightness.dark
          ? Icons.dark_mode_outlined
          : Icons.light_mode_outlined,
    ),
    onSelected: (mode) async {
      final saved = await ref
          .read(themeControllerProvider.notifier)
          .setMode(mode);
      if (!saved && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Theme changed for this session. Preference could not be saved.',
            ),
          ),
        );
      }
    },
    itemBuilder: (_) => ThemeMode.values
        .map(
          (mode) => CheckedPopupMenuItem(
            value: mode,
            checked: ref.read(themeControllerProvider) == mode,
            child: Text(switch (mode) {
              ThemeMode.system => 'System',
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
            }),
          ),
        )
        .toList(),
  );
}

class PageBody extends StatelessWidget {
  const PageBody({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1440),
        child: Padding(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 20 : 32,
          ),
          child: child,
        ),
      ),
    ),
  );
}

class AdaptiveColumns extends StatelessWidget {
  const AdaptiveColumns({
    required this.children,
    this.minWidth = 250,
    super.key,
  });
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = ((constraints.maxWidth + 16) / (minWidth + 16))
          .floor()
          .clamp(1, children.length);
      final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(),
      );
    },
  );
}
