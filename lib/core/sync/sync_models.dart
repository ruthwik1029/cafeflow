enum SyncEntityType { order, payment, inventory, table, menu, staff }

enum SyncOperationType {
  createOrder,
  recordPayment,
  updateTableStatus,
  adjustStock,
  recordAttendance,
}

enum SyncStatus {
  pending,
  processing,
  synced,
  retry,
  conflict,
  failed,
  requiresReview,
}

extension SyncStatusX on SyncStatus {
  String get label => switch (this) {
    SyncStatus.pending => 'Waiting for sync',
    SyncStatus.processing => 'Synchronizing...',
    SyncStatus.synced => 'Synchronized',
    SyncStatus.retry => 'Retrying...',
    SyncStatus.conflict => 'Conflict detected',
    SyncStatus.failed => 'Sync failed',
    SyncStatus.requiresReview => 'Requires review',
  };

  String get dbValue => switch (this) {
    SyncStatus.pending => 'PENDING',
    SyncStatus.processing => 'PROCESSING',
    SyncStatus.synced => 'SYNCED',
    SyncStatus.retry => 'RETRY',
    SyncStatus.conflict => 'CONFLICT',
    SyncStatus.failed => 'FAILED',
    SyncStatus.requiresReview => 'REQUIRES_REVIEW',
  };

  static SyncStatus fromDb(String? value) => switch (value?.toUpperCase()) {
    'PENDING' => SyncStatus.pending,
    'PROCESSING' => SyncStatus.processing,
    'SYNCED' => SyncStatus.synced,
    'RETRY' => SyncStatus.retry,
    'CONFLICT' => SyncStatus.conflict,
    'FAILED' => SyncStatus.failed,
    'REQUIRES_REVIEW' => SyncStatus.requiresReview,
    _ => SyncStatus.pending,
  };
}

/// A durable synchronization queue item persisted in the local database.
class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.clientTxId,
    required this.restaurantId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.payload,
    this.localVersion = 1,
    this.baseServerVersion = 1,
    required this.createdAt,
    this.lastAttemptedAt,
    this.retryCount = 0,
    this.status = SyncStatus.pending,
    this.lastError,
    this.nextRetryAt,
  });

  final String id;
  final String clientTxId;
  final String restaurantId;
  final SyncEntityType entityType;
  final String entityId;
  final SyncOperationType operationType;
  final Map<String, dynamic> payload;
  final int localVersion;
  final int baseServerVersion;
  final DateTime createdAt;
  final DateTime? lastAttemptedAt;
  final int retryCount;
  final SyncStatus status;
  final String? lastError;
  final DateTime? nextRetryAt;

  SyncQueueItem copyWith({
    String? id,
    String? clientTxId,
    String? restaurantId,
    SyncEntityType? entityType,
    String? entityId,
    SyncOperationType? operationType,
    Map<String, dynamic>? payload,
    int? localVersion,
    int? baseServerVersion,
    DateTime? createdAt,
    DateTime? lastAttemptedAt,
    int? retryCount,
    SyncStatus? status,
    String? lastError,
    DateTime? nextRetryAt,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      clientTxId: clientTxId ?? this.clientTxId,
      restaurantId: restaurantId ?? this.restaurantId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operationType: operationType ?? this.operationType,
      payload: payload ?? this.payload,
      localVersion: localVersion ?? this.localVersion,
      baseServerVersion: baseServerVersion ?? this.baseServerVersion,
      createdAt: createdAt ?? this.createdAt,
      lastAttemptedAt: lastAttemptedAt ?? this.lastAttemptedAt,
      retryCount: retryCount ?? this.retryCount,
      status: status ?? this.status,
      lastError: lastError ?? this.lastError,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'client_tx_id': clientTxId,
    'restaurant_id': restaurantId,
    'entity_type': entityType.name,
    'entity_id': entityId,
    'operation_type': operationType.name,
    'payload': payload,
    'local_version': localVersion,
    'base_server_version': baseServerVersion,
    'created_at': createdAt.toIso8601String(),
    'last_attempted_at': lastAttemptedAt?.toIso8601String(),
    'retry_count': retryCount,
    'status': status.dbValue,
    'last_error': lastError,
    'next_retry_at': nextRetryAt?.toIso8601String(),
  };

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'] as String,
      clientTxId: map['client_tx_id'] as String,
      restaurantId: map['restaurant_id'] as String,
      entityType: SyncEntityType.values.byName(map['entity_type'] as String),
      entityId: map['entity_id'] as String,
      operationType: SyncOperationType.values.byName(
        map['operation_type'] as String,
      ),
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      localVersion: (map['local_version'] as num?)?.toInt() ?? 1,
      baseServerVersion: (map['base_server_version'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastAttemptedAt: map['last_attempted_at'] != null
          ? DateTime.tryParse(map['last_attempted_at'] as String)
          : null,
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      status: SyncStatusX.fromDb(map['status'] as String?),
      lastError: map['last_error'] as String?,
      nextRetryAt: map['next_retry_at'] != null
          ? DateTime.tryParse(map['next_retry_at'] as String)
          : null,
    );
  }
}

