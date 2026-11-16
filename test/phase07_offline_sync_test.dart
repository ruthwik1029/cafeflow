import 'package:cafeflow/core/storage/local_database.dart';
import 'package:cafeflow/core/sync/cafe_sync_service.dart';
import 'package:cafeflow/core/sync/sync_models.dart';
import 'package:cafeflow/core/sync/sync_queue.dart';
import 'package:cafeflow/core/widgets/sync_status_badge.dart';
import 'package:cafeflow/features/orders/domain/cafe_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 07: CafeLocalDatabase & Storage Engine Tests', () {
    late MemoryStorageAdapter adapter;
    late CafeLocalDatabase db;

    setUp(() async {
      adapter = MemoryStorageAdapter();
      db = CafeLocalDatabase(adapter: adapter);
      await db.initialize();
    });

    test('Initializes with current schema version', () async {
      expect(CafeLocalDatabase.currentSchemaVersion, 1);
      final storedVersion = await adapter.read(
        '${CafeLocalDatabase.keyPrefix}meta_schema_version',
      );
      expect(storedVersion, '1');
    });

    test(
      'CRUD operations on collections persist and retrieve correctly',
      () async {
        final orderData = {
          'id': 'ord-local-101',
          'restaurant_id': 'rest-001',
          'table_name': 'Table 4',
          'subtotal_minor': 45000,
          'tax_minor': 2250,
          'discount_minor': 0,
          'total_minor': 47250,
          'status': 'NEW_ORDER',
          'sync_status': 'PENDING',
          'client_tx_id': 'tx-ord-101',
        };

        await db.put('orders', 'ord-local-101', orderData);

        final retrieved = await db.get('orders', 'ord-local-101');
        expect(retrieved, isNotNull);
        expect(retrieved!['id'], 'ord-local-101');
        expect(retrieved['table_name'], 'Table 4');
        expect(retrieved['total_minor'], 47250);

        // Update document
        await db.put('orders', 'ord-local-101', {
          ...orderData,
          'status': 'PREPARING',
        });
        final updated = await db.get('orders', 'ord-local-101');
        expect(updated!['status'], 'PREPARING');
        expect(updated['total_minor'], 47250);

        // Query by predicate
        final filtered = await db.query(
          'orders',
          where: {'restaurant_id': 'rest-001'},
        );
        expect(filtered.length, 1);

        // Delete document
        await db.delete('orders', 'ord-local-101');
        final afterDelete = await db.get('orders', 'ord-local-101');
        expect(afterDelete, isNull);
      },
    );

    test('LocalTransaction commits all staged operations atomically', () async {
      await db.runTransaction((tx) async {
        tx.insert('orders', 'tx-ord-1', {
          'id': 'tx-ord-1',
          'restaurant_id': 'rest-1',
        });
        tx.insert('order_items', 'tx-item-1', {
          'id': 'tx-item-1',
          'order_id': 'tx-ord-1',
        });
        tx.insert('payments', 'tx-pay-1', {
          'id': 'tx-pay-1',
          'amount_minor': 5000,
        });
      });

      expect(await db.get('orders', 'tx-ord-1'), isNotNull);
      expect(await db.get('order_items', 'tx-item-1'), isNotNull);
      expect(await db.get('payments', 'tx-pay-1'), isNotNull);
    });

    test(
      'LocalTransaction rollback discards all staged operations on error',
      () async {
        try {
          await db.runTransaction((tx) async {
            tx.insert('orders', 'rollback-ord-1', {'id': 'rollback-ord-1'});
            throw Exception('Intentional failure to trigger rollback');
          });
        } catch (_) {}

        expect(await db.get('orders', 'rollback-ord-1'), isNull);
      },
    );

    test('Multi-tenant isolation: clearTenantCache purges only matching restaurant records', () async {
      await db.put('orders', 'ord-rest-A-1', {
        'id': 'ord-rest-A-1',
        'restaurant_id': 'rest-A',
      });
      await db.put('orders', 'ord-rest-A-2', {
        'id': 'ord-rest-A-2',
        'restaurant_id': 'rest-A',
      });
      await db.put('orders', 'ord-rest-B-1', {
        'id': 'ord-rest-B-1',
        'restaurant_id': 'rest-B',
      });

      await db.clearTenantCache('rest-A');

      expect(await db.get('orders', 'ord-rest-A-1'), isNull);
      expect(await db.get('orders', 'ord-rest-A-2'), isNull);
      expect(await db.get('orders', 'ord-rest-B-1'), isNotNull);
    });
  });

  group('Phase 07: Durable SyncQueue & Dependency Ordering Tests', () {
    late MemoryStorageAdapter adapter;
    late CafeLocalDatabase db;
    late SyncQueue queue;

    setUp(() async {
      adapter = MemoryStorageAdapter();
      db = CafeLocalDatabase(adapter: adapter);
      await db.initialize();
      queue = SyncQueue(db);
    });

    test('Enqueues operations and enforces dependency ordering (orders before payments)', () async {
      // Enqueue payment first chronologically
      await queue.enqueue(
        SyncQueueItem(
          id: 'q-pay-001',
          clientTxId: 'tx-pay-001',
          restaurantId: 'rest-001',
          entityType: SyncEntityType.payment,
          entityId: 'pay-001',
          operationType: SyncOperationType.recordPayment,
          payload: {
            'order_client_tx_id': 'tx-ord-001',
            'amount_minor': 12000,
            'payment_method_code': 'CASH',
          },
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      );

      // Enqueue parent order second chronologically
      await queue.enqueue(
        SyncQueueItem(
          id: 'q-ord-001',
          clientTxId: 'tx-ord-001',
          restaurantId: 'rest-001',
          entityType: SyncEntityType.order,
          entityId: 'ord-001',
          operationType: SyncOperationType.createOrder,
          payload: {'table_name': 'Table 1', 'total_minor': 12000},
          createdAt: DateTime.now(),
        ),
      );

      final pending = await queue.getPendingOperations(
        restaurantId: 'rest-001',
      );
      expect(pending.length, 2);

      // Order MUST be sorted before payment regardless of insertion order
      expect(pending[0].entityType, SyncEntityType.order);
      expect(pending[0].clientTxId, 'tx-ord-001');

      expect(pending[1].entityType, SyncEntityType.payment);
      expect(pending[1].clientTxId, 'tx-pay-001');
    });

    test(
      'Exponential backoff increments and schedules next retry timestamp',
      () async {
        final item = SyncQueueItem(
          id: 'q-retry-001',
          clientTxId: 'tx-retry-001',
          restaurantId: 'rest-001',
          entityType: SyncEntityType.order,
          entityId: 'ord-retry-001',
          operationType: SyncOperationType.createOrder,
          payload: {'test': true},
          createdAt: DateTime.now(),
        );

        await queue.enqueue(item);
        expect(item.retryCount, 0);

        // Fail attempt 1
        await queue.markRetry(item.id, 'Connection timeout');
        var raw = await db.get('sync_queue', item.id);
        expect(raw, isNotNull);
        var updated = SyncQueueItem.fromMap(raw!);
        expect(updated.retryCount, 1);
        expect(updated.lastError, 'Connection timeout');
        expect(updated.nextRetryAt, isNotNull);

        // Fail attempt 2
        await queue.markRetry(item.id, '503 Service Unavailable');
        raw = await db.get('sync_queue', item.id);
        updated = SyncQueueItem.fromMap(raw!);
        expect(updated.retryCount, 2);
      },
    );

    test(
      'Item transitions to SyncStatus.failed when exceeding max retries',
      () async {
        final item = SyncQueueItem(
          id: 'q-fail-threshold',
          clientTxId: 'tx-fail-threshold',
          restaurantId: 'rest-001',
          entityType: SyncEntityType.order,
          entityId: 'ord-fail',
          operationType: SyncOperationType.createOrder,
          payload: {},
          createdAt: DateTime.now(),
        );

        await queue.enqueue(item);

        // Simulate 5 failures (default max retries is 5)
        for (int i = 0; i < 5; i++) {
          await queue.markRetry(item.id, 'Network error #$i');
        }

        final failedCount = await queue.getFailedCount(
          restaurantId: 'rest-001',
        );
        expect(failedCount, 1);

        // Item should no longer appear in getPendingOperations
        final pending = await queue.getPendingOperations(
          restaurantId: 'rest-001',
        );
        expect(pending.any((i) => i.id == item.id), isFalse);

        // retryAllFailed resets it back to pending
        await queue.retryAllFailed(restaurantId: 'rest-001');
        final afterResetFailed = await queue.getFailedCount(
          restaurantId: 'rest-001',
        );
        expect(afterResetFailed, 0);

        final afterResetPending = await queue.getPendingOperations(
          restaurantId: 'rest-001',
        );
        expect(afterResetPending.any((i) => i.id == item.id), isTrue);
      },
    );

    test('markSynced records server acknowledgement correctly', () async {
      final item = SyncQueueItem(
        id: 'q-ack-test',
        clientTxId: 'tx-ack-test',
        restaurantId: 'rest-001',
        entityType: SyncEntityType.order,
        entityId: 'ord-ack-test',
        operationType: SyncOperationType.createOrder,
        payload: {},
        createdAt: DateTime.now(),
      );

      await queue.enqueue(item);

      await queue.markSynced(
        item.id,
        serverResult: {'server_order_id': 'srv-ord-999'},
      );

      final pending = await queue.getPendingOperations(
        restaurantId: 'rest-001',
      );
      expect(pending.any((i) => i.id == item.id), isFalse);

      final rawItem = await db.get('sync_queue', item.id);
      expect(rawItem, isNotNull);
      expect(rawItem!['status'], 'SYNCED');
      expect(rawItem['server_result']?['server_order_id'], 'srv-ord-999');
    });

    test('Conflict handling records conflict details in sync_conflicts and updates queue status', () async {
      final item = SyncQueueItem(
        id: 'q-conflict-01',
        clientTxId: 'tx-conflict-01',
        restaurantId: 'rest-001',
        entityType: SyncEntityType.order,
        entityId: 'ord-conf-01',
        operationType: SyncOperationType.createOrder,
        payload: {'item_id': 'it-1', 'quantity': 2},
        createdAt: DateTime.now(),
      );

      await queue.enqueue(item);

      await queue.markConflict(
        id: item.id,
        reason: 'Menu item "Double Espresso" is currently out of stock.',
        serverPayload: {'item_id': 'it-1', 'available': false},
      );

      final conflictCount = await queue.getConflictCount(
        restaurantId: 'rest-001',
      );
      expect(conflictCount, 1);

      final conflicts = await db.query(
        'sync_conflicts',
        where: {'restaurant_id': 'rest-001'},
      );
      expect(conflicts.length, 1);
      expect(conflicts.first['conflict_reason'], contains('Double Espresso'));
      expect(conflicts.first['server_payload']?['available'], isFalse);
    });
  });

  group('Phase 07: CafeSyncService Offline Order & Payment Safety Tests', () {
    late MemoryStorageAdapter adapter;
    late CafeLocalDatabase db;
    late SyncQueue queue;
    late CafeSyncService syncService;

    setUp(() async {
      adapter = MemoryStorageAdapter();
      db = CafeLocalDatabase(adapter: adapter);
      await db.initialize();
      queue = SyncQueue(db);
      syncService = CafeSyncService(
        database: db,
        queue: queue,
        client: null, // Hermetic offline testing
        gateway: null,
      );
    });

    tearDown(() {
      syncService.dispose();
    });

    test('saveOfflineOrder creates local pending order and enqueues sync operation', () async {
      final lines = [
        const OrderLine(
          productId: 'prod-latte',
          name: 'Caffe Latte',
          unitMinor: 22000,
          quantity: 2,
        ),
      ];

      final localOrderId = await syncService.saveOfflineOrder(
        restaurantId: 'rest-offline-1',
        tableName: 'Table 7',
        lines: lines,
        discountMinor: 4000,
        discountReason: 'Loyalty discount',
        specialInstructions: 'Oat milk please',
        taxMinor: 2000,
        serviceChargeMinor: 0,
        taxName: 'GST',
        taxRateBps: 500,
        taxIsInclusive: false,
      );

      expect(localOrderId, isNotEmpty);

      // Verify order saved in local database
      final savedOrder = await db.get('orders', localOrderId);
      expect(savedOrder, isNotNull);
      expect(savedOrder!['sync_status'], 'PENDING');
      expect(savedOrder['table_name'], 'Table 7');
      expect(savedOrder['subtotal_minor'], 44000);
      expect(savedOrder['discount_minor'], 4000);
      expect(savedOrder['tax_minor'], 2000);
      expect(savedOrder['total_minor'], 42000);
      expect(savedOrder['client_tx_id'], isNotEmpty);

      // Verify order items saved in local database
      final items = await db.query(
        'order_items',
        where: {'order_id': localOrderId},
      );
      expect(items.length, 1);
      expect(items.first['item_name'], 'Caffe Latte');
      expect(items.first['unit_price_minor'], 22000);
      expect(items.first['quantity'], 2);

      // Verify item enqueued in sync queue
      final pendingOps = await queue.getPendingOperations(
        restaurantId: 'rest-offline-1',
      );
      expect(pendingOps.length, 1);
      expect(pendingOps.first.entityType, SyncEntityType.order);
      expect(pendingOps.first.operationType, SyncOperationType.createOrder);
      expect(pendingOps.first.clientTxId, savedOrder['client_tx_id']);
    });

    test('recordOfflinePayment: Cash payment calculates change and updates local order', () async {
      final lines = [
        const OrderLine(
          productId: 'prod-coldbrew',
          name: 'Cold Brew',
          unitMinor: 18000,
          quantity: 1,
        ),
      ];

      final localOrderId = await syncService.saveOfflineOrder(
        restaurantId: 'rest-offline-1',
        tableName: 'Bar Counter',
        lines: lines,
        discountMinor: 0,
        taxMinor: 900,
        serviceChargeMinor: 0,
      );

      // Record offline cash payment (Bill: 18900, Tendered: 20000 -> Change: 1100)
      final paymentId = await syncService.recordOfflinePayment(
        restaurantId: 'rest-offline-1',
        localOrderId: localOrderId,
        paymentMethodCode: 'CASH',
        amountMinor: 18900,
        tenderedAmountMinor: 20000,
        notes: 'Counter Cash Tender',
      );

      expect(paymentId, isNotEmpty);

      // Verify payment saved in local database
      final savedPayment = await db.get('payments', paymentId);
      expect(savedPayment, isNotNull);
      expect(savedPayment!['payment_method_code'], 'CASH');
      expect(savedPayment['amount_minor'], 18900);
      expect(savedPayment['tendered_amount_minor'], 20000);
      expect(savedPayment['change_due_minor'], 1100);
      expect(savedPayment['status'], 'PENDING_SYNC');
      expect(savedPayment['sync_status'], 'PENDING');

      // Verify order status updated locally to PAID
      final orderAfterPay = await db.get('orders', localOrderId);
      expect(orderAfterPay!['financial_status'], 'PAID');
      expect(orderAfterPay['paid_amount_minor'], 18900);

      // Verify both order and payment are queued in proper order
      final pendingOps = await queue.getPendingOperations(
        restaurantId: 'rest-offline-1',
      );
      expect(pendingOps.length, 2);
      expect(pendingOps[0].entityType, SyncEntityType.order);
      expect(pendingOps[1].entityType, SyncEntityType.payment);
    });

    test('recordOfflinePayment: Digital payment is marked PENDING_RECONCILIATION and warned', () async {
      final lines = [
        const OrderLine(
          productId: 'prod-matcha',
          name: 'Matcha Latte',
          unitMinor: 24000,
          quantity: 1,
        ),
      ];

      final localOrderId = await syncService.saveOfflineOrder(
        restaurantId: 'rest-offline-1',
        tableName: 'Takeaway',
        lines: lines,
        discountMinor: 0,
        taxMinor: 1200,
        serviceChargeMinor: 0,
      );

      // Record offline UPI payment
      final paymentId = await syncService.recordOfflinePayment(
        restaurantId: 'rest-offline-1',
        localOrderId: localOrderId,
        paymentMethodCode: 'UPI',
        amountMinor: 25200,
        transactionReference: 'UPI-REF-OFFLINE-9921',
      );

      // Offline digital payments must NOT claim completed verification
      final savedPayment = await db.get('payments', paymentId);
      expect(savedPayment!['status'], 'PENDING_RECONCILIATION');
      expect(savedPayment['transaction_reference'], 'UPI-REF-OFFLINE-9921');
    });

    test(
      'checkCloudReachability returns false when unconfigured or offline',
      () async {
        final isReachable = await syncService.checkCloudReachability();
        expect(isReachable, isFalse);
      },
    );

    test(
      'SyncState stream emits accurate pending and status metrics',
      () async {
        expect(syncService.currentState.isOnline, isFalse);
        expect(syncService.currentState.pendingCount, 0);

        final lines = [
          const OrderLine(
            productId: 'p-1',
            name: 'Espresso',
            unitMinor: 10000,
            quantity: 1,
          ),
        ];

        await syncService.saveOfflineOrder(
          restaurantId: 'rest-1',
          tableName: 'T1',
          lines: lines,
          discountMinor: 0,
          taxMinor: 500,
          serviceChargeMinor: 0,
        );

        expect(syncService.currentState.pendingCount, 1);
      },
    );
  });

  group('Phase 07: SyncStatusBadge & SyncManagementDialog Widget Tests', () {
    late MemoryStorageAdapter adapter;
    late CafeLocalDatabase db;
    late SyncQueue queue;
    late CafeSyncService syncService;

    setUp(() async {
      adapter = MemoryStorageAdapter();
      db = CafeLocalDatabase(adapter: adapter);
      await db.initialize();
      queue = SyncQueue(db);
      syncService = CafeSyncService(
        database: db,
        queue: queue,
        client: null,
        gateway: null,
      );
    });

    tearDown(() {
      syncService.dispose();
    });

    testWidgets(
      'SyncStatusBadge displays Offline Mode when unconfigured/offline',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseProvider.overrideWithValue(db),
              syncQueueProvider.overrideWithValue(queue),
              syncServiceProvider.overrideWithValue(syncService),
            ],
            child: const MaterialApp(
              home: Scaffold(body: Center(child: SyncStatusBadge())),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.byType(SyncStatusBadge), findsOneWidget);
        expect(find.text('Offline Mode'), findsOneWidget);
        expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      },
    );

    testWidgets(
      'SyncStatusBadge displays pending count when orders are queued offline',
      (tester) async {
        await queue.enqueue(
          SyncQueueItem(
            id: 'q-test-badge-1',
            clientTxId: 'tx-test-badge-1',
            restaurantId: 'default',
            entityType: SyncEntityType.order,
            entityId: 'ord-badge-1',
            operationType: SyncOperationType.createOrder,
            payload: {},
            createdAt: DateTime.now(),
          ),
        );

        // Trigger sync service state refresh
        await syncService.saveOfflineOrder(
          restaurantId: 'default',
          tableName: 'T1',
          lines: const [
            OrderLine(
              productId: 'p1',
              name: 'Coffee',
              unitMinor: 5000,
              quantity: 1,
            ),
          ],
          discountMinor: 0,
          taxMinor: 0,
          serviceChargeMinor: 0,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseProvider.overrideWithValue(db),
              syncQueueProvider.overrideWithValue(queue),
              syncServiceProvider.overrideWithValue(syncService),
            ],
            child: const MaterialApp(
              home: Scaffold(body: Center(child: SyncStatusBadge())),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Offline (2 pending)'), findsOneWidget);
      },
    );

    testWidgets('Tapping SyncStatusBadge opens SyncManagementDialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localDatabaseProvider.overrideWithValue(db),
            syncQueueProvider.overrideWithValue(queue),
            syncServiceProvider.overrideWithValue(syncService),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Center(child: SyncStatusBadge())),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the badge
      await tester.tap(find.byType(SyncStatusBadge));
      await tester.pumpAndSettle();

      // Verify dialog is presented
      expect(find.byType(SyncManagementDialog), findsOneWidget);
      expect(find.text('Synchronization & Offline Center'), findsOneWidget);
      expect(find.text('Sync Now'), findsOneWidget);
      expect(find.text('Refresh Cache'), findsOneWidget);
    });
  });
}
