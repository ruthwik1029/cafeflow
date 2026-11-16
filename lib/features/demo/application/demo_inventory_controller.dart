import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/demo_operations.dart';

final demoInventoryProvider =
    NotifierProvider<DemoInventoryController, List<DemoInventoryItem>>(
      DemoInventoryController.new,
    );

class DemoInventoryController extends Notifier<List<DemoInventoryItem>> {
  @override
  List<DemoInventoryItem> build() => List.unmodifiable(demoInventory);

  void reset() => state = List.unmodifiable(demoInventory);

  void restock(String id, double amount) {
    if (amount <= 0) {
      throw ArgumentError('Restock quantity must be positive.');
    }
    state = List.unmodifiable(
      state.map((item) {
        if (item.id != id) return item;
        return item.copyWith(quantity: item.quantity + amount);
      }),
    );
  }

  void adjust(String id, double newQuantity) {
    if (newQuantity < 0) {
      throw ArgumentError('Quantity cannot be negative.');
    }
    state = List.unmodifiable(
      state.map((item) {
        if (item.id != id) return item;
        return item.copyWith(quantity: newQuantity);
      }),
    );
  }
}
