import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/cafe_components.dart';
import '../../orders/domain/cafe_order.dart';
import '../application/customer_order_service.dart';

class CustomerOrderTrackingDialog extends ConsumerStatefulWidget {
  const CustomerOrderTrackingDialog({
    required this.orderId,
    required this.orderNumber,
    this.pairingCode,
    super.key,
  });

  final String orderId;
  final String orderNumber;
  final String? pairingCode;

  static Future<void> show(
    BuildContext context, {
    required String orderId,
    required String orderNumber,
    String? pairingCode,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerOrderTrackingDialog(
        orderId: orderId,
        orderNumber: orderNumber,
        pairingCode: pairingCode,
      ),
    );
  }

  @override
  ConsumerState<CustomerOrderTrackingDialog> createState() =>
      _CustomerOrderTrackingDialogState();
}

class _CustomerOrderTrackingDialogState
    extends ConsumerState<CustomerOrderTrackingDialog> {
  OrderStatus _currentStatus = OrderStatus.newOrder;
  StreamSubscription<OrderStatus>? _sub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    final service = ref.read(customerOrderServiceProvider);
    // Initial fetch to get latest status
    service
        .fetchOrderStatus(widget.orderId)
        .then((tracked) {
          if (mounted) {
            setState(() => _currentStatus = tracked.status);
          }
        })
        .catchError((_) {});

    // Realtime subscription for live updates
    _sub = service.watchOrderStatus(widget.orderId).listen((status) {
      if (mounted) {
        setState(() => _currentStatus = status);
      }
    });

    // Dual-mode polling fallback every 5 seconds to ensure tracking stays
    // synchronized even if websockets are blocked by client firewalls or proxies
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      service
          .fetchOrderStatus(widget.orderId)
          .then((tracked) {
            if (mounted && _currentStatus != tracked.status) {
              setState(() => _currentStatus = tracked.status);
            }
          })
          .catchError((_) {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  int get _stepIndex => switch (_currentStatus) {
    OrderStatus.newOrder => 0,
    OrderStatus.preparing => 1,
    OrderStatus.ready => 2,
    OrderStatus.completed => 3,
    OrderStatus.cancelled => 0,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.check_circle_outline_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Placed Successfully!',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Live Kitchen Status Tracking',
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
              const SizedBox(height: 20),

              // Order Number Card
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
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
                      'ORDER NUMBER',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.orderNumber,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (widget.pairingCode != null &&
                        widget.pairingCode!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.sensors_rounded,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Paired to Channel: ${widget.pairingCode}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Status Stepper
              Text(
                'Live Order Progress',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),

              _buildStatusStep(
                theme,
                stepNumber: 1,
                title: 'Order Received',
                subtitle: 'Order received and logged in kitchen queue.',
                isActive: _stepIndex >= 0,
                isCurrent: _stepIndex == 0,
              ),
              _buildStatusStep(
                theme,
                stepNumber: 2,
                title: 'Preparing in Kitchen',
                subtitle: 'Barista & kitchen staff are preparing your items.',
                isActive: _stepIndex >= 1,
                isCurrent: _stepIndex == 1,
              ),
              _buildStatusStep(
                theme,
                stepNumber: 3,
                title: 'Ready for Serving / Pickup',
                subtitle: 'Your order is freshly prepared and ready!',
                isActive: _stepIndex >= 2,
                isCurrent: _stepIndex == 2,
              ),
              _buildStatusStep(
                theme,
                stepNumber: 4,
                title: 'Completed',
                subtitle: 'Served and settled. Thank you for dining with us!',
                isActive: _stepIndex >= 3,
                isCurrent: _stepIndex == 3,
                isLast: true,
              ),

              const SizedBox(height: 24),
              CafeButton(
                label: 'Order More Items',
                secondary: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusStep(
    ThemeData theme, {
    required int stepNumber,
    required String title,
    required String subtitle,
    required bool isActive,
    required bool isCurrent,
    bool isLast = false,
  }) {
    final color = isCurrent
        ? theme.colorScheme.primary
        : (isActive ? Colors.green : theme.colorScheme.outlineVariant);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isActive ? color : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: Center(
                child: isActive && !isCurrent
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : isCurrent
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        '$stepNumber',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 28,
                color: isActive
                    ? Colors.green
                    : theme.colorScheme.outlineVariant,
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
