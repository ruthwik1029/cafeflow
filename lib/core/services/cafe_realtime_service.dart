import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend.dart';
import 'realtime_gateway.dart';

/// Reusable Realtime service that coordinates Supabase channel subscriptions
/// outside of UI widgets.
class CafeRealtimeService {
  const CafeRealtimeService(this._gateway);
  final RealtimeGateway _gateway;

  PostgresChangeFilter? _restaurantFilter(String? restaurantId) {
    if (restaurantId == null || restaurantId.isEmpty) return null;
    return PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'restaurant_id',
      value: restaurantId,
    );
  }

  /// Watch live menu updates (e.g. price change, availability toggle)
  Stream<RealtimeSignal> watchMenu({String? restaurantId}) {
    return _gateway.watch(
      ChangefeedSpec(
        table: 'menu_items',
        filter: _restaurantFilter(restaurantId),
      ),
    );
  }

  /// Watch live category updates
  Stream<RealtimeSignal> watchCategories({String? restaurantId}) {
    return _gateway.watch(
      ChangefeedSpec(
        table: 'menu_categories',
        filter: _restaurantFilter(restaurantId),
      ),
    );
  }

  /// Watch live orders and kitchen ticket changes
  Stream<RealtimeSignal> watchOrders({String? restaurantId}) {
    return _gateway.watch(
      ChangefeedSpec(table: 'orders', filter: _restaurantFilter(restaurantId)),
    );
  }

  /// Watch live order item additions or modifications
  Stream<RealtimeSignal> watchOrderItems() {
    return _gateway.watch(const ChangefeedSpec(table: 'order_items'));
  }

  /// Watch dining table occupancy and reservation changes
  Stream<RealtimeSignal> watchDiningTables({String? restaurantId}) {
    return _gateway.watch(
      ChangefeedSpec(
        table: 'dining_tables',
        filter: _restaurantFilter(restaurantId),
      ),
    );
  }

  /// Watch ingredient stock and reorder level changes
  Stream<RealtimeSignal> watchInventory({String? restaurantId}) {
    return _gateway.watch(
      ChangefeedSpec(
        table: 'inventory_items',
        filter: _restaurantFilter(restaurantId),
      ),
    );
  }

  /// Watch customer directory updates
  Stream<RealtimeSignal> watchCustomers({String? restaurantId}) {
    return _gateway.watch(
      ChangefeedSpec(
        table: 'customers',
        filter: _restaurantFilter(restaurantId),
      ),
    );
  }

  /// Watch live payment transactions
  Stream<RealtimeSignal> watchPayments({String? restaurantId}) {
    return _gateway.watch(
      ChangefeedSpec(
        table: 'payments',
        filter: _restaurantFilter(restaurantId),
      ),
    );
  }

  /// Watch live refund records
  Stream<RealtimeSignal> watchRefunds({String? restaurantId}) {
    return _gateway.watch(
      ChangefeedSpec(table: 'refunds', filter: _restaurantFilter(restaurantId)),
    );
  }

  /// Watch kitchen order tickets (KOT)
  Stream<RealtimeSignal> watchKitchenTickets({String? restaurantId}) {
    return _gateway.watch(
      ChangefeedSpec(
        table: 'kitchen_order_tickets',
        filter: _restaurantFilter(restaurantId),
      ),
    );
  }

  /// Watch table sessions
  Stream<RealtimeSignal> watchTableSessions({String? restaurantId}) {
    return _gateway.watch(
      ChangefeedSpec(
        table: 'table_sessions',
        filter: _restaurantFilter(restaurantId),
      ),
    );
  }
}

final cafeRealtimeServiceProvider = Provider<CafeRealtimeService?>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend.status != BackendStatus.initialized) {
    return null;
  }
  return CafeRealtimeService(ref.watch(realtimeGatewayProvider));
});
