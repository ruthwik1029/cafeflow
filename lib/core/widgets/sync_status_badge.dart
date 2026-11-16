import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../routing/workspace.dart';
import '../sync/cafe_sync_service.dart';
import '../sync/sync_models.dart';
import 'cafe_components.dart';

/// Reusable connectivity and synchronization status indicator widget.
class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncService = ref.watch(syncServiceProvider);
    final syncStateAsync = ref.watch(syncStateProvider);
    final state = syncStateAsync.value ?? syncService.currentState;
    final auth = ref.watch(authControllerProvider);
    final restaurantId = auth.activeMembership?.restaurantId ?? 'default';

    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    if (state.isSyncing) {
      bgColor = Colors.blue.shade100;
      textColor = Colors.blue.shade900;
      icon = Icons.sync;
      label = state.pendingCount > 0
          ? 'Syncing (${state.pendingCount})...'
          : 'Syncing...';
    } else if (state.conflictCount > 0) {
      bgColor = Colors.deepOrange.shade100;
      textColor = Colors.deepOrange.shade900;
      icon = Icons.warning_amber_rounded;
      label =
          '${state.conflictCount} Conflict${state.conflictCount > 1 ? "s" : ""}';
    } else if (state.failedCount > 0) {
      bgColor = Colors.red.shade100;
      textColor = Colors.red.shade900;
      icon = Icons.error_outline;
      label = '${state.failedCount} Failed';
    } else if (!state.isOnline) {
      bgColor = Colors.amber.shade100;
      textColor = Colors.amber.shade900;
      icon = Icons.cloud_off_outlined;
      label = state.pendingCount > 0
          ? 'Offline (${state.pendingCount} pending)'
          : 'Offline Mode';
    } else {
      bgColor = Colors.green.shade100;
      textColor = Colors.green.shade900;
      icon = Icons.cloud_done_outlined;
      label = state.pendingCount > 0
          ? '${state.pendingCount} Pending Sync'
          : 'Cloud Synced';
    }

    return InkWell(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (context) =>
              SyncManagementDialog(restaurantId: restaurantId),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: textColor.withValues(alpha: 0.3)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: textColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Comprehensive synchronization management dialog.
class SyncManagementDialog extends ConsumerStatefulWidget {
  const SyncManagementDialog({required this.restaurantId, super.key});
  final String restaurantId;

  @override
  ConsumerState<SyncManagementDialog> createState() =>
      _SyncManagementDialogState();
}

class _SyncManagementDialogState extends ConsumerState<SyncManagementDialog> {
  bool _isProcessing = false;
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    final syncService = ref.watch(syncServiceProvider);
    final syncQueue = ref.watch(syncQueueProvider);
    final syncStateAsync = ref.watch(syncStateProvider);
    final state = syncStateAsync.value ?? syncService.currentState;
    final auth = ref.watch(authControllerProvider);
    final isPrivileged =
        auth.activeRole == WorkspaceRole.owner ||
        auth.activeRole == WorkspaceRole.admin;

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(child: Text('Synchronization & Offline Center')),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Connection status card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: state.isOnline
                      ? Colors.green.shade50
                      : Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: state.isOnline
                        ? Colors.green.shade300
                        : Colors.amber.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      state.isOnline ? Icons.wifi : Icons.wifi_off,
                      color: state.isOnline
                          ? Colors.green.shade800
                          : Colors.amber.shade900,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.isOnline
                                ? 'Online · Cloud Connected'
                                : 'Offline · Local Persistence Active',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: state.isOnline
                                  ? Colors.green.shade900
                                  : Colors.amber.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            state.lastSyncTime != null
                                ? 'Last synced: ${state.lastSyncTime!.hour.toString().padLeft(2, '0')}:${state.lastSyncTime!.minute.toString().padLeft(2, '0')}:${state.lastSyncTime!.second.toString().padLeft(2, '0')}'
                                : 'Awaiting first synchronization',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. Queue Metrics
              Row(
                children: [
                  Expanded(
                    child: _metricBox(
                      'Pending Ops',
                      '${state.pendingCount}',
                      Colors.blue,
                      Icons.schedule,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metricBox(
                      'Failed Ops',
                      '${state.failedCount}',
                      Colors.red,
                      Icons.error_outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metricBox(
                      'Conflicts',
                      '${state.conflictCount}',
                      Colors.deepOrange,
                      Icons.rule,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_statusMessage != null) ...[
                Text(
                  _statusMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // 3. Action Controls
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.sync, size: 16),
                    label: const Text('Sync Now'),
                    onPressed: _isProcessing
                        ? null
                        : () async {
                            setState(() {
                              _isProcessing = true;
                              _statusMessage =
                                  'Running synchronization sweep...';
                            });
                            await syncService.synchronize(
                              restaurantId: widget.restaurantId,
                            );
                            if (mounted) {
                              setState(() {
                                _isProcessing = false;
                                _statusMessage = 'Sync sweep completed.';
                              });
                            }
                          },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh Cache'),
                    onPressed: _isProcessing
                        ? null
                        : () async {
                            setState(() {
                              _isProcessing = true;
                              _statusMessage =
                                  'Refreshing local cache from cloud...';
                            });
                            await syncService.refreshCache(
                              restaurantId: widget.restaurantId,
                            );
                            if (mounted) {
                              setState(() {
                                _isProcessing = false;
                                _statusMessage =
                                    'Cache refreshed successfully.';
                              });
                            }
                          },
                  ),
                  if (state.failedCount > 0 && isPrivileged)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.replay, size: 16),
                      label: const Text('Retry Failed'),
                      onPressed: _isProcessing
                          ? null
                          : () async {
                              final count = await syncQueue.retryAllFailed(
                                restaurantId: widget.restaurantId,
                              );
                              await syncService.synchronize(
                                restaurantId: widget.restaurantId,
                              );
                              if (mounted) {
                                setState(() {
                                  _statusMessage =
                                      '$count operations queued for retry.';
                                });
                              }
                            },
                    ),
                ],
              ),
              const Divider(height: 28),

              // 4. Queue Items Preview
              Text(
                'Pending & Recent Operations',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<SyncQueueItem>>(
                future: syncQueue.getPendingOperations(
                  restaurantId: widget.restaurantId,
                ),
                builder: (context, snapshot) {
                  final items = snapshot.data ?? [];
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No pending synchronization operations. All local actions are cloud-confirmed.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final item = items[idx];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(switch (item.operationType) {
                          SyncOperationType.createOrder => Icons.receipt_long,
                          SyncOperationType.recordPayment => Icons.payment,
                          _ => Icons.data_object,
                        }, size: 20),
                        title: Text(
                          '${item.operationType.name} · ${item.clientTxId}',
                        ),
                        subtitle: Text(
                          'Created: ${item.createdAt.hour}:${item.createdAt.minute} · Status: ${item.status.label}${item.retryCount > 0 ? " (Retries: ${item.retryCount})" : ""}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: StatusPill(item.status.label),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _metricBox(
    String label,
    String value,
    MaterialColor color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.shade200),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color.shade700),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color.shade900,
            ),
          ),
        ],
      ),
    );
  }
}
