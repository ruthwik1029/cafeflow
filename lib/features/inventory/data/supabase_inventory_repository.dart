import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/database_gateway.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/backend.dart';
import '../../../core/services/cafe_realtime_service.dart';
import '../../../core/services/realtime_gateway.dart';
import '../domain/inventory_models.dart';

export '../domain/inventory_models.dart';

typedef InventoryRecord = InventoryItem;

class SupabaseInventoryRepository {
  SupabaseInventoryRepository({
    required this.gateway,
    this.client,
    this.realtime,
  });

  final DatabaseGateway gateway;
  final SupabaseClient? client;
  final CafeRealtimeService? realtime;

  // --------------------------------------------------------------------------
  // Inventory Items & Categories
  // --------------------------------------------------------------------------

  Future<List<InventoryItem>> listInventory(
    String restaurantId, {
    bool includeArchived = false,
  }) async {
    final equals = <String, Object>{
      'restaurant_id': restaurantId,
      'deleted_at': 'null',
    };
    if (!includeArchived) {
      equals['is_archived'] = false;
    }

    final rows = await gateway.readRows(
      'inventory_items',
      equals: equals,
      limit: 200,
    );

    // Map category and supplier names in batch
    Map<String, String> catMap = {};
    try {
      final catRows = await gateway.readRows(
        'inventory_categories',
        equals: {'restaurant_id': restaurantId},
        limit: 100,
      );
      for (final r in catRows) {
        catMap[r['id'] as String] = r['name'] as String;
      }
    } catch (_) {}

    Map<String, String> supMap = {};
    try {
      final supRows = await gateway.readRows(
        'suppliers',
        equals: {'restaurant_id': restaurantId},
        limit: 100,
      );
      for (final r in supRows) {
        supMap[r['id'] as String] = r['name'] as String;
      }
    } catch (_) {}

    final items = rows.map((row) {
      final catId = row['category_id'] as String?;
      final supId = row['supplier_id'] as String?;
      return InventoryItem.fromMap(
        row,
        catName: catId != null && catMap.containsKey(catId)
            ? catMap[catId]
            : 'General',
        supName: supId != null && supMap.containsKey(supId)
            ? supMap[supId]
            : null,
      );
    }).toList();

    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return items;
  }

