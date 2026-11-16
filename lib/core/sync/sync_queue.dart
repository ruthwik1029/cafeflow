import 'dart:math';

import '../storage/local_database.dart';
import 'sync_models.dart';

/// Manages the durable, persistent synchronization queue.
class SyncQueue {
  SyncQueue(this._database);
  final CafeLocalDatabase _database;

  static const String collection = 'sync_queue';
  static const int maxRetries = 5;

  /// Enqueues a new operation to the durable queue.
  Future<void> enqueue(SyncQueueItem item) async {
    await _database.put(collection, item.id, item.toMap());
  }

  /// Returns pending or retry-ready queue operations in strict dependency order:
  /// (Orders before Payments, then by creation date ascending).
  Future<List<SyncQueueItem>> getPendingOperations({
    required String restaurantId,
  }) async {
    final rows = await _database.query(
      collection,
      where: {'restaurant_id': restaurantId},
    );

    final now = DateTime.now();
    final items = rows.map(SyncQueueItem.fromMap).where((item) {
      if (item.status == SyncStatus.pending) return true;
      if (item.status == SyncStatus.retry) {
        if (item.nextRetryAt == null || item.nextRetryAt!.isBefore(now)) {
          return true;
        }
      }
      return false;
    }).toList();

    // Sort by dependency order:
    // 1. Orders first (payment requires order ID)
    // 2. Created timestamp ascending (oldest first)
    items.sort((a, b) {
      if (a.entityType == SyncEntityType.order &&
          b.entityType != SyncEntityType.order) {
        return -1;
      }
      if (a.entityType != SyncEntityType.order &&
          b.entityType == SyncEntityType.order) {
        return 1;
      }
      return a.createdAt.compareTo(b.createdAt);
    });

    return items;
  }

  /// Marks an item as actively processing to prevent concurrent execution.
  Future<void> markProcessing(String id) async {
    final existing = await _database.get(collection, id);
    if (existing != null) {
      final updated = Map<String, dynamic>.from(existing)
        ..['status'] = SyncStatus.processing.dbValue
        ..['last_attempted_at'] = DateTime.now().toIso8601String();
      await _database.put(collection, id, updated);
    }
  }

  /// Marks an item as durably synced following server acknowledgement.
  Future<void> markSynced(
    String id, {
    Map<String, dynamic>? serverResult,
  }) async {
    final existing = await _database.get(collection, id);
    if (existing != null) {
      final updated = Map<String, dynamic>.from(existing)
        ..['status'] = SyncStatus.synced.dbValue
        ..['last_attempted_at'] = DateTime.now().toIso8601String()
        ..['server_result'] = serverResult;
      await _database.put(collection, id, updated);
    }
  }

  /// Flags an item for exponential backoff retry.
  Future<void> markRetry(String id, String error) async {
    final existing = await _database.get(collection, id);
    if (existing == null) return;

    final item = SyncQueueItem.fromMap(existing);
    final newRetryCount = item.retryCount + 1;

    if (newRetryCount >= maxRetries) {
      // Exceeded maximum attempts -> mark failed for manual intervention
      final updated = item.copyWith(
        status: SyncStatus.failed,
        lastError: error,
        lastAttemptedAt: DateTime.now(),
        retryCount: newRetryCount,
        nextRetryAt: null,
      );
      await _database.put(collection, id, updated.toMap());
      return;
    }

    // Exponential backoff: min(300s, 2^(retryCount) * 3s)
    final delaySeconds = min(300, pow(2, newRetryCount).toInt() * 3);
    final nextRetry = DateTime.now().add(Duration(seconds: delaySeconds));

    final updated = item.copyWith(
      status: SyncStatus.retry,
      lastError: error,
      lastAttemptedAt: DateTime.now(),
      retryCount: newRetryCount,
      nextRetryAt: nextRetry,
    );
    await _database.put(collection, id, updated.toMap());
  }

  /// Flags an item with conflict status and records conflict audit details.
  Future<void> markConflict({
    required String id,
    required String reason,
    Map<String, dynamic>? serverPayload,
  }) async {
    final existing = await _database.get(collection, id);
    if (existing == null) return;

    final item = SyncQueueItem.fromMap(existing);
    final updated = item.copyWith(
      status: SyncStatus.conflict,
      lastError: reason,
      lastAttemptedAt: DateTime.now(),
    );
    await _database.put(collection, id, updated.toMap());

    // Record in local sync_conflicts collection
    final conflictId = 'cf_${DateTime.now().millisecondsSinceEpoch}_${item.id}';
    final conflict = SyncConflict(
      id: conflictId,
      restaurantId: item.restaurantId,
      entityType: item.entityType.name.toUpperCase(),
      entityId: item.entityId,
      clientTxId: item.clientTxId,
      clientVersion: item.localVersion,
      conflictReason: reason,
      clientPayload: item.payload,
      serverPayload: serverPayload,
      createdAt: DateTime.now(),
    );
    await _database.put('sync_conflicts', conflictId, conflict.toMap());
  }

  /// Resets failed or retry queue items back to pending for manual retry.
  Future<int> retryAllFailed({required String restaurantId}) async {
    final rows = await _database.query(
      collection,
      where: {'restaurant_id': restaurantId},
    );

    int count = 0;
    for (final row in rows) {
      final item = SyncQueueItem.fromMap(row);
      if (item.status == SyncStatus.failed ||
          item.status == SyncStatus.retry ||
          item.status == SyncStatus.processing) {
        final updated = item.copyWith(
          status: SyncStatus.pending,
          nextRetryAt: null,
          retryCount: 0,
        );
        await _database.put(collection, item.id, updated.toMap());
        count++;
      }
    }
    return count;
  }

  /// Counts pending items in queue.
  Future<int> getPendingCount({required String restaurantId}) async {
    final rows = await _database.query(
      collection,
      where: {'restaurant_id': restaurantId},
    );
    return rows.where((r) {
      final s = r['status'] as String?;
      return s == 'PENDING' || s == 'PROCESSING' || s == 'RETRY';
    }).length;
  }

  /// Counts failed items in queue.
  Future<int> getFailedCount({required String restaurantId}) async {
    final rows = await _database.query(
      collection,
      where: {'restaurant_id': restaurantId},
    );
    return rows.where((r) => (r['status'] as String?) == 'FAILED').length;
  }

  /// Counts unresolved conflicts in queue.
  Future<int> getConflictCount({required String restaurantId}) async {
    final rows = await _database.query(
      collection,
      where: {'restaurant_id': restaurantId},
    );
    return rows.where((r) => (r['status'] as String?) == 'CONFLICT').length;
  }
}
