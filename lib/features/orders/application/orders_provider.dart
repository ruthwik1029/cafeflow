import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backend.dart';
import '../../../core/storage/local_database.dart';
import '../../../core/sync/sync_models.dart';
import '../../auth/application/auth_controller.dart';
import '../../demo/application/demo_orders_controller.dart';
import '../data/supabase_order_repository.dart';
import '../domain/cafe_order.dart';

final ordersProvider = FutureProvider<List<CafeOrder>>((ref) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(orderRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final localDb = ref.watch(localDatabaseProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (restaurantId != null) {
    List<CafeOrder> cloudOrders = [];
    bool cloudFetched = false;

    if (backend.status == BackendStatus.initialized &&
        repo is SupabaseOrderRepository) {
      try {
        final sub = repo.watchInvalidations(restaurantId: restaurantId).listen((
          _,
        ) {
          ref.invalidateSelf();
        });
        ref.onDispose(sub.cancel);

        cloudOrders = await repo.fetchOrders(restaurantId: restaurantId);
        cloudFetched = true;
      } catch (_) {}
    }

    // Read local offline/pending orders from local database
    final localRows = await localDb.query(
      'orders',
      where: {'restaurant_id': restaurantId},
    );
    final List<CafeOrder> localPendingOrders = [];

    for (final row in localRows) {
      final syncStatus = SyncStatusX.fromDb(row['sync_status'] as String?);
      final serverOrderId = row['server_order_id'] as String?;
      final clientTxId = row['client_tx_id'] as String?;
      final alreadyInCloud = cloudOrders.any(
        (co) =>
            co.id == serverOrderId ||
            (clientTxId != null && co.clientTxId == clientTxId),
      );

      if (!alreadyInCloud && syncStatus != SyncStatus.synced) {
        final rawLines = (row['lines'] as List?) ?? [];
        final lines = rawLines.map((l) {
          final m = l as Map<String, dynamic>;
          return OrderLine(
            productId: (m['product_id'] as String?) ?? '',
            name: (m['name'] as String?) ?? '',
            quantity: (m['quantity'] as num?)?.toInt() ?? 1,
            unitMinor: (m['unit_minor'] as num?)?.toInt() ?? 0,
          );
        }).toList();

        localPendingOrders.add(
          CafeOrder(
            id: row['id'] as String,
            number: row['order_number'] as String? ?? 'LOCAL',
            createdAt:
                DateTime.tryParse(row['created_at'] as String? ?? '') ??
                DateTime.now(),
            lines: lines,
            status: OrderStatus.newOrder,
            financialStatus: OrderFinancialStatusX.fromDb(
              row['financial_status'] as String?,
            ),
            table: row['table_name'] as String? ?? 'Takeaway',
            instructions: row['special_instructions'] as String? ?? '',
            taxMinor: (row['tax_minor'] as num?)?.toInt() ?? 0,
            discountMinor: (row['discount_minor'] as num?)?.toInt() ?? 0,
            serviceChargeMinor:
                (row['service_charge_minor'] as num?)?.toInt() ?? 0,
            paidMinor: (row['paid_amount_minor'] as num?)?.toInt() ?? 0,
            taxName: row['tax_name'] as String? ?? 'GST',
            taxRateBps: (row['tax_rate_basis_points'] as num?)?.toInt() ?? 500,
            taxIsInclusive: (row['tax_is_inclusive'] as bool?) ?? false,
            discountReason: row['discount_reason'] as String? ?? '',
            clientTxId: clientTxId,
            syncStatus: syncStatus,
          ),
        );
      }
    }

    if (cloudFetched) {
      return [...localPendingOrders, ...cloudOrders];
    } else if (localPendingOrders.isNotEmpty) {
      return localPendingOrders;
    }
  }

  return ref.watch(demoOrdersProvider);
});
