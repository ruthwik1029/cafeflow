import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../orders/domain/cafe_order.dart';
import '../data/demo_operations.dart';

final demoOrdersProvider =
    NotifierProvider<DemoOrdersController, List<CafeOrder>>(
      DemoOrdersController.new,
    );

class DemoOrdersController extends Notifier<List<CafeOrder>> {
  int _next = 1043;
  @override
  List<CafeOrder> build() => List.unmodifiable(demoOrders);
  void reset() {
    state = List.unmodifiable(demoOrders);
    _next = 1043;
  }

  CafeOrder add({
    required List<OrderLine> lines,
    required String table,
    required String instructions,
    required int taxMinor,
    required int discountMinor,
  }) {
    if (lines.isEmpty) throw StateError('Choose at least one product.');
    final number = _next++;
    final order = CafeOrder(
      id: 'local-$number',
      number: 'LOCAL-$number',
      createdAt: DateTime.now(),
      lines: lines,
      table: table,
      instructions: instructions,
      taxMinor: taxMinor,
      discountMinor: discountMinor,
    );
    state = List.unmodifiable([order, ...state]);
    return order;
  }

  void advance(String id) {
    final order = state.firstWhere((o) => o.id == id);
    final next = switch (order.status) {
      OrderStatus.newOrder => OrderStatus.preparing,
      OrderStatus.preparing => OrderStatus.ready,
      _ => throw StateError('No kitchen transition is available.'),
    };
    state = List.unmodifiable(
      state.map((o) => o.id == id ? o.withStatus(next) : o),
    );
  }
}
