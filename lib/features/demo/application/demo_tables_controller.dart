import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/demo_operations.dart';

final demoTablesProvider =
    NotifierProvider<DemoTablesController, List<DemoDiningTable>>(
      DemoTablesController.new,
    );

class DemoTablesController extends Notifier<List<DemoDiningTable>> {
  @override
  List<DemoDiningTable> build() => List.unmodifiable(demoTables);

  void reset() => state = List.unmodifiable(demoTables);

  void updateStatus(String id, TableStatus status, {String? orderNumber}) {
    state = List.unmodifiable(
      state.map((table) {
        if (table.id != id) return table;
        return table.copyWith(
          status: status,
          currentOrderNumber: status == TableStatus.available
              ? null
              : orderNumber,
        );
      }),
    );
  }
}
