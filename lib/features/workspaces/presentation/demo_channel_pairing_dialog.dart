import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/cafe_components.dart';

class DemoChannelPairingDialog extends StatelessWidget {
  const DemoChannelPairingDialog({
    required this.pairingCode,
    required this.restaurantId,
    super.key,
  });

  final String pairingCode;
  final String restaurantId;

  static Future<void> show(
    BuildContext context, {
    required String pairingCode,
    required String restaurantId,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => DemoChannelPairingDialog(
        pairingCode: pairingCode,
        restaurantId: restaurantId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.sensors_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live Demo Channel Pairing',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Flagship Bistro · Live Cloud Connected',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.primary.withAlpha(16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.primary.withAlpha(60),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'CHANNEL PAIRING CODE',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      pairingCode,
                      style: theme.textTheme.displayMedium?.copyWith(
                        letterSpacing: 6,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy Channel Code'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: pairingCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Channel code $pairingCode copied to clipboard.',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'How to test end-to-end ordering:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              _buildStep(
                theme,
                step: '1',
                title: 'Open Customer Menu',
                desc: 'Open the customer site (/menu) in another window or browser tab.',
              ),
              _buildStep(
                theme,
                step: '2',
                title: 'Add Items & Checkout',
                desc: 'Add delicious drinks or pastries and click "Review Cart & Order".',
              ),
              _buildStep(
                theme,
                step: '3',
                title: 'Enter Pairing Code',
                desc:
                    'Enter $pairingCode in the checkout sheet to route orders directly to this screen.',
              ),
              _buildStep(
                theme,
                step: '4',
                title: 'Live Realtime Synchronization',
                desc: 'Watch the order arrive on Cashier POS & Kitchen KOT instantly!',
              ),
              const SizedBox(height: 20),
              CafeButton(
                label: 'Got It',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(
    ThemeData theme, {
    required String step,
    required String title,
    required String desc,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              step,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
