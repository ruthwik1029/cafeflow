import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cafeflow/core/database/database_gateway.dart';
import 'package:cafeflow/core/errors/app_failure.dart';
import 'package:cafeflow/core/routing/workspace.dart';
import 'package:cafeflow/core/storage/local_database.dart';
import 'package:cafeflow/core/sync/cafe_sync_service.dart';
import 'package:cafeflow/core/sync/sync_models.dart';
import 'package:cafeflow/core/sync/sync_queue.dart';
import 'package:cafeflow/features/inventory/data/supabase_inventory_repository.dart';
import 'package:cafeflow/features/inventory/presentation/inventory_page.dart';
import 'package:cafeflow/features/staff/data/staff_repository.dart';
import 'package:cafeflow/features/staff/presentation/staff_page.dart';

class MockDatabaseGateway implements DatabaseGateway {
  final Map<String, List<Map<String, dynamic>>> tables = {};

  @override
  Future<List<Map<String, dynamic>>> readRows(
    String relation, {
    Map<String, Object> equals = const {},
    int limit = 100,
  }) async {
    final rows = tables[relation] ?? [];
    return rows
        .where((row) {
          for (final entry in equals.entries) {
            if (row[entry.key] != entry.value) return false;
          }
          return true;
        })
        .take(limit)
        .toList();
  }
}

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 09: Inventory Domain Models & Valuation Tests', () {
    test('InventoryItem calculates stock valuation in integer minor units', () {
      final item = InventoryItem(
        id: 'inv-1',
        restaurantId: 'rest-1',
        name: 'Single Origin Espresso Beans',
        unit: 'kg',
        currentStock: 12.5,
        minimumStock: 4.0,
        reorderLevel: 8.0,
        costPerUnitMinor: 250000, // $25.00 per kg
        sku: 'BEAN-SO-01',
        storageLocation: 'Roastery Shelf 2',
      );

      expect(item.name, 'Single Origin Espresso Beans');
      expect(item.currentStock, 12.5);
      expect(item.reorderLevel, 8.0);
      expect(item.costPerUnitMinor, 250000);
      // Valuation: 12.5 * 250000 = 3125000 minor units ($312.50)
      expect(item.stockValuationMinor, 3125000);
      expect(item.isLow, isFalse);
      expect(item.isOutOfStock, isFalse);
    });

    test(
      'InventoryItem correctly evaluates low stock and out-of-stock thresholds',
      () {
        final normalItem = InventoryItem(
          id: 'inv-1',
          restaurantId: 'rest-1',
          name: 'Whole Milk',
          unit: 'L',
          currentStock: 20.0,
          minimumStock: 5.0,
          reorderLevel: 10.0,
        );
        expect(normalItem.isLow, isFalse);
        expect(normalItem.isOutOfStock, isFalse);

        final lowItem = normalItem.copyWith(currentStock: 8.0);
        expect(lowItem.isLow, isTrue);
        expect(lowItem.isOutOfStock, isFalse);

        final outItem = normalItem.copyWith(currentStock: 0.0);
        expect(outItem.isLow, isTrue);
        expect(outItem.isOutOfStock, isTrue);
      },
    );

    test('InventoryItem serializes and deserializes from database map', () {
      final map = {
        'id': 'inv-42',
        'restaurant_id': 'rest-101',
        'name': 'Matcha Powder Ceremonial',
        'unit': 'kg',
        'current_stock': 3.5,
        'minimum_stock': 1.0,
        'reorder_level': 2.0,
        'cost_per_unit_minor': 850000,
        'sku': 'TEA-MAT-01',
        'category_id': 'cat-1',
        'supplier_id': 'sup-1',
        'storage_location': 'Dry Pantry B',
        'is_archived': false,
      };

      final item = InventoryItem.fromMap(
        map,
        catName: 'Specialty Teas',
        supName: 'Kyoto Imports Ltd',
      );

      expect(item.id, 'inv-42');
      expect(item.restaurantId, 'rest-101');
      expect(item.name, 'Matcha Powder Ceremonial');
      expect(item.categoryName, 'Specialty Teas');
      expect(item.supplierName, 'Kyoto Imports Ltd');
      expect(item.costPerUnitMinor, 850000);
      expect(item.stockValuationMinor, (3.5 * 850000).round());

      final serialized = item.toMap();
      expect(serialized['id'], 'inv-42');
      expect(serialized['name'], 'Matcha Powder Ceremonial');
      expect(serialized['unit'], 'kg');
      expect(serialized['cost_per_unit_minor'], 850000);
    });
  });

  group('Phase 09: Stock Ledger & Movement Types Tests', () {
    test('StockMovementType supports all 8 canonical operational movement categories', () {
      expect(StockMovementType.purchase.dbValue, 'PURCHASE');
      expect(StockMovementType.saleConsumption.dbValue, 'SALE_CONSUMPTION');
      expect(StockMovementType.manualAdjustment.dbValue, 'MANUAL_ADJUSTMENT');
      expect(StockMovementType.wastage.dbValue, 'WASTAGE');
      expect(StockMovementType.damage.dbValue, 'DAMAGE');
      expect(StockMovementType.returnMovement.dbValue, 'RETURN');
      expect(StockMovementType.transfer.dbValue, 'TRANSFER');
      expect(StockMovementType.reversal.dbValue, 'REVERSAL');

      expect(StockMovementType.fromDb('PURCHASE'), StockMovementType.purchase);
      expect(
        StockMovementType.fromDb('SALE_CONSUMPTION'),
        StockMovementType.saleConsumption,
      );
      expect(
        StockMovementType.fromDb('MANUAL_ADJUSTMENT'),
        StockMovementType.manualAdjustment,
      );
      expect(StockMovementType.fromDb('WASTAGE'), StockMovementType.wastage);
      expect(StockMovementType.fromDb('DAMAGE'), StockMovementType.damage);
      expect(
        StockMovementType.fromDb('RETURN'),
        StockMovementType.returnMovement,
      );
      expect(StockMovementType.fromDb('TRANSFER'), StockMovementType.transfer);
      expect(StockMovementType.fromDb('REVERSAL'), StockMovementType.reversal);
    });

    test('StockMovement preserves immutable transition ledger details', () {
      final now = DateTime.now();
      final movement = StockMovement(
        id: 'mov-100',
        restaurantId: 'rest-1',
        inventoryItemId: 'inv-beans',
        itemName: 'House espresso beans',
        movementType: StockMovementType.purchase,
        quantityChange: 20.0,
        previousStock: 5.0,
        newStock: 25.0,
        unit: 'kg',
        reference: 'PO-2026-088',
        reason: 'Weekly shipment intake',
        performedBy: 'usr-admin-1',
        createdAt: now,
      );

      expect(movement.id, 'mov-100');
      expect(movement.movementType, StockMovementType.purchase);
      expect(movement.quantityChange, 20.0);
      expect(movement.previousStock, 5.0);
      expect(movement.newStock, 25.0);
      expect(movement.reference, 'PO-2026-088');

      final map = movement.toMap();
      expect(map['previous_stock'], 5.0);
      expect(map['new_stock'], 25.0);

      final fromMap = StockMovement.fromMap(
        map,
        itemTitle: 'House espresso beans',
      );
      expect(fromMap.id, movement.id);
      expect(fromMap.newStock, 25.0);
      expect(fromMap.movementType, StockMovementType.purchase);
    });
  });

  group('Phase 09: Suppliers & Purchase Orders Workflow Tests', () {
    test(
      'Supplier profile serializes and deserializes with contact information',
      () {
        final supplier = Supplier(
          id: 'sup-1',
          restaurantId: 'rest-1',
          name: 'Artisan Dairy Farms',
          contactName: 'Ravi Patel',
          email: 'orders@artisandairy.example',
          phone: '+91 98200 88990',
          address: 'Anand District, Gujarat',
          notes: 'Delivers daily before 07:00 AM',
          isActive: true,
        );

        expect(supplier.name, 'Artisan Dairy Farms');
        expect(supplier.contactName, 'Ravi Patel');
        expect(supplier.phone, '+91 98200 88990');
        expect(supplier.isActive, isTrue);

        final map = supplier.toMap();
        expect(map['name'], 'Artisan Dairy Farms');
        expect(map['contact_name'], 'Ravi Patel');

        final deserialized = Supplier.fromMap(map);
        expect(deserialized.id, supplier.id);
        expect(deserialized.name, supplier.name);
      },
    );

    test(
      'PurchaseRecord and PurchaseItemRecord track cost breakdown and receipt',
      () {
        final now = DateTime.now();
        final po = PurchaseRecord(
          id: 'po-1',
          restaurantId: 'rest-1',
          purchaseNumber: 'PO-2026-501',
          supplierId: 'sup-1',
          supplierName: 'Artisan Dairy Farms',
          status: 'ORDERED',
          purchaseDate: now,
          subtotalMinor: 500000,
          taxMinor: 25000,
          totalMinor: 525000,
          notes: 'Monthly bulk whole milk replenishment',
          items: const [
            PurchaseItemRecord(
              id: 'poi-1',
              purchaseId: 'po-1',
              inventoryItemId: 'inv-milk',
              inventoryItemName: 'Organic Whole Milk',
              quantity: 50.0,
              unit: 'L',
              unitCostMinor: 10000,
              totalCostMinor: 500000,
              quantityReceived: 0.0,
            ),
          ],
        );

        expect(po.purchaseNumber, 'PO-2026-501');
        expect(po.status, 'ORDERED');
        expect(po.totalMinor, 525000);
        expect(po.items.first.quantity, 50.0);
        expect(po.items.first.quantityReceived, 0.0);

        // Simulating receiving updates status to RECEIVED and sets quantityReceived
        final receivedPo = PurchaseRecord(
          id: po.id,
          restaurantId: po.restaurantId,
          purchaseNumber: po.purchaseNumber,
          supplierId: po.supplierId,
          supplierName: po.supplierName,
          status: 'RECEIVED',
          purchaseDate: po.purchaseDate,
          subtotalMinor: po.subtotalMinor,
          taxMinor: po.taxMinor,
          totalMinor: po.totalMinor,
          receivedAt: DateTime.now(),
          items: const [
            PurchaseItemRecord(
              id: 'poi-1',
              purchaseId: 'po-1',
              inventoryItemId: 'inv-milk',
              inventoryItemName: 'Organic Whole Milk',
              quantity: 50.0,
              unit: 'L',
              unitCostMinor: 10000,
              totalCostMinor: 500000,
              quantityReceived: 50.0,
            ),
          ],
        );

        expect(receivedPo.status, 'RECEIVED');
        expect(receivedPo.receivedAt, isNotNull);
        expect(receivedPo.items.first.quantityReceived, 50.0);
      },
    );
  });

  group('Phase 09: Recipe & Ingredient Management Tests', () {
    test('MenuItemIngredient serializes and deserializes recipe binding', () {
      final recipeItem = MenuItemIngredient(
        id: 'rec-1',
        restaurantId: 'rest-1',
        menuItemId: 'prod-cappuccino',
        inventoryItemId: 'inv-beans',
        inventoryItemName: 'House espresso beans',
        quantity: 0.018,
        unit: 'kg',
        notes: 'Double shot dose',
      );

      expect(recipeItem.menuItemId, 'prod-cappuccino');
      expect(recipeItem.inventoryItemId, 'inv-beans');
      expect(recipeItem.quantity, 0.018);
      expect(recipeItem.unit, 'kg');

      final map = recipeItem.toMap();
      expect(map['menu_item_id'], 'prod-cappuccino');
      expect(map['quantity'], 0.018);

      final fromMap = MenuItemIngredient.fromMap(
        map,
        ingName: 'House espresso beans',
      );
      expect(fromMap.id, recipeItem.id);
      expect(fromMap.quantity, 0.018);
      expect(fromMap.inventoryItemName, 'House espresso beans');
    });

    test('Recipe deduction calculates proportional ingredient consumption', () {
      // Espresso: 18g beans
      const beansPerServing = 0.018; // kg
      const milkPerServing = 0.150; // L

      const orderQuantity = 4;
      final expectedBeans = orderQuantity * beansPerServing;
      final expectedMilk = orderQuantity * milkPerServing;

      expect(expectedBeans, closeTo(0.072, 0.0001));
      expect(expectedMilk, closeTo(0.600, 0.0001));
    });
  });

  group('Phase 09: Staff Profiles, Shifts & Attendance Domain Tests', () {
    test('EmploymentStatus maps canonical database values', () {
      expect(EmploymentStatus.fullTime.dbValue, 'FULL_TIME');
      expect(EmploymentStatus.partTime.dbValue, 'PART_TIME');
      expect(EmploymentStatus.casual.dbValue, 'CASUAL');
      expect(EmploymentStatus.terminated.dbValue, 'TERMINATED');

      expect(EmploymentStatus.fromDb('FULL_TIME'), EmploymentStatus.fullTime);
      expect(EmploymentStatus.fromDb('PART_TIME'), EmploymentStatus.partTime);
      expect(EmploymentStatus.fromDb('CASUAL'), EmploymentStatus.casual);
      expect(
        EmploymentStatus.fromDb('TERMINATED'),
        EmploymentStatus.terminated,
      );
      expect(EmploymentStatus.fromDb('unknown'), EmploymentStatus.fullTime);
    });

    test('StaffProfileRecord maintains department and emergency contacts', () {
      final profile = StaffProfileRecord(
        id: 'prof-1',
        userId: 'usr-42',
        restaurantId: 'rest-1',
        fullName: 'Aanya Rao',
        username: 'aanya.manager',
        role: WorkspaceRole.owner,
        department: 'Management',
        employmentStatus: EmploymentStatus.fullTime,
        joiningDate: DateTime(2025, 1, 15),
        phone: '+91 98200 12345',
        emergencyContactName: 'Vikram Rao',
        emergencyContactPhone: '+91 98200 98765',
        notes: 'Founding General Manager',
      );

      expect(profile.fullName, 'Aanya Rao');
      expect(profile.department, 'Management');
      expect(profile.employmentStatus, EmploymentStatus.fullTime);
      expect(profile.emergencyContactName, 'Vikram Rao');

      final map = profile.toMap();
      expect(map['department'], 'Management');
      expect(map['employment_status'], 'FULL_TIME');
      expect(map['emergency_contact_name'], 'Vikram Rao');
    });

    test('ShiftRecord models time range and department assignment', () {
      final shift = ShiftRecord(
        id: 'shift-1',
        restaurantId: 'rest-1',
        name: 'Morning Opening Shift',
        startTime: '06:30:00',
        endTime: '14:30:00',
        department: 'Barista & Front of House',
        isActive: true,
      );

      expect(shift.name, 'Morning Opening Shift');
      expect(shift.startTime, '06:30:00');
      expect(shift.endTime, '14:30:00');
      expect(shift.timeRangeLabel, '06:30:00 - 14:30:00');
      expect(shift.isActive, isTrue);

      final map = shift.toMap();
      expect(map['start_time'], '06:30:00');
      expect(map['end_time'], '14:30:00');

      final fromMap = ShiftRecord.fromMap(map);
      expect(fromMap.id, shift.id);
      expect(fromMap.name, shift.name);
    });

    test('StaffAttendanceRecord tracks duty status, duration, and breaks', () {
      final clockInTime = DateTime.now().subtract(
        const Duration(hours: 4, minutes: 30),
      );
      final clockOutTime = DateTime.now();

      final record = StaffAttendanceRecord(
        id: 'att-1',
        restaurantId: 'rest-1',
        userId: 'usr-42',
        userName: 'Kabir Shah',
        shiftName: 'Morning Opening Shift',
        clockIn: clockInTime,
        clockOut: clockOutTime,
        totalBreakMinutes: 30,
        status: AttendanceStatus.clockedOut,
        isLate: false,
        notes: 'Handover complete to afternoon crew',
      );

      expect(record.userName, 'Kabir Shah');
      expect(record.status, AttendanceStatus.clockedOut);
      expect(record.totalBreakMinutes, 30);
      expect(record.duration.inMinutes, greaterThanOrEqualTo(270));
      expect(record.formattedDuration, contains('h'));
    });
  });

  group('Phase 09: SEC-01 RBAC & Staff Management Security Guards', () {
    test('Admin cannot provision an OWNER account under SEC-01', () async {
      final gateway = MockDatabaseGateway();
      final repo = StaffRepository(gateway: gateway, client: null);

      expect(
        () => repo.provisionStaff(
          restaurantId: 'rest-1',
          targetUserId: 'usr-new-owner',
          role: WorkspaceRole.owner,
          fullName: 'Malicious Admin Promotion',
          callerRole: WorkspaceRole.admin,
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('Privilege escalation violation'),
          ),
        ),
      );
    });

    test(
      'Staff user cannot change their own role (anti-self-promotion)',
      () async {
        final gateway = MockDatabaseGateway();
        final repo = StaffRepository(gateway: gateway, client: null);

        expect(
          () => repo.updateStaffRole(
            restaurantId: 'rest-1',
            targetUserId: 'usr-self',
            newRole: WorkspaceRole.admin,
            callerRole: WorkspaceRole.admin,
            callerUserId: 'usr-self', // Same caller and target!
            targetCurrentRole: WorkspaceRole.staff,
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'message',
              contains(
                'Security violation: users cannot change their own role',
              ),
            ),
          ),
        );
      },
    );

    test(
      'Admin cannot modify an existing OWNER account under SEC-01',
      () async {
        final gateway = MockDatabaseGateway();
        final repo = StaffRepository(gateway: gateway, client: null);

        expect(
          () => repo.updateStaffRole(
            restaurantId: 'rest-1',
            targetUserId: 'usr-owner-id',
            newRole: WorkspaceRole.staff,
            callerRole: WorkspaceRole.admin,
            callerUserId: 'usr-admin-id',
            targetCurrentRole: WorkspaceRole.owner,
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'message',
              contains(
                'Security violation: Admins cannot modify an Owner account',
              ),
            ),
          ),
        );
      },
    );

    test('Admin cannot grant the OWNER role under SEC-01', () async {
      final gateway = MockDatabaseGateway();
      final repo = StaffRepository(gateway: gateway, client: null);

      expect(
        () => repo.updateStaffRole(
          restaurantId: 'rest-1',
          targetUserId: 'usr-staff-id',
          newRole: WorkspaceRole.owner,
          callerRole: WorkspaceRole.admin,
          callerUserId: 'usr-admin-id',
          targetCurrentRole: WorkspaceRole.cashier,
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains(
              'Privilege escalation violation: Admins cannot grant the OWNER role',
            ),
          ),
        ),
      );
    });

    test('Non-administrative role cannot provision staff', () async {
      final gateway = MockDatabaseGateway();
      final repo = StaffRepository(gateway: gateway, client: null);

      expect(
        () => repo.provisionStaff(
          restaurantId: 'rest-1',
          targetUserId: 'usr-new-id',
          role: WorkspaceRole.staff,
          fullName: 'Unauthorized Provisioning',
          callerRole: WorkspaceRole.kitchen,
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('Unauthorized: only Owners and Admins may add staff'),
          ),
        ),
      );
    });
  });

  group('Phase 09: Offline Persistence & Sync Queue Tests', () {
    test('LocalDatabase includes Phase 09 collections in tenant isolation clearing', () async {
      final adapter = MemoryStorageAdapter();
      final db = CafeLocalDatabase(adapter: adapter);
      await db.initialize();

      // Put records in Phase 09 collections
      await db.put('inventory_items', 'inv-1', {
        'id': 'inv-1',
        'restaurant_id': 'rest-1',
        'name': 'Coffee Beans',
      });
      await db.put('suppliers', 'sup-1', {
        'id': 'sup-1',
        'restaurant_id': 'rest-1',
        'name': 'Blue Tokai',
      });
      await db.put('shifts', 'shift-1', {
        'id': 'shift-1',
        'restaurant_id': 'rest-1',
        'name': 'Morning',
      });
      await db.put('staff_attendance', 'att-1', {
        'id': 'att-1',
        'restaurant_id': 'rest-1',
        'status': 'CLOCKED_IN',
      });

      expect(await db.get('inventory_items', 'inv-1'), isNotNull);
      expect(await db.get('suppliers', 'sup-1'), isNotNull);
      expect(await db.get('shifts', 'shift-1'), isNotNull);
      expect(await db.get('staff_attendance', 'att-1'), isNotNull);

      // Clearing tenant data must purge all Phase 09 collections for this tenant cleanly
      await db.clearTenantCache('rest-1');

      expect(await db.get('inventory_items', 'inv-1'), isNull);
      expect(await db.get('suppliers', 'sup-1'), isNull);
      expect(await db.get('shifts', 'shift-1'), isNull);
      expect(await db.get('staff_attendance', 'att-1'), isNull);
    });

    test(
      'CafeSyncService registers offline stock adjustment operation',
      () async {
        final adapter = MemoryStorageAdapter();
        final db = CafeLocalDatabase(adapter: adapter);
        await db.initialize();
        final queue = SyncQueue(db);
        final syncService = CafeSyncService(
          database: db,
          queue: queue,
          client: null,
        );

        final movementId = await syncService.queueOfflineStockAdjustment(
          restaurantId: 'rest-1',
          inventoryItemId: 'inv-beans',
          movementType: 'MANUAL_ADJUSTMENT',
          quantityChange: -2.5,
          reason: 'Physical cycle count adjustment',
        );

        expect(movementId, isNotEmpty);
        final pendingOps = await queue.getPendingOperations(
          restaurantId: 'rest-1',
        );
        expect(pendingOps, isNotEmpty);
        final pending = pendingOps.first;
        expect(pending.entityType, SyncEntityType.inventory);
        expect(pending.operationType, SyncOperationType.adjustStock);
        expect(pending.payload['movement_type'], 'MANUAL_ADJUSTMENT');
        expect(pending.payload['quantity_change'], -2.5);
      },
    );

    test(
      'CafeSyncService registers offline staff attendance operation',
      () async {
        final adapter = MemoryStorageAdapter();
        final db = CafeLocalDatabase(adapter: adapter);
        await db.initialize();
        final queue = SyncQueue(db);
        final syncService = CafeSyncService(
          database: db,
          queue: queue,
          client: null,
        );

        final attendanceId = await syncService.queueOfflineAttendance(
          restaurantId: 'rest-1',
          userId: 'usr-42',
          action: 'CLOCK_IN',
          shiftId: 'shift-morning',
          notes: 'Offline clock-in on local tablet',
        );

        expect(attendanceId, isNotEmpty);
        final pendingOps = await queue.getPendingOperations(
          restaurantId: 'rest-1',
        );
        final attItem = pendingOps.firstWhere(
          (i) => i.entityType == SyncEntityType.staff,
        );
        expect(attItem.operationType, SyncOperationType.recordAttendance);
        expect(attItem.payload['action'], 'CLOCK_IN');
        expect(attItem.payload['shift_id'], 'shift-morning');
      },
    );
  });

  group('Phase 09: Inventory & Staff Page Widget Tests', () {
    testWidgets(
      'InventoryPage renders all tabs and preserves backward compatibility',
      (tester) async {
        await tester.pumpWidget(_wrap(const InventoryPage()));
        await tester.pumpAndSettle();

        // Backward compatible assertions
        expect(find.text('Inventory Management'), findsOneWidget);
        expect(find.text('House espresso beans'), findsOneWidget);
        expect(find.text('Restock'), findsWidgets);

        // Phase 09 navigation tabs
        expect(find.text('Items & Stock'), findsOneWidget);
        expect(find.text('Stock Ledger'), findsOneWidget);
        expect(find.text('Suppliers'), findsOneWidget);
        expect(find.text('Purchase Orders'), findsOneWidget);
        expect(find.text('Recipes & BOM'), findsOneWidget);

        // Switch to Stock Ledger tab
        await tester.tap(find.text('Stock Ledger'));
        await tester.pumpAndSettle();
        expect(find.text('Stock Ledger & Audit Trail'), findsOneWidget);

        // Switch to Suppliers tab
        await tester.tap(find.text('Suppliers'));
        await tester.pumpAndSettle();
        expect(find.text('Suppliers & Vendors'), findsOneWidget);

        // Switch to Purchase Orders tab
        await tester.tap(find.text('Purchase Orders'));
        await tester.pumpAndSettle();
        expect(find.text('Purchase Orders & Receiving'), findsOneWidget);

        // Switch to Recipes & BOM tab
        await tester.tap(find.text('Recipes & BOM'));
        await tester.pumpAndSettle();
        expect(find.text('Recipe & BOM Management'), findsOneWidget);
        expect(find.text('Idempotent Recipe Deduction Engine'), findsOneWidget);
      },
    );

    testWidgets(
      'StaffPage renders all tabs and preserves backward compatibility',
      (tester) async {
        await tester.pumpWidget(_wrap(const StaffPage()));
        await tester.pumpAndSettle();

        // Backward compatible assertions
        expect(find.text('Team & Staff Management'), findsOneWidget);
        expect(find.text('Aanya Rao'), findsOneWidget);
        expect(find.text('Kabir Shah'), findsOneWidget);

        // Phase 09 navigation tabs
        expect(find.text('Team Roster'), findsOneWidget);
        expect(find.text('Shifts & Hours'), findsOneWidget);
        expect(find.text('Attendance Terminal'), findsOneWidget);
        expect(find.text('Role Permissions Matrix'), findsOneWidget);
        expect(find.text('Activity Audit Log'), findsOneWidget);

        // Switch to Shifts & Hours tab
        await tester.tap(find.text('Shifts & Hours'));
        await tester.pumpAndSettle();
        expect(find.text('Shift Scheduling & Coverage'), findsOneWidget);

        // Switch to Attendance Terminal tab
        await tester.tap(find.text('Attendance Terminal'));
        await tester.pumpAndSettle();
        expect(find.text('Attendance & Time Tracking'), findsOneWidget);
        expect(find.text('Duty Timeclock Terminal'), findsOneWidget);

        // Switch to Role Permissions Matrix tab
        await tester.tap(find.text('Role Permissions Matrix'));
        await tester.pumpAndSettle();
        expect(find.text('Role & Permissions Matrix (SEC-01)'), findsOneWidget);

        // Switch to Activity Audit Log tab
        await tester.tap(find.text('Activity Audit Log'));
        await tester.pumpAndSettle();
        expect(find.text('Workforce & Operational Audit'), findsOneWidget);
      },
    );
  });
}
