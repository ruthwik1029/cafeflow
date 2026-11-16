import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cafe_components.dart';

class DesignSystemPage extends StatelessWidget {
  const DesignSystemPage({super.key});
  @override
  Widget build(BuildContext context) => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The CafeFlow language.',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'A working component gallery. All examples below are local UI previews.',
        ),
        const SizedBox(height: 28),
        AdaptiveColumns(
          minWidth: 150,
          children: const [
            _Swatch(
              'Deep Charcoal',
              '#20242A',
              CafeColors.charcoal,
              CafeColors.ivory,
            ),
            _Swatch(
              'Graphite',
              '#292E36',
              CafeColors.graphite,
              CafeColors.ivory,
            ),
            _Swatch(
              'Vivid Coral',
              '#FF4B2F',
              CafeColors.coral,
              CafeColors.charcoal,
            ),
            _Swatch(
              'Soft Mint',
              '#EEFFEC',
              CafeColors.mint,
              CafeColors.charcoal,
            ),
            _Swatch(
              'Warm Ivory',
              '#F5F4E9',
              CafeColors.ivory,
              CafeColors.charcoal,
            ),
          ],
        ),
        const SizedBox(height: 24),
        CafeCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Considered type. Clear purpose.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Space Grotesk gives headlines their character. Inter keeps the everyday details effortless to read. Both font families are bundled for offline use.',
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  CafeButton(
                    label: 'Open a dialog',
                    onPressed: () => showCafeDialog(
                      context,
                      title: 'A moment of clarity',
                      message: 'Dialogs share the same Material 3 theme, keyboard focus behavior, and accessible controls. This preview does not change business data.',
                    ),
                  ),
                  CafeButton(
                    label: 'Secondary action',
                    secondary: true,
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Local component preview. No backend operation was performed.',
                        ),
                      ),
                    ),
                  ),
                  const CafeButton(
                    label: 'Unavailable action',
                    onPressed: null,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const CafeInput(
                label: 'Example input',
                hint: 'Try typing here — this value is not saved',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const AdaptiveColumns(
          children: [
            CafeEmptyState(
              title: 'Room for something good',
              message: 'An empty-state example with a clear explanation.',
            ),
            CafeErrorState(
              message: 'An error-state example. Real failures will provide safe, actionable messages.',
            ),
          ],
        ),
        const SizedBox(height: 16),
        const CafeCard(child: CafeLoadingState(label: 'Loading-state preview')),
        const SizedBox(height: 24),
        Text(
          'Spacing: 4 · 8 · 16 · 24 · 32 · 48   /   Card radius: 20',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ],
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.hex, this.color, this.foreground);
  final String name;
  final String hex;
  final Color color;
  final Color foreground;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Text(
          name,
          style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(hex, style: TextStyle(color: foreground, fontSize: 12)),
      ],
    ),
  );
}
