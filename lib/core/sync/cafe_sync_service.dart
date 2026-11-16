import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/billing/data/supabase_payment_repository.dart';
import '../../features/billing/domain/payment_repository.dart';
import '../../features/orders/data/supabase_order_repository.dart';
import '../../features/orders/domain/cafe_order.dart';
import '../../features/orders/domain/order_repository.dart';
import '../database/database_gateway.dart';
import '../errors/app_failure.dart';
import '../services/backend.dart';
import '../services/cafe_realtime_service.dart';
import '../storage/local_database.dart';
import 'sync_models.dart';
import 'sync_queue.dart';

/// Central Cloud Synchronization Service for CafeFlow.
/// Coordinates offline persistence, durable queue execution, reachability checks,
/// conflict detection, and cache synchronization.
class CafeSyncService {
  CafeSyncService({
    required this.database,
    required this.queue,
    this.client,
    this.gateway,
    this.orderRepository,
    this.paymentRepository,
    this.realtimeService,
  }) : _currentState = SyncState(isOnline: client != null);

  final CafeLocalDatabase database;
  final SyncQueue queue;
  final SupabaseClient? client;
  final DatabaseGateway? gateway;
  final OrderRepository? orderRepository;
  final PaymentRepository? paymentRepository;
  final CafeRealtimeService? realtimeService;

  bool _isSyncRunning = false;
  final StreamController<SyncState> _stateController =
      StreamController<SyncState>.broadcast();
  SyncState _currentState;

  SyncState get currentState => _currentState;
  Stream<SyncState> get stateStream => _stateController.stream;

  void dispose() {
    _stateController.close();
  }

