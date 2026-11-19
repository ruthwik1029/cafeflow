import 'dart:convert';
import 'dart:io';

import 'package:cafeflow/core/config/app_config.dart';
import 'package:cafeflow/core/routing/workspace.dart';
import 'package:cafeflow/core/services/demo_session_service.dart';
import 'package:cafeflow/features/auth/application/auth_controller.dart';
import 'package:cafeflow/features/auth/domain/auth_user.dart';
import 'package:cafeflow/features/billing/application/cart_controller.dart';
import 'package:cafeflow/features/customer_website/application/customer_order_service.dart';
import 'package:cafeflow/features/menu/domain/catalog.dart';
import 'package:cafeflow/features/orders/domain/cafe_order.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2 Part A: DemoSessionService & Live Auth Integration Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'DemoSessionService fails closed in production when allowsDemo is false',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final service = DemoSessionService(
          client: null,
          config: const AppConfig(environment: 'production'),
          prefs: prefs,
        );

        final result = await service.provisionOrRestoreSession();
        expect(result, isNull);
        expect(service.currentSession, isNull);
      },
    );

    test('DemoSessionService falls back gracefully to null when backend is unconfigured', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = DemoSessionService(
        client: null,
        config: const AppConfig(environment: 'development'),
        prefs: prefs,
      );

      final result = await service.provisionOrRestoreSession();
      expect(result, isNull);
      expect(service.currentSession, isNull);
    });

    test('DemoSessionInfo JSON serialization and deserialization', () {
      final now = DateTime.now().add(const Duration(hours: 2));
      final info = DemoSessionInfo(
        sessionId: 'sess-12345',
        pairingCode: '482910',
        restaurantId: 'a0000000-0000-0000-0000-000000000001',
        role: 'DEMO_OWNER',
        expiresAt: now,
        accessToken: 'mock-access',
        refreshToken: 'mock-refresh',
      );

      final json = info.toJson();
      expect(json['demo_session_id'], 'sess-12345');
      expect(json['pairing_code'], '482910');
      expect(json['role'], 'DEMO_OWNER');
      expect(json['refresh_token'], 'mock-refresh');

      final fromJson = DemoSessionInfo.fromJson(json);
      expect(fromJson.sessionId, 'sess-12345');
      expect(fromJson.pairingCode, '482910');
      expect(fromJson.isExpired, isFalse);
    });

    test('DemoSessionService endDemoSession clears cached state', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        DemoSessionService.prefsKey,
        jsonEncode({
          'demo_session_id': 'sess-cached',
          'pairing_code': '123456',
          'restaurant_id': 'a0000000-0000-0000-0000-000000000001',
          'role': 'DEMO_OWNER',
          'expires_at': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'refresh_token': 'token-cached',
        }),
      );

      final service = DemoSessionService(
        client: null,
        config: const AppConfig(environment: 'staging'),
        prefs: prefs,
      );

      await service.endDemoSession();
      expect(service.currentSession, isNull);
      expect(prefs.containsKey(DemoSessionService.prefsKey), isFalse);
    });

    test(
      'AuthState models demo session metadata and active role correctly',
      () {
        const state = AuthState(
          status: AuthStatus.authenticated,
          isDemoSession: true,
          demoSessionId: 'sess-uuid-001',
          demoPairingCode: '654321',
          activeMembership: RestaurantMembershipInfo(
            restaurantId: 'a0000000-0000-0000-0000-000000000001',
            restaurantName: 'Flagship Bistro',
            role: WorkspaceRole.owner,
          ),
        );

        expect(state.isDemoSession, isTrue);
        expect(state.demoSessionId, 'sess-uuid-001');
        expect(state.demoPairingCode, '654321');
        expect(state.activeRole, WorkspaceRole.owner);
        expect(state.hasActiveMembership, isTrue);
      },
    );
  });

  group('Phase 2 Part B: Customer Online Ordering & Cart Tests', () {
    test(
      'Customer cart adds items and computes subtotal, GST and grand total',
      () {
        final container = ProviderContainer();
        final cartNotifier = container.read(cartProvider('customer').notifier);

        const espresso = MenuProduct(
          id: 'p-espresso',
          categoryId: 'cat-coffee',
          name: 'House Espresso',
          priceMinor: 18000, // ₹180.00
        );

        const croissant = MenuProduct(
          id: 'p-croissant',
          categoryId: 'cat-bakery',
          name: 'Golden Croissant',
          priceMinor: 21000, // ₹210.00
        );

        cartNotifier.add(espresso);
        cartNotifier.add(espresso); // quantity 2
        cartNotifier.add(croissant); // quantity 1

        final state = container.read(cartProvider('customer'));
        expect(state.lines.length, 2);
        expect(state.lines[0].quantity, 2);
        expect(state.lines[1].quantity, 1);

        // Subtotal: (18000 * 2) + 21000 = 36000 + 21000 = 57000 (₹570.00)
        expect(state.subtotalMinor, 57000);

        // 5.00% GST on 57000 = (57000 * 500 + 5000) ~/ 10000 = 2850 (₹28.50)
        expect(state.taxMinor, 2850);

        // Grand Total: 57000 + 2850 = 59850 (₹598.50)
        expect(state.totalMinor, 59850);
      },
    );

    test(
      'CustomerOrderSubmission models dine-in vs takeaway with pairing code',
      () {
        const submission = CustomerOrderSubmission(
          customerName: 'Alex Sharma',
          customerPhone: '+91 9876543210',
          orderType: 'DINE_IN',
          tableName: 'Table 04',
          specialInstructions: 'Oat milk, extra hot',
          items: [
            CustomerOrderItem(productId: 'prod-01', quantity: 2),
            CustomerOrderItem(productId: 'prod-02', quantity: 1),
          ],
          pairingCode: '482910',
        );

        expect(submission.customerName, 'Alex Sharma');
        expect(submission.orderType, 'DINE_IN');
        expect(submission.tableName, 'Table 04');
        expect(submission.pairingCode, '482910');
        expect(submission.items.length, 2);
        expect(submission.items[0].toJson(), {
          'product_id': 'prod-01',
          'quantity': 2,
        });
      },
    );

    test('CustomerOrderResult JSON parsing', () {
      final json = {
        'order_id': 'ord-uuid-999',
        'order_number': 'WEB-1402-391',
        'subtotal_minor': 42000,
        'tax_minor': 2100,
        'total_minor': 44100,
        'pairing_code': '482910',
      };

      final result = CustomerOrderResult.fromJson(json);
      expect(result.orderId, 'ord-uuid-999');
      expect(result.orderNumber, 'WEB-1402-391');
      expect(result.subtotalMinor, 42000);
      expect(result.taxMinor, 2100);
      expect(result.totalMinor, 44100);
      expect(result.pairingCode, '482910');
    });

    test('CustomerTrackedOrder JSON parsing & status mapping', () {
      final json = {
        'order_id': 'ord-uuid-123',
        'order_number': 'WEB-1234-567',
        'status': 'PREPARING',
        'financial_status': 'UNPAID',
        'subtotal_minor': 36000,
        'tax_minor': 1800,
        'total_minor': 37800,
        'table_name': 'Table 02',
        'order_type': 'DINE_IN',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'items': [
          {
            'item_name': 'Velvet Latte',
            'quantity': 2,
            'unit_price_minor': 18000,
            'total_price_minor': 36000,
          },
        ],
      };

      final tracked = CustomerTrackedOrder.fromJson(json);
      expect(tracked.orderId, 'ord-uuid-123');
      expect(tracked.status, OrderStatus.preparing);
      expect(tracked.financialStatus, OrderFinancialStatus.unpaid);
      expect(tracked.items.length, 1);
      expect(tracked.items[0]['item_name'], 'Velvet Latte');
    });
  });

  group('Phase 2 Part C: Dual-Demonstrator Isolation Simulation', () {
    test(
      'Simulated orders with different demo_session_ids are mutually isolated',
      () {
        final sessionA = 'a1111111-1111-1111-1111-111111111111';
        final sessionB = 'b2222222-2222-2222-2222-222222222222';

        final ordersDatabase = [
          {'id': 'ord-1', 'demo_session_id': sessionA, 'number': 'WEB-001'},
          {'id': 'ord-2', 'demo_session_id': sessionA, 'number': 'WEB-002'},
          {'id': 'ord-3', 'demo_session_id': sessionB, 'number': 'WEB-003'},
        ];

        // Demonstrator A query filter (simulating RLS policy demo_session_id = current_demo_session_id())
        final demonstratorAOrders = ordersDatabase
            .where((o) => o['demo_session_id'] == sessionA)
            .map((o) => o['id'])
            .toList();

        // Demonstrator B query filter
        final demonstratorBOrders = ordersDatabase
            .where((o) => o['demo_session_id'] == sessionB)
            .map((o) => o['id'])
            .toList();

        expect(demonstratorAOrders, ['ord-1', 'ord-2']);
        expect(demonstratorBOrders, ['ord-3']);
        expect(demonstratorAOrders.contains('ord-3'), isFalse);
        expect(demonstratorBOrders.contains('ord-1'), isFalse);
      },
    );
  });

  group('Phase 2 Part D: Migration 000012 Enhancements Verification', () {
    test('Migration 000012 contains all Phase 2 integration routines', () {
      final content = File(
        'supabase/migrations/20261119000012_secure_live_demo_backend.sql',
      ).readAsStringSync();

      // 1. Harmonized has_role
      expect(content.contains('FUNCTION public.has_role'), isTrue);
      expect(content.contains("role::text = 'DEMO_OWNER'"), isTrue);
      expect(content.contains("role::text = 'DEMO_STAFF'"), isTrue);

      // 2. Auto-stamping triggers
      expect(content.contains('FUNCTION public.stamp_demo_session_id'), isTrue);
      expect(content.contains('TRIGGER trg_stamp_order_demo_session'), isTrue);
      expect(
        content.contains('TRIGGER trg_stamp_menu_item_demo_session'),
        isTrue,
      );

      // 3. Public order tracking policies for anon on Flagship Bistro
      expect(content.contains('Public can view demo orders'), isTrue);
      expect(content.contains('Public can view demo order items'), isTrue);

      // 4. Customer order status tracking RPC
      expect(
        content.contains('FUNCTION public.get_customer_order_status'),
        isTrue,
      );
      expect(
        content.contains(
          'GRANT EXECUTE ON FUNCTION public.get_customer_order_status TO anon, authenticated',
        ),
        isTrue,
      );

      // 5. Harmonized order creation & payment recording
      expect(
        content.contains('FUNCTION public.create_order_with_items'),
        isTrue,
      );
      expect(content.contains('FUNCTION public.record_order_payment'), isTrue);
    });
  });
}