/// A synchronization conflict recorded locally or on the server.
class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.restaurantId,
    required this.entityType,
    required this.entityId,
    this.clientTxId,
    this.clientVersion = 1,
    this.serverVersion = 1,
    required this.conflictReason,
    required this.clientPayload,
    this.serverPayload,
    this.status = 'PENDING_REVIEW',
    this.resolvedBy,
    this.resolvedAt,
    this.resolutionNotes = '',
    required this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String entityType;
  final String entityId;
  final String? clientTxId;
  final int clientVersion;
  final int serverVersion;
  final String conflictReason;
  final Map<String, dynamic> clientPayload;
  final Map<String, dynamic>? serverPayload;
  final String status;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final String resolutionNotes;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'restaurant_id': restaurantId,
    'entity_type': entityType,
    'entity_id': entityId,
    'client_tx_id': clientTxId,
    'client_version': clientVersion,
    'server_version': serverVersion,
    'conflict_reason': conflictReason,
    'client_payload': clientPayload,
    'server_payload': serverPayload,
    'status': status,
    'resolved_by': resolvedBy,
    'resolved_at': resolvedAt?.toIso8601String(),
    'resolution_notes': resolutionNotes,
    'created_at': createdAt.toIso8601String(),
  };

  factory SyncConflict.fromMap(Map<String, dynamic> map) {
    return SyncConflict(
      id: map['id'] as String,
      restaurantId: map['restaurant_id'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      clientTxId: map['client_tx_id'] as String?,
      clientVersion: (map['client_version'] as num?)?.toInt() ?? 1,
      serverVersion: (map['server_version'] as num?)?.toInt() ?? 1,
      conflictReason: map['conflict_reason'] as String,
      clientPayload: Map<String, dynamic>.from(map['client_payload'] as Map),
      serverPayload: map['server_payload'] != null
          ? Map<String, dynamic>.from(map['server_payload'] as Map)
          : null,
      status: (map['status'] as String?) ?? 'PENDING_REVIEW',
      resolvedBy: map['resolved_by'] as String?,
      resolvedAt: map['resolved_at'] != null
          ? DateTime.tryParse(map['resolved_at'] as String)
          : null,
      resolutionNotes: (map['resolution_notes'] as String?) ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

/// Aggregated state of the synchronization engine for UI presentation.
class SyncState {
  const SyncState({
    this.isOnline = true,
    this.isSyncing = false,
    this.lastSyncTime,
    this.pendingCount = 0,
    this.failedCount = 0,
    this.conflictCount = 0,
    this.lastError,
  });

  final bool isOnline;
  final bool isSyncing;
  final DateTime? lastSyncTime;
  final int pendingCount;
  final int failedCount;
  final int conflictCount;
  final String? lastError;

  bool get hasPendingItems => pendingCount > 0;
  bool get hasIssues => failedCount > 0 || conflictCount > 0;

  SyncState copyWith({
    bool? isOnline,
    bool? isSyncing,
    DateTime? lastSyncTime,
    int? pendingCount,
    int? failedCount,
    int? conflictCount,
    String? lastError,
  }) {
    return SyncState(
      isOnline: isOnline ?? this.isOnline,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      pendingCount: pendingCount ?? this.pendingCount,
      failedCount: failedCount ?? this.failedCount,
      conflictCount: conflictCount ?? this.conflictCount,
      lastError: lastError ?? this.lastError,
    );
  }
}