  void _updateState(SyncState newState) {
    _currentState = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  /// Verifies true cloud reachability by performing a lightweight query.
  Future<bool> checkCloudReachability() async {
    if (client == null) return false;
    try {
      // Lightweight read to test actual endpoint availability and latency
      await client!
          .from('restaurant_settings')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 4));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Refreshes local cache collections from the cloud source of truth.
  Future<void> refreshCache({required String restaurantId}) async {
    if (client == null || gateway == null) return;

    try {
      // 1. Refresh menu categories
      final catRows = await gateway!.readRows(
        'menu_categories',
        equals: {'restaurant_id': restaurantId, 'deleted_at': 'null'},
      );
      for (final row in catRows) {
        final id = row['id'] as String;
        await database.put('menu_categories', id, row);
      }

      // 2. Refresh menu items
      final itemRows = await gateway!.readRows(
        'menu_items',
        equals: {'restaurant_id': restaurantId, 'deleted_at': 'null'},
      );
      for (final row in itemRows) {
        final id = row['id'] as String;
        await database.put('menu_items', id, row);
      }

      // 3. Refresh dining tables
      final tableRows = await gateway!.readRows(
        'dining_tables',
        equals: {'restaurant_id': restaurantId, 'deleted_at': 'null'},
      );
      for (final row in tableRows) {
        final id = row['id'] as String;
        await database.put('dining_tables', id, row);
      }

      // 4. Refresh payment methods
      final methodRows = await gateway!.readRows(
        'payment_methods',
        equals: {'restaurant_id': restaurantId},
      );
      for (final row in methodRows) {
        final id = row['id'] as String;
        await database.put('payment_methods', id, row);
      }

      // 5. Refresh restaurant settings
      final settingsRows = await gateway!.readRows(
        'restaurant_settings',
        equals: {'restaurant_id': restaurantId},
      );
      if (settingsRows.isNotEmpty) {
        await database.put(
          'restaurant_settings',
          restaurantId,
          settingsRows.first,
        );
      }
    } catch (_) {
      // Cache refresh failure does not block local operations
    }
  }

  /// Executes a full synchronization sweep over the durable queue.
  Future<void> synchronize({required String restaurantId}) async {
    if (_isSyncRunning) return;
    _isSyncRunning = true;

    _updateState(_currentState.copyWith(isSyncing: true));

    try {
      final isReachable = await checkCloudReachability();
      if (!isReachable) {
        _updateState(
          _currentState.copyWith(
            isOnline: false,
            isSyncing: false,
            lastError: 'Cloud backend is currently unreachable.',
          ),
        );
        return;
      }

      _updateState(_currentState.copyWith(isOnline: true));

      // 1. Process pending queued operations in dependency order
      final pendingOperations = await queue.getPendingOperations(
        restaurantId: restaurantId,
      );

      for (final item in pendingOperations) {
        await _processQueueItem(item, restaurantId);
      }

      // 2. Refresh local cache with latest cloud catalog
      await refreshCache(restaurantId: restaurantId);

      // 3. Update sync state metrics
      final pendingCount = await queue.getPendingCount(
        restaurantId: restaurantId,
      );
      final failedCount = await queue.getFailedCount(
        restaurantId: restaurantId,
      );
      final conflictCount = await queue.getConflictCount(
        restaurantId: restaurantId,
      );

      _updateState(
        _currentState.copyWith(
          isOnline: true,
          isSyncing: false,
          lastSyncTime: DateTime.now(),
          pendingCount: pendingCount,
          failedCount: failedCount,
          conflictCount: conflictCount,
          lastError: null,
        ),
      );
    } catch (e) {
      _updateState(
        _currentState.copyWith(
          isSyncing: false,
          lastError: 'Synchronization encountered an error: $e',
        ),
      );
    } finally {
      _isSyncRunning = false;
    }
  }

  Future<void> _processQueueItem(
    SyncQueueItem item,
    String restaurantId,
  ) async {
    await queue.markProcessing(item.id);

    try {
      switch (item.operationType) {
        case SyncOperationType.createOrder:
          await _syncCreateOrder(item, restaurantId);
          break;

        case SyncOperationType.recordPayment:
          await _syncRecordPayment(item, restaurantId);
          break;

        case SyncOperationType.adjustStock:
          await _syncAdjustStock(item, restaurantId);
          break;

        case SyncOperationType.recordAttendance:
          await _syncRecordAttendance(item, restaurantId);
          break;

        default:
          // Unhandled operation types
          await queue.markSynced(item.id);
          break;
      }
    } on AppFailure catch (e) {
      // Check if this is a permanent conflict or validation error
      if (e.message.contains('unavailable') ||
          e.message.contains('Permission denied') ||
          e.message.contains('not found')) {
        await queue.markConflict(id: item.id, reason: e.message);
      } else {
        await queue.markRetry(item.id, e.message);
      }
    } catch (e) {
      await queue.markRetry(item.id, e.toString());
    }
  }

  Future<void> _syncCreateOrder(SyncQueueItem item, String restaurantId) async {
    final payload = item.payload;
    final itemsList = (payload['items'] as List).map((i) {
      final map = i as Map<String, dynamic>;
      return OrderSubmissionItem(
        menuItemId: map['menu_item_id'] as String,
        quantity: (map['quantity'] as num).toInt(),
      );
    }).toList();

    if (orderRepository is! SupabaseOrderRepository) {
      throw const AppFailure(
        'Order repository is unavailable for cloud synchronization.',
      );
    }

    final repo = orderRepository as SupabaseOrderRepository;
    final result = await repo.createOrder(
      restaurantId: restaurantId,
      tableName: (payload['table_name'] as String?) ?? 'Takeaway',
      items: itemsList,
      specialInstructions: (payload['special_instructions'] as String?) ?? '',
      discountMinor: (payload['discount_minor'] as num?)?.toInt() ?? 0,
      discountReason: (payload['discount_reason'] as String?) ?? '',
      idempotencyKey: payload['idempotency_key'] as String?,
    );

    // Update local order document with cloud confirmation
    final localOrder = await database.get('orders', item.entityId);
    if (localOrder != null) {
      final updated = Map<String, dynamic>.from(localOrder)
        ..['server_order_id'] = result.id
        ..['order_number'] = result.orderNumber
        ..['sync_status'] = 'SYNCED'
        ..['synced_at'] = DateTime.now().toIso8601String();
      await database.put('orders', item.entityId, updated);
    }

    // Trigger idempotent recipe deduction on server
    try {
      if (client != null) {
        await client!.rpc(
          'deduct_order_recipe_stock',
          params: {'p_restaurant_id': restaurantId, 'p_order_id': result.id},
        );
      }
    } catch (_) {}

    await queue.markSynced(
      item.id,
      serverResult: {
        'server_order_id': result.id,
        'order_number': result.orderNumber,
        'is_replay': result.isReplay,
      },
    );
  }

  Future<void> _syncAdjustStock(SyncQueueItem item, String restaurantId) async {
    if (client == null) {
      throw const AppFailure('Database client is unavailable.');
    }
    final p = item.payload;
    final res = await client!
        .rpc(
          'adjust_inventory_stock_v2',
          params: {
            'p_restaurant_id': restaurantId,
            'p_inventory_item_id': p['inventory_item_id'],
            'p_movement_type': p['movement_type'],
            'p_quantity_change': p['quantity_change'],
            'p_reason': p['reason'] ?? '',
            'p_reference': p['reference'] ?? '',
            'p_client_tx_id': item.clientTxId,
          },
        )
        .timeout(const Duration(seconds: 15));

    await queue.markSynced(
      item.id,
      serverResult: Map<String, dynamic>.from(res as Map),
    );
  }

  Future<void> _syncRecordAttendance(
    SyncQueueItem item,
    String restaurantId,
  ) async {
    if (client == null) {
      throw const AppFailure('Database client is unavailable.');
    }
    final p = item.payload;
    final action = p['action'] as String? ?? 'CLOCK_IN';
    if (action == 'CLOCK_IN') {
      final res = await client!
          .rpc(
            'staff_clock_in',
            params: {
              'p_restaurant_id': restaurantId,
              'p_target_user_id': p['user_id'],
              'p_shift_id': p['shift_id'],
              'p_notes': p['notes'] ?? '',
            },
          )
          .timeout(const Duration(seconds: 15));
      await queue.markSynced(
        item.id,
        serverResult: Map<String, dynamic>.from(res as Map),
      );
    } else {
      final res = await client!
          .rpc(
            'staff_clock_out',
            params: {
              'p_restaurant_id': restaurantId,
              'p_attendance_id': p['attendance_id'],
              'p_notes': p['notes'] ?? '',
            },
          )
          .timeout(const Duration(seconds: 15));
      await queue.markSynced(
        item.id,
        serverResult: Map<String, dynamic>.from(res as Map),
      );
    }
  }

  Future<void> _syncRecordPayment(
    SyncQueueItem item,
    String restaurantId,
  ) async {
    final payload = item.payload;
    String? targetOrderId = payload['order_id'] as String?;

    // If order was created offline, resolve its server order ID from the local order record
    final localOrderId = payload['local_order_id'] as String?;
    if (localOrderId != null) {
      final localOrder = await database.get('orders', localOrderId);
      if (localOrder != null && localOrder['server_order_id'] != null) {
        targetOrderId = localOrder['server_order_id'] as String;
      }
    }

    if (targetOrderId == null || targetOrderId.isEmpty) {
      throw const AppFailure(
        'Cannot synchronize payment: Target order has not yet synced.',
      );
    }

    if (paymentRepository is! SupabasePaymentRepository) {
      throw const AppFailure(
        'Payment repository is unavailable for cloud synchronization.',
      );
    }

    final repo = paymentRepository as SupabasePaymentRepository;
    final result = await repo.recordPayment(
      restaurantId: restaurantId,
      orderId: targetOrderId,
      paymentMethodCode: payload['payment_method_code'] as String,
      amountMinor: (payload['amount_minor'] as num).toInt(),
      tenderedAmountMinor: (payload['tendered_amount_minor'] as num?)?.toInt(),
      transactionReference: payload['transaction_reference'] as String?,
      notes: (payload['notes'] as String?) ?? '',
      idempotencyKey: payload['idempotency_key'] as String?,
    );

    // Update local payment record
    final localPayment = await database.get('payments', item.entityId);
    if (localPayment != null) {
      final updated = Map<String, dynamic>.from(localPayment)
        ..['server_payment_id'] = result.paymentId
        ..['sync_status'] = 'SYNCED'
        ..['synced_at'] = DateTime.now().toIso8601String();
      await database.put('payments', item.entityId, updated);
    }

    await queue.markSynced(
      item.id,
      serverResult: {
        'payment_id': result.paymentId,
        'financial_status': result.financialStatus.dbValue,
        'is_replay': result.isReplay,
      },
    );
  }

  /// Enqueues an offline order creation into local storage and queue.
  Future<String> saveOfflineOrder({
    required String restaurantId,
    required String tableName,
    required List<OrderLine> lines,
    String? tableSessionId,
    String orderType = 'TAKEAWAY',
    int discountMinor = 0,
    String discountReason = '',
    String specialInstructions = '',
    int taxMinor = 0,
    int serviceChargeMinor = 0,
    String taxName = 'GST',
    int taxRateBps = 500,
    bool taxIsInclusive = false,
  }) async {
    final clientTxId = 'ctx_ord_${DateTime.now().millisecondsSinceEpoch}';
    final localOrderId = 'local_ord_${DateTime.now().millisecondsSinceEpoch}';
    final tempOrderNumber =
        'OFFLINE-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

    final subtotalMinor = lines.fold<int>(0, (sum, l) => sum + l.totalMinor);
    final totalMinor =
        (subtotalMinor - discountMinor + taxMinor + serviceChargeMinor).clamp(
          0,
          999999999,
        );

    // 1. Save local order document
    final orderMap = {
      'id': localOrderId,
      'client_tx_id': clientTxId,
      'restaurant_id': restaurantId,
      'order_number': tempOrderNumber,
      'table_name': tableName,
      'table_session_id': tableSessionId,
      'order_type': orderType,
      'special_instructions': specialInstructions,
      'subtotal_minor': subtotalMinor,
      'discount_minor': discountMinor,
      'discount_reason': discountReason,
      'tax_name': taxName,
      'tax_rate_basis_points': taxRateBps,
      'tax_is_inclusive': taxIsInclusive,
      'tax_minor': taxMinor,
      'service_charge_minor': serviceChargeMinor,
      'total_minor': totalMinor,
      'status': 'NEW',
      'financial_status': 'UNPAID',
      'paid_amount_minor': 0,
      'refunded_amount_minor': 0,
      'sync_status': 'PENDING',
      'created_at': DateTime.now().toIso8601String(),
      'lines': lines
          .map(
            (l) => {
              'product_id': l.productId,
              'name': l.name,
              'quantity': l.quantity,
              'unit_minor': l.unitMinor,
              'total_minor': l.totalMinor,
            },
          )
          .toList(),
    };

    await database.put('orders', localOrderId, orderMap);

    // Save individual line item records in order_items collection
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final itemId = 'local_oi_${localOrderId}_$i';
      await database.put('order_items', itemId, {
        'id': itemId,
        'order_id': localOrderId,
        'restaurant_id': restaurantId,
        'menu_item_id': line.productId,
        'item_name': line.name,
        'unit_price_minor': line.unitMinor,
        'quantity': line.quantity,
        'subtotal_minor': line.totalMinor,
      });
    }

    // Generate local KOT ticket for kitchen fulfillment
    final localKotId = 'local_kot_${DateTime.now().microsecondsSinceEpoch}';
    final tempKotNumber =
        'KOT-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

    await database.put('kitchen_order_tickets', localKotId, {
      'id': localKotId,
      'restaurant_id': restaurantId,
      'order_id': localOrderId,
      'table_session_id': tableSessionId,
      'kot_number': tempKotNumber,
      'sequence_number': 1,
      'table_name': tableName,
      'status': 'NEW',
      'special_instructions': specialInstructions,
      'created_at': DateTime.now().toIso8601String(),
    });

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final kotItemId = 'local_koti_${localKotId}_$i';
      await database.put('kot_items', kotItemId, {
        'id': kotItemId,
        'kot_id': localKotId,
        'order_item_id': 'local_oi_${localOrderId}_$i',
        'item_name': line.name,
        'quantity': line.quantity,
        'status': 'NEW',
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    // 2. Enqueue sync operation
    final queueItem = SyncQueueItem(
      id: 'sq_ord_${DateTime.now().microsecondsSinceEpoch}',
      clientTxId: clientTxId,
      restaurantId: restaurantId,
      entityType: SyncEntityType.order,
      entityId: localOrderId,
      operationType: SyncOperationType.createOrder,
      payload: {
        'restaurant_id': restaurantId,
        'table_name': tableName,
        'table_session_id': tableSessionId,
        'order_type': orderType,
        'special_instructions': specialInstructions,
        'discount_minor': discountMinor,
        'discount_reason': discountReason,
        'idempotency_key': clientTxId,
        'items': lines
            .map((l) => {'menu_item_id': l.productId, 'quantity': l.quantity})
            .toList(),
      },
      createdAt: DateTime.now(),
      status: SyncStatus.pending,
    );

    await queue.enqueue(queueItem);

    // Update pending count
    final count = await queue.getPendingCount(restaurantId: restaurantId);
    _updateState(_currentState.copyWith(pendingCount: count));

    return localOrderId;
  }

  /// Enqueues an offline payment settlement into local storage and queue.
  Future<String> recordOfflinePayment({
    required String restaurantId,
    required String localOrderId,
    required String paymentMethodCode,
    required int amountMinor,
    int? tenderedAmountMinor,
    String? transactionReference,
    String notes = '',
  }) async {
    final clientTxId = 'ctx_pay_${DateTime.now().millisecondsSinceEpoch}';
    final localPaymentId = 'local_pay_${DateTime.now().millisecondsSinceEpoch}';

    final isCash = paymentMethodCode.toUpperCase() == 'CASH';
    final changeDue =
        isCash &&
            tenderedAmountMinor != null &&
            tenderedAmountMinor > amountMinor
        ? tenderedAmountMinor - amountMinor
        : 0;

    // 1. Save local payment document
    final paymentMap = {
      'id': localPaymentId,
      'client_tx_id': clientTxId,
      'restaurant_id': restaurantId,
      'local_order_id': localOrderId,
      'payment_method_code': paymentMethodCode.toUpperCase(),
      'amount_minor': amountMinor,
      'tendered_amount_minor': tenderedAmountMinor,
      'change_due_minor': changeDue,
      'transaction_reference': transactionReference,
      'notes': notes,
      'status': isCash ? 'PENDING_SYNC' : 'PENDING_RECONCILIATION',
      'sync_status': 'PENDING',
      'created_at': DateTime.now().toIso8601String(),
    };

    await database.put('payments', localPaymentId, paymentMap);

    // 2. Update local order financial status
    final localOrder = await database.get('orders', localOrderId);
    if (localOrder != null) {
      final updatedOrder = Map<String, dynamic>.from(localOrder)
        ..['financial_status'] = 'PAID'
        ..['paid_amount_minor'] = amountMinor;
      await database.put('orders', localOrderId, updatedOrder);
    }

    // 3. Enqueue sync operation
    final queueItem = SyncQueueItem(
      id: 'sq_pay_${DateTime.now().microsecondsSinceEpoch}',
      clientTxId: clientTxId,
      restaurantId: restaurantId,
      entityType: SyncEntityType.payment,
      entityId: localPaymentId,
      operationType: SyncOperationType.recordPayment,
      payload: {
        'restaurant_id': restaurantId,
        'local_order_id': localOrderId,
        'payment_method_code': paymentMethodCode.toUpperCase(),
        'amount_minor': amountMinor,
        'tendered_amount_minor': tenderedAmountMinor,
        'transaction_reference': transactionReference,
        'notes': notes,
        'idempotency_key': clientTxId,
      },
      createdAt: DateTime.now(),
      status: SyncStatus.pending,
    );

    await queue.enqueue(queueItem);

    // Update pending count
    final count = await queue.getPendingCount(restaurantId: restaurantId);
    _updateState(_currentState.copyWith(pendingCount: count));

    return localPaymentId;
  }

  /// Enqueues an offline stock adjustment into local storage and queue.
  Future<String> queueOfflineStockAdjustment({
    required String restaurantId,
    required String inventoryItemId,
    required String movementType,
    required double quantityChange,
    String reason = '',
    String reference = '',
  }) async {
    final clientTxId = 'ctx_stk_${DateTime.now().millisecondsSinceEpoch}';
    final localMovementId =
        'local_mov_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Update local inventory item stock
    final localItem = await database.get('inventory_items', inventoryItemId);
    double prevStock = 0.0;
    if (localItem != null) {
      prevStock = (localItem['current_stock'] as num?)?.toDouble() ?? 0.0;
      final newStock = (prevStock + quantityChange).clamp(0.0, double.infinity);
      final updatedItem = Map<String, dynamic>.from(localItem)
        ..['current_stock'] = newStock
        ..['sync_status'] = 'PENDING';
      await database.put('inventory_items', inventoryItemId, updatedItem);
    }

    // 2. Insert local stock movement
    final movementMap = {
      'id': localMovementId,
      'restaurant_id': restaurantId,
      'inventory_item_id': inventoryItemId,
      'movement_type': movementType.toUpperCase(),
      'quantity_change': quantityChange,
      'previous_stock': prevStock,
      'new_stock': (prevStock + quantityChange).clamp(0.0, double.infinity),
      'reason': reason,
      'reference': reference,
      'client_tx_id': clientTxId,
      'sync_status': 'PENDING',
      'created_at': DateTime.now().toIso8601String(),
    };
    await database.put('stock_movements', localMovementId, movementMap);

    // 3. Enqueue sync item
    final queueItem = SyncQueueItem(
      id: 'sq_stk_${DateTime.now().microsecondsSinceEpoch}',
      clientTxId: clientTxId,
      restaurantId: restaurantId,
      entityType: SyncEntityType.inventory,
      entityId: localMovementId,
      operationType: SyncOperationType.adjustStock,
      payload: {
        'inventory_item_id': inventoryItemId,
        'movement_type': movementType.toUpperCase(),
        'quantity_change': quantityChange,
        'reason': reason,
        'reference': reference,
      },
      createdAt: DateTime.now(),
      status: SyncStatus.pending,
    );
    await queue.enqueue(queueItem);

    final count = await queue.getPendingCount(restaurantId: restaurantId);
    _updateState(_currentState.copyWith(pendingCount: count));
    return localMovementId;
  }

  /// Enqueues an offline attendance clock-in or clock-out into local storage and queue.
  Future<String> queueOfflineAttendance({
    required String restaurantId,
    required String userId,
    required String action,
    String? attendanceId,
    String? shiftId,
    String notes = '',
  }) async {
    final clientTxId = 'ctx_att_${DateTime.now().millisecondsSinceEpoch}';
    final recordId =
        attendanceId ?? 'local_att_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Record local attendance
    final attMap = {
      'id': recordId,
      'restaurant_id': restaurantId,
      'user_id': userId,
      'shift_id': shiftId,
      'status': action == 'CLOCK_IN' ? 'CLOCKED_IN' : 'CLOCKED_OUT',
      'clock_in': DateTime.now().toIso8601String(),
      if (action == 'CLOCK_OUT') 'clock_out': DateTime.now().toIso8601String(),
      'notes': notes,
      'sync_status': 'PENDING',
      'created_at': DateTime.now().toIso8601String(),
    };
    await database.put('staff_attendance', recordId, attMap);

    // 2. Enqueue sync item
    final queueItem = SyncQueueItem(
      id: 'sq_att_${DateTime.now().microsecondsSinceEpoch}',
      clientTxId: clientTxId,
      restaurantId: restaurantId,
      entityType: SyncEntityType.staff,
      entityId: recordId,
      operationType: SyncOperationType.recordAttendance,
      payload: {
        'action': action,
        'user_id': userId,
        'shift_id': shiftId,
        'attendance_id': recordId,
        'notes': notes,
      },
      createdAt: DateTime.now(),
      status: SyncStatus.pending,
    );
    await queue.enqueue(queueItem);

    final count = await queue.getPendingCount(restaurantId: restaurantId);
    _updateState(_currentState.copyWith(pendingCount: count));
    return recordId;
  }
}

/// Global Riverpod providers for synchronization.
final syncQueueProvider = Provider<SyncQueue>((ref) {
  final db = ref.watch(localDatabaseProvider);
  return SyncQueue(db);
});

final syncServiceProvider = Provider<CafeSyncService>((ref) {
  final db = ref.watch(localDatabaseProvider);
  final queue = ref.watch(syncQueueProvider);
  final backend = ref.watch(backendProvider);
  final isLive = backend.status == BackendStatus.initialized;

  final SupabaseClient? client = isLive ? backend.client : null;
  final DatabaseGateway? gateway = isLive
      ? ref.watch(databaseGatewayProvider)
      : null;
  final OrderRepository? orderRepo = isLive
      ? ref.watch(orderRepositoryProvider)
      : null;
  final PaymentRepository? paymentRepo = isLive
      ? ref.watch(paymentRepositoryProvider)
      : null;
  final CafeRealtimeService? realtime = isLive
      ? ref.watch(cafeRealtimeServiceProvider)
      : null;

  final service = CafeSyncService(
    database: db,
    queue: queue,
    client: client,
    gateway: gateway,
    orderRepository: orderRepo,
    paymentRepository: paymentRepo,
    realtimeService: realtime,
  );

  ref.onDispose(service.dispose);
  return service;
});

final syncStateProvider = StreamProvider<SyncState>((ref) {
  final service = ref.watch(syncServiceProvider);
  return service.stateStream;
});
