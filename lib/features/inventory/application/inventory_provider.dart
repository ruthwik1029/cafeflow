import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backend.dart';
import '../../auth/application/auth_controller.dart';
import '../../demo/application/demo_inventory_controller.dart';
import '../data/supabase_inventory_repository.dart';

export '../data/supabase_inventory_repository.dart';

/// Active inventory items for current restaurant.
final inventoryProvider = FutureProvider<List<InventoryItem>>((ref) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(inventoryRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      repo != null &&
      restaurantId != null) {
    try {
      final sub = repo.watchInvalidations(restaurantId).listen((_) {
        ref.invalidateSelf();
      });
      ref.onDispose(sub.cancel);

      return await repo.listInventory(restaurantId);
    } catch (_) {}
  }

  // Fallback to mapped demo inventory
  final demo = ref.watch(demoInventoryProvider);
  return demo
      .map(
        (i) => InventoryItem(
          id: i.id,
          restaurantId: restaurantId ?? 'demo-rest',
          name: i.name,
          unit: i.unit,
          currentStock: i.quantity,
          minimumStock: i.minimum * 0.5,
          reorderLevel: i.minimum,
          costPerUnitMinor: 35000,
          categoryName: i.category,
        ),
      )
      .toList();
});

/// Suppliers list provider.
final suppliersProvider = FutureProvider<List<Supplier>>((ref) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(inventoryRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      repo != null &&
      restaurantId != null) {
    try {
      return await repo.listSuppliers(restaurantId);
    } catch (_) {}
  }

  // Demo fallback suppliers
  return const [
    Supplier(
      id: 'sup-1',
      restaurantId: 'demo-rest',
      name: 'Blue Tokai Estate Supply',
      contactName: 'Rohit Verma',
      phone: '+91 98200 11223',
      email: 'orders@bluetokai.example',
      address: 'Bengaluru Roastery, Karnataka',
    ),
    Supplier(
      id: 'sup-2',
      restaurantId: 'demo-rest',
      name: 'Farm Fresh Dairy Organics',
      contactName: 'Priya Joshi',
      phone: '+91 98450 33445',
      email: 'supply@farmfresh.example',
      address: 'Anand, Gujarat',
    ),
    Supplier(
      id: 'sup-3',
      restaurantId: 'demo-rest',
      name: 'Artisan Baking Supplies',
      contactName: 'Sunil Menon',
      phone: '+91 99100 55667',
      email: 'orders@artisanbakery.example',
      address: 'Mumbai West, Maharashtra',
    ),
  ];
});

/// Stock movements audit ledger provider.
final stockMovementsProvider =
    FutureProvider.family<List<StockMovement>, String?>((ref, itemId) async {
      final backend = ref.watch(backendProvider);
      final repo = ref.watch(inventoryRepositoryProvider);
      final auth = ref.watch(authControllerProvider);
      final restaurantId = auth.activeMembership?.restaurantId;

      if (backend.status == BackendStatus.initialized &&
          repo != null &&
          restaurantId != null) {
        try {
          return await repo.listMovements(restaurantId, itemId: itemId);
        } catch (_) {}
      }

      // Demo fallback movements
      final now = DateTime.now();
      return [
        StockMovement(
          id: 'mov-1',
          restaurantId: restaurantId ?? 'demo-rest',
          inventoryItemId: itemId ?? 'demo-inv-1',
          itemName: 'House espresso beans',
          movementType: StockMovementType.purchase,
          quantityChange: 15.0,
          previousStock: 5.0,
          newStock: 20.0,
          unit: 'kg',
          reference: 'PO-2026-088',
          reason: 'Weekly coffee delivery receipt',
          createdAt: now.subtract(const Duration(hours: 4)),
        ),
        StockMovement(
          id: 'mov-2',
          restaurantId: restaurantId ?? 'demo-rest',
          inventoryItemId: itemId ?? 'demo-inv-2',
          itemName: 'Whole milk',
          movementType: StockMovementType.saleConsumption,
          quantityChange: -8.0,
          previousStock: 24.0,
          newStock: 16.0,
          unit: 'L',
          reference: 'CF-1002',
          reason: 'Daily POS sale consumption',
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
      ];
    });

/// Purchase orders list provider.
final purchasesProvider = FutureProvider.family<List<PurchaseRecord>, String?>((
  ref,
  status,
) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(inventoryRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      repo != null &&
      restaurantId != null) {
    try {
      return await repo.listPurchases(restaurantId, status: status);
    } catch (_) {}
  }

  // Demo fallback purchase records
  return [
    PurchaseRecord(
      id: 'po-1',
      restaurantId: restaurantId ?? 'demo-rest',
      purchaseNumber: 'PO-2026-001',
      supplierName: 'Blue Tokai Estate Supply',
      status: 'RECEIVED',
      purchaseDate: DateTime.now().subtract(const Duration(days: 2)),
      subtotalMinor: 4500000,
      taxMinor: 225000,
      totalMinor: 4725000,
      notes: 'Speciality Arabica beans delivery',
      receivedAt: DateTime.now().subtract(const Duration(days: 1)),
      items: const [
        PurchaseItemRecord(
          id: 'poi-1',
          purchaseId: 'po-1',
          inventoryItemId: 'inv-beans',
          inventoryItemName: 'House espresso beans',
          quantity: 20.0,
          unit: 'kg',
          unitCostMinor: 225000,
          totalCostMinor: 4500000,
          quantityReceived: 20.0,
        ),
      ],
    ),
  ];
});

/// Recipe ingredients for a menu item.
final recipeProvider = FutureProvider.family<List<MenuItemIngredient>, String>((
  ref,
  menuItemId,
) async {
  final backend = ref.watch(backendProvider);
  final repo = ref.watch(inventoryRepositoryProvider);
  final auth = ref.watch(authControllerProvider);
  final restaurantId = auth.activeMembership?.restaurantId;

  if (backend.status == BackendStatus.initialized &&
      repo != null &&
      restaurantId != null) {
    try {
      return await repo.listRecipesForMenuItem(restaurantId, menuItemId);
    } catch (_) {}
  }

  return const [];
});