  Future<InventoryItem> createItem({
    required String restaurantId,
    required String name,
    required String unit,
    double currentStock = 0.0,
    double minimumStock = 0.0,
    double reorderLevel = 0.0,
    int costPerUnitMinor = 0,
    String? sku,
    String? categoryId,
    String? supplierId,
    String storageLocation = 'Kitchen Pantry',
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const AppFailure('Item name cannot be empty.');
    }
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .from('inventory_items')
          .insert({
            'restaurant_id': restaurantId,
            'name': trimmedName,
            'unit': unit.trim(),
            'current_stock': currentStock,
            'minimum_stock': minimumStock,
            'reorder_level': reorderLevel,
            'cost_per_unit_minor': costPerUnitMinor,
            'sku': sku?.trim().isEmpty == true ? null : sku?.trim(),
            'category_id': categoryId,
            'supplier_id': supplierId,
            'storage_location': storageLocation.trim(),
            'is_archived': false,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 15));

      return InventoryItem.fromMap(res);
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure(
          'Unauthorized: only kitchen and admin staff can manage stock.',
        );
      }
      throw AppFailure(e.message);
    } catch (_) {
      throw const AppFailure('Network failure while adding inventory item.');
    }
  }

  Future<void> updateItem({
    required String restaurantId,
    required String itemId,
    required String name,
    required String unit,
    double minimumStock = 0.0,
    double reorderLevel = 0.0,
    int costPerUnitMinor = 0,
    String? sku,
    String? categoryId,
    String? supplierId,
    String storageLocation = 'Kitchen Pantry',
    bool isArchived = false,
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is unavailable.');
    }

    try {
      await client!
          .from('inventory_items')
          .update({
            'name': name.trim(),
            'unit': unit.trim(),
            'minimum_stock': minimumStock,
            'reorder_level': reorderLevel,
            'cost_per_unit_minor': costPerUnitMinor,
            'sku': sku?.trim().isEmpty == true ? null : sku?.trim(),
            'category_id': categoryId,
            'supplier_id': supplierId,
            'storage_location': storageLocation.trim(),
            'is_archived': isArchived,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', itemId)
          .eq('restaurant_id', restaurantId)
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    }
  }

  // --------------------------------------------------------------------------
  // Stock Adjustment & Movements Ledger
  // --------------------------------------------------------------------------

  Future<Map<String, dynamic>> adjustStock({
    required String restaurantId,
    required String itemId,
    required String movementType,
    required double quantityChange,
    String reason = '',
    String reference = '',
    String? clientTxId,
  }) async {
    if (client == null) {
      throw const AppFailure('Database client is not available.');
    }

    try {
      final res = await client!
          .rpc(
            'adjust_inventory_stock_v2',
            params: {
              'p_restaurant_id': restaurantId,
              'p_inventory_item_id': itemId,
              'p_movement_type': movementType.toUpperCase(),
              'p_quantity_change': quantityChange,
              'p_reason': reason.trim(),
              'p_reference': reference.trim(),
              'p_client_tx_id': clientTxId,
            },
          )
          .timeout(const Duration(seconds: 15));

      return Map<String, dynamic>.from(res as Map);
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw AppFailure('Permission denied: ${e.message}');
      }
      throw AppFailure(e.message);
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw const AppFailure('Network failure during stock adjustment.');
    }
  }

  Future<List<StockMovement>> listMovements(
    String restaurantId, {
    String? itemId,
    int limit = 100,
  }) async {
    final equals = <String, Object>{'restaurant_id': restaurantId};
    if (itemId != null) {
      equals['inventory_item_id'] = itemId;
    }

    final rows = await gateway.readRows(
      'stock_movements',
      equals: equals,
      limit: limit,
    );

    // Map item names in batch
    Map<String, String> itemMap = {};
    try {
      final itemRows = await gateway.readRows(
        'inventory_items',
        equals: {'restaurant_id': restaurantId},
        limit: 200,
      );
      for (final r in itemRows) {
        itemMap[r['id'] as String] = r['name'] as String;
      }
    } catch (_) {}

    final movements = rows.map((r) {
      final itId = r['inventory_item_id'] as String;
      return StockMovement.fromMap(r, itemTitle: itemMap[itId] ?? 'Ingredient');
    }).toList();

    movements.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return movements;
  }

  // --------------------------------------------------------------------------
  // Suppliers
  // --------------------------------------------------------------------------

  Future<List<Supplier>> listSuppliers(
    String restaurantId, {
    bool includeInactive = false,
  }) async {
    final equals = <String, Object>{'restaurant_id': restaurantId};
    if (!includeInactive) {
      equals['is_active'] = true;
    }

    final rows = await gateway.readRows(
      'suppliers',
      equals: equals,
      limit: 100,
    );

    final suppliers = rows.map(Supplier.fromMap).toList();
    suppliers.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return suppliers;
  }

  Future<Supplier> createSupplier({
    required String restaurantId,
    required String name,
    String contactName = '',
    String email = '',
    String phone = '',
    String address = '',
    String notes = '',
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const AppFailure('Supplier name cannot be empty.');
    }
    if (client == null) {
      throw const AppFailure('Database client unavailable.');
    }

    try {
      final res = await client!
          .from('suppliers')
          .insert({
            'restaurant_id': restaurantId,
            'name': trimmed,
            'contact_name': contactName.trim(),
            'email': email.trim(),
            'phone': phone.trim(),
            'address': address.trim(),
            'notes': notes.trim(),
            'is_active': true,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 15));

      return Supplier.fromMap(res);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    }
  }

  Future<void> updateSupplier({
    required String restaurantId,
    required String supplierId,
    required String name,
    String contactName = '',
    String email = '',
    String phone = '',
    String address = '',
    String notes = '',
    bool isActive = true,
  }) async {
    if (client == null) throw const AppFailure('Database client unavailable.');

    try {
      await client!
          .from('suppliers')
          .update({
            'name': name.trim(),
            'contact_name': contactName.trim(),
            'email': email.trim(),
            'phone': phone.trim(),
            'address': address.trim(),
            'notes': notes.trim(),
            'is_active': isActive,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', supplierId)
          .eq('restaurant_id', restaurantId)
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    }
  }

  // --------------------------------------------------------------------------
  // Purchases
  // --------------------------------------------------------------------------

  Future<List<PurchaseRecord>> listPurchases(
    String restaurantId, {
    String? status,
    int limit = 50,
  }) async {
    final equals = <String, Object>{'restaurant_id': restaurantId};
    if (status != null) {
      equals['status'] = status;
    }

    final rows = await gateway.readRows(
      'purchases',
      equals: equals,
      limit: limit,
    );

    // Map suppliers
    Map<String, String> supMap = {};
    try {
      final sups = await listSuppliers(restaurantId, includeInactive: true);
      for (final s in sups) {
        supMap[s.id] = s.name;
      }
    } catch (_) {}

    // Map inventory items
    Map<String, String> itemMap = {};
    try {
      final items = await listInventory(restaurantId, includeArchived: true);
      for (final it in items) {
        itemMap[it.id] = it.name;
      }
    } catch (_) {}

    final List<PurchaseRecord> purchases = [];
    for (final row in rows) {
      final purchaseId = row['id'] as String;
      final itemRows = await gateway.readRows(
        'purchase_items',
        equals: {'purchase_id': purchaseId},
        limit: 50,
      );

      final purchaseItems = itemRows.map((ir) {
        final itId = ir['inventory_item_id'] as String;
        return PurchaseItemRecord.fromMap(
          ir,
          itemName: itemMap[itId] ?? 'Item',
        );
      }).toList();

      final sId = row['supplier_id'] as String?;
      purchases.add(
        PurchaseRecord.fromMap(
          row,
          supName: sId != null ? supMap[sId] : 'Vendor',
          items: purchaseItems,
        ),
      );
    }

    purchases.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    return purchases;
  }

  Future<PurchaseRecord> createPurchase({
    required String restaurantId,
    required String purchaseNumber,
    String? supplierId,
    DateTime? purchaseDate,
    DateTime? expectedDeliveryDate,
    required List<Map<String, dynamic>> items,
    int subtotalMinor = 0,
    int taxMinor = 0,
    int additionalChargesMinor = 0,
    int totalMinor = 0,
    String notes = '',
    String? clientTxId,
  }) async {
    if (client == null) throw const AppFailure('Database client unavailable.');

    try {
      final purchaseRes = await client!
          .from('purchases')
          .insert({
            'restaurant_id': restaurantId,
            'purchase_number': purchaseNumber.trim(),
            'supplier_id': supplierId,
            'purchase_date': (purchaseDate ?? DateTime.now())
                .toIso8601String()
                .substring(0, 10),
            'expected_delivery_date': expectedDeliveryDate
                ?.toIso8601String()
                .substring(0, 10),
            'subtotal_minor': subtotalMinor,
            'tax_minor': taxMinor,
            'additional_charges_minor': additionalChargesMinor,
            'total_minor': totalMinor,
            'notes': notes.trim(),
            'status': 'ORDERED',
            'client_tx_id': clientTxId,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 15));

      final purchaseId = purchaseRes['id'] as String;

      // Insert purchase items
      for (final item in items) {
        await client!.from('purchase_items').insert({
          'purchase_id': purchaseId,
          'inventory_item_id': item['inventory_item_id'],
          'quantity': item['quantity'],
          'unit': item['unit'],
          'unit_cost_minor': item['unit_cost_minor'] ?? 0,
          'total_cost_minor': item['total_cost_minor'] ?? 0,
        });
      }

      return PurchaseRecord.fromMap(purchaseRes);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    }
  }

  Future<Map<String, dynamic>> receivePurchase({
    required String restaurantId,
    required String purchaseId,
    String notes = '',
  }) async {
    if (client == null) throw const AppFailure('Database client unavailable.');

    try {
      final res = await client!
          .rpc(
            'receive_purchase_order',
            params: {
              'p_restaurant_id': restaurantId,
              'p_purchase_id': purchaseId,
              'p_notes': notes.trim(),
            },
          )
          .timeout(const Duration(seconds: 15));

      return Map<String, dynamic>.from(res as Map);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    }
  }

  // --------------------------------------------------------------------------
  // Recipes & Ingredient Consumption
  // --------------------------------------------------------------------------

  Future<List<MenuItemIngredient>> listRecipesForMenuItem(
    String restaurantId,
    String menuItemId,
  ) async {
    final rows = await gateway.readRows(
      'menu_item_ingredients',
      equals: {'restaurant_id': restaurantId, 'menu_item_id': menuItemId},
      limit: 50,
    );

    // Map item names
    Map<String, String> itemMap = {};
    try {
      final items = await listInventory(restaurantId, includeArchived: true);
      for (final it in items) {
        itemMap[it.id] = it.name;
      }
    } catch (_) {}

    return rows.map((r) {
      final itId = r['inventory_item_id'] as String;
      return MenuItemIngredient.fromMap(r, ingName: itemMap[itId]);
    }).toList();
  }

  Future<void> saveRecipeIngredient({
    required String restaurantId,
    required String menuItemId,
    required String inventoryItemId,
    required double quantity,
    required String unit,
    String notes = '',
  }) async {
    if (client == null) throw const AppFailure('Database client unavailable.');

    try {
      await client!
          .from('menu_item_ingredients')
          .upsert({
            'restaurant_id': restaurantId,
            'menu_item_id': menuItemId,
            'inventory_item_id': inventoryItemId,
            'quantity': quantity,
            'unit': unit.trim(),
            'notes': notes.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'menu_item_id,inventory_item_id')
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    }
  }

  Future<void> deleteRecipeIngredient({
    required String restaurantId,
    required String recipeId,
  }) async {
    if (client == null) throw const AppFailure('Database client unavailable.');

    try {
      await client!
          .from('menu_item_ingredients')
          .delete()
          .eq('id', recipeId)
          .eq('restaurant_id', restaurantId)
          .timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    }
  }

  Future<Map<String, dynamic>> deductRecipeStockForOrder({
    required String restaurantId,
    required String orderId,
  }) async {
    if (client == null) throw const AppFailure('Database client unavailable.');

    try {
      final res = await client!
          .rpc(
            'deduct_order_recipe_stock',
            params: {'p_restaurant_id': restaurantId, 'p_order_id': orderId},
          )
          .timeout(const Duration(seconds: 15));

      return Map<String, dynamic>.from(res as Map);
    } on PostgrestException catch (e) {
      throw AppFailure(e.message);
    }
  }

  Stream<void> watchInvalidations(String restaurantId) {
    if (realtime == null) return const Stream.empty();
    return realtime!
        .watchInventory(restaurantId: restaurantId)
        .transform(
          StreamTransformer<RealtimeSignal, void>.fromHandlers(
            handleData: (signal, sink) => sink.add(null),
            handleError: (error, stackTrace, sink) {},
          ),
        );
  }
}

final inventoryRepositoryProvider = Provider<SupabaseInventoryRepository?>((
  ref,
) {
  final backend = ref.watch(backendProvider);
  if (backend.status != BackendStatus.initialized) {
    return null;
  }
  return SupabaseInventoryRepository(
    gateway: ref.watch(databaseGatewayProvider),
    client: backend.client,
    realtime: ref.watch(cafeRealtimeServiceProvider),
  );
});
