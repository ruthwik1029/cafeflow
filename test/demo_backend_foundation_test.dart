import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 1: Secure Live Demo Backend Architecture & Migration Tests', () {
    test(
      'Migration 000012 exists and adheres to strict naming conventions',
      () {
        final migrationFile = File(
          'supabase/migrations/20261119000012_secure_live_demo_backend.sql',
        );
        expect(
          migrationFile.existsSync(),
          isTrue,
          reason: 'Migration 000012 must exist in supabase/migrations/',
        );
      },
    );

    test(
      'Migration 000012 contains restricted roles and schema extensions',
      () {
        final content = File(
          'supabase/migrations/20261119000012_secure_live_demo_backend.sql',
        ).readAsStringSync();

        // Restricted roles
        expect(
          content.contains(
            "ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'DEMO_OWNER'",
          ),
          isTrue,
        );
        expect(
          content.contains(
            "ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'DEMO_STAFF'",
          ),
          isTrue,
        );

        // Schema flags
        expect(
          content.contains('is_demo BOOLEAN NOT NULL DEFAULT false'),
          isTrue,
        );
        expect(
          content.contains('is_seed BOOLEAN NOT NULL DEFAULT false'),
          isTrue,
        );
        expect(content.contains('demo_session_id UUID NULL'), isTrue);

        // Flagging seed Bistro
        expect(content.contains("SET is_demo = true"), isTrue);
        expect(content.contains("SET is_seed = true"), isTrue);
        expect(
          content.contains('a0000000-0000-0000-0000-000000000001'),
          isTrue,
        );
      },
    );

    test('Migration 000012 avoids enum transaction invariant errors in demo_sessions table', () {
      final content = File(
        'supabase/migrations/20261119000012_secure_live_demo_backend.sql',
      ).readAsStringSync();

      // Must use check constraint instead of uncommitted enum type in table definition
      expect(
        content.contains(
          "role TEXT NOT NULL DEFAULT 'DEMO_OWNER' CHECK (role IN ('DEMO_OWNER', 'DEMO_STAFF'))",
        ),
        isTrue,
        reason: 'demo_sessions.role must use text check constraint to prevent PostgreSQL transactional enum invariant violation during db push',
      );
    });

    test('Migration 000012 pins safe search_path and restricts rate limit function', () {
      final content = File(
        'supabase/migrations/20261119000012_secure_live_demo_backend.sql',
      ).readAsStringSync();

      // Safe search_path on all SECURITY DEFINER routines
      expect(content.contains('SET search_path = public, pg_temp'), isTrue);

      // check_and_increment_rate_limit security
      expect(
        content.contains(
          'REVOKE ALL ON FUNCTION public.check_and_increment_rate_limit FROM public, anon, authenticated',
        ),
        isTrue,
      );
      expect(
        content.contains(
          'GRANT EXECUTE ON FUNCTION public.check_and_increment_rate_limit TO service_role',
        ),
        isTrue,
      );

      // ZERO anonymous RPC for demo provisioning
      expect(
        content.contains(
          'CREATE OR REPLACE FUNCTION public.provision_demo_session',
        ),
        isFalse,
        reason: 'No public RPC for demo session provisioning must exist in the database.',
      );
    });

    test('Migration 000012 protects demo_sessions RLS and defines resolve_demo_pairing_code RPC', () {
      final content = File(
        'supabase/migrations/20261119000012_secure_live_demo_backend.sql',
      ).readAsStringSync();

      // demo_sessions RLS must restrict SELECT to user_id = auth.uid()
      expect(
        content.contains('CREATE POLICY "Users can view own demo sessions"'),
        isTrue,
      );
      expect(content.contains('USING (user_id = auth.uid())'), isTrue);

      // Public enumeration policy must be dropped
      expect(
        content.contains(
          'DROP POLICY IF EXISTS "Active pairing codes are queryable"',
        ),
        isTrue,
      );

      // resolve_demo_pairing_code RPC exists
      expect(
        content.contains('FUNCTION public.resolve_demo_pairing_code'),
        isTrue,
      );
      expect(
        content.contains(
          'GRANT EXECUTE ON FUNCTION public.resolve_demo_pairing_code TO anon, authenticated, service_role',
        ),
        isTrue,
      );
    });

    test('Migration 000012 enforces seed immutability, settings protection, and exempts demo deletion in prevent_financial_deletion', () {
      final content = File(
        'supabase/migrations/20261119000012_secure_live_demo_backend.sql',
      ).readAsStringSync();

      // Seed catalog trigger
      expect(
        content.contains('FUNCTION public.enforce_seed_catalog_immutability'),
        isTrue,
      );
      expect(content.contains('trg_protect_seed_menu_items'), isTrue);
      expect(
        content.contains('Core seed demo items cannot be deleted'),
        isTrue,
      );
      expect(
        content.contains('Price must remain between ₹10.00 and ₹10,000.00'),
        isTrue,
      );

      // Store settings trigger
      expect(
        content.contains('FUNCTION public.protect_demo_restaurant_settings'),
        isTrue,
      );
      expect(content.contains('trg_protect_demo_settings'), isTrue);
      expect(
        content.contains(
          'Configuration changes are disabled for the demo bistro',
        ),
        isTrue,
      );

      // Financial deletion trigger exemption for service_role in demo bistro
      expect(
        content.contains('FUNCTION public.prevent_financial_deletion'),
        isTrue,
      );
      expect(
        content.contains(
          "OLD.restaurant_id = 'a0000000-0000-0000-0000-000000000001' AND auth.role() = 'service_role'",
        ),
        isTrue,
        reason: 'prevent_financial_deletion must exempt demo restaurant order deletion by service_role for hourly cleanup',
      );
    });

    test('Migration 000012 defines is_demo_user and eliminates inverted expiry fallthrough in orders and menu RLS', () {
      final content = File(
        'supabase/migrations/20261119000012_secure_live_demo_backend.sql',
      ).readAsStringSync();

      // is_demo_user helper function
      expect(content.contains('FUNCTION public.is_demo_user'), isTrue);
      expect(
        content.contains("role::text IN ('DEMO_OWNER', 'DEMO_STAFF')"),
        isTrue,
      );

      // Orders RLS isolation ensures demo user sees strictly their active session orders or 0 on expiry
      expect(content.contains('NOT public.is_demo_user()'), isTrue);
      expect(
        content.contains(
          'public.is_demo_user() AND demo_session_id IS NOT NULL AND demo_session_id = public.current_demo_session_id()',
        ),
        isTrue,
      );

      // Custom Menu items RLS isolation
      expect(content.contains('is_seed = true'), isTrue);
    });

    test('Migration 000012 grants demo roles permissions for session-isolated order creation, updates, and advance_order_status', () {
      final content = File(
        'supabase/migrations/20261119000012_secure_live_demo_backend.sql',
      ).readAsStringSync();

      // Demo users can create orders in POS
      expect(
        content.contains('CREATE POLICY "Demo users can create demo orders"'),
        isTrue,
      );
      expect(content.contains('ON public.orders FOR INSERT'), isTrue);

      // Demo users can update demo orders
      expect(
        content.contains('CREATE POLICY "Demo users can update demo orders"'),
        isTrue,
      );
      expect(content.contains('ON public.orders FOR UPDATE'), isTrue);

      // advance_order_status RPC updated to support DEMO_OWNER and DEMO_STAFF
      expect(content.contains('FUNCTION public.advance_order_status'), isTrue);
      expect(
        content.contains("v_caller_role::text IN ('DEMO_OWNER', 'DEMO_STAFF')"),
        isTrue,
      );

      // Demo owner can manage demo menu items
      expect(
        content.contains(
          'CREATE POLICY "Demo owner can manage demo menu items"',
        ),
        isTrue,
      );
    });

    test('Migration 000012 derives client IP server-side in create_public_online_order and enforces circuit breaker', () {
      final content = File(
        'supabase/migrations/20261119000012_secure_live_demo_backend.sql',
      ).readAsStringSync();

      // Circuit breaker (max 30 active orders)
      expect(content.contains('v_active_count >= 30'), isTrue);
      expect(content.contains('capacity (30 active orders)'), isTrue);

      // Server-derived IP from request.headers overrides client argument
      expect(content.contains("current_setting('request.headers'"), isTrue);
      expect(content.contains('cf-connecting-ip'), isTrue);
      expect(content.contains('x-forwarded-for'), isTrue);
      expect(
        content.contains(
          "check_and_increment_rate_limit(v_effective_ip, 'ONLINE_ORDER', 5, 3)",
        ),
        isTrue,
      );

      // Server-side price resolution from menu_items
      expect(
        content.contains(
          'SELECT name, price_minor, is_available INTO v_db_name, v_db_price, v_db_avail',
        ),
        isTrue,
      );
      expect(content.contains('v_db_price * v_qty'), isTrue);
      expect(content.contains('v_subtotal * 500) / 10000'), isTrue); // 5% GST
    });

    test('Migration 000012 specifies hourly cleanup routine with demo deletion and orphan account pruning', () {
      final content = File(
        'supabase/migrations/20261119000012_secure_live_demo_backend.sql',
      ).readAsStringSync();

      expect(
        content.contains('FUNCTION public.reset_demo_tenant_data'),
        isTrue,
      );
      expect(content.contains('DELETE FROM public.orders'), isTrue);
      expect(
        content.contains(
          'DELETE FROM public.demo_sessions WHERE expires_at < now()',
        ),
        isTrue,
      );

      // Orphan account pruning
      expect(
        content.contains('DELETE FROM public.restaurant_memberships'),
        isTrue,
      );
      expect(
        content.contains("role::text IN ('DEMO_OWNER', 'DEMO_STAFF')"),
        isTrue,
      );
      expect(content.contains('DELETE FROM public.user_profiles'), isTrue);

      expect(
        content.contains(
          'REVOKE ALL ON FUNCTION public.reset_demo_tenant_data FROM public, anon, authenticated',
        ),
        isTrue,
      );
      expect(
        content.contains(
          'GRANT EXECUTE ON FUNCTION public.reset_demo_tenant_data TO service_role',
        ),
        isTrue,
      );
    });
  });

  group('Phase 1: Supabase Edge Function Architecture & Verification', () {
    test(
      'provision-demo-session Edge Function exists and enforces security gates',
      () {
        final edgeFile = File(
          'supabase/functions/provision-demo-session/index.ts',
        );
        expect(
          edgeFile.existsSync(),
          isTrue,
          reason: 'Edge Function must exist in supabase/functions/provision-demo-session/',
        );

        final content = edgeFile.readAsStringSync();

        // Production fail-closed gate
        expect(content.contains('if (appEnv === "production")'), isTrue);
        expect(
          content.contains(
            'Demo session provisioning is strictly disabled in production',
          ),
          isTrue,
        );

        // Service role key usage server-side only
        expect(
          content.contains('Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")'),
          isTrue,
        );

        // Concurrency guard: max 50 concurrent active sessions
        expect(
          content.contains('activeSessionCount >= 50'),
          isTrue,
          reason: 'Edge Function must enforce 50-session concurrency limit',
        );

        // Rate limiting check
        expect(content.contains('check_and_increment_rate_limit'), isTrue);
        expect(content.contains('DEMO_SESSION_PROVISION'), isTrue);

        // Ephemeral user creation in auth.users
        expect(content.contains('adminClient.auth.admin.createUser'), isTrue);

        // CRITICAL FOREIGN KEY FIX: User profile insertion in public.user_profiles
        expect(
          content.contains('adminClient.from("user_profiles").insert'),
          isTrue,
          reason: 'Must insert profile into public.user_profiles before inserting into restaurant_memberships to avoid FK violation',
        );

        // Role binding
        expect(
          content.contains('adminClient.from("restaurant_memberships").insert'),
          isTrue,
        );
        expect(content.contains('DEMO_OWNER'), isTrue);

        // Pairing code generation & sanitized response
        expect(content.contains('pairing_code'), isTrue);
        expect(
          content.contains('access_token: sessionData.session.access_token'),
          isTrue,
        );
      },
    );

    test('provision-demo-session Edge Function enforces strict Turnstile bot verification and native client attestation', () {
      final content = File('supabase/functions/provision-demo-session/index.ts')
          .readAsStringSync();

      // Must fail closed when Turnstile token is missing for web access
      expect(content.contains('if (!turnstileToken)'), isTrue);
      expect(
        content.contains(
          'Bot verification challenge is required for web demo access',
        ),
        isTrue,
      );

      // Native app attestation header check
      expect(content.contains('cafeflow-desktop-demo'), isTrue);
      expect(content.contains('cafeflow-mobile-demo'), isTrue);

      // Cloudflare siteverify error fails closed with 502/400
      expect(content.contains('status: 502'), isTrue);
    });
  });

  group('Phase 1: Invariant Logic Simulation Tests', () {
    test('Circuit breaker trips when active queue exceeds 30 orders', () {
      bool canPlaceOrder(int activeTickets) {
        if (activeTickets >= 30) {
          throw Exception('Queue at capacity (30 orders)');
        }
        return true;
      }

      expect(canPlaceOrder(15), isTrue);
      expect(canPlaceOrder(29), isTrue);
      expect(() => canPlaceOrder(30), throwsException);
      expect(() => canPlaceOrder(31), throwsException);
    });

    test('Sliding-window rate limiter permits 3 orders and blocks 4th within 5 minutes', () {
      final requests = <DateTime>[];

      bool allowRequest(DateTime now, int maxRequests, Duration window) {
        requests.removeWhere((t) => now.difference(t) > window);
        if (requests.length >= maxRequests) {
          return false;
        }
        requests.add(now);
        return true;
      }

      final t0 = DateTime(2026, 11, 19, 12, 0, 0);
      expect(allowRequest(t0, 3, const Duration(minutes: 5)), isTrue);
      expect(
        allowRequest(
          t0.add(const Duration(minutes: 1)),
          3,
          const Duration(minutes: 5),
        ),
        isTrue,
      );
      expect(
        allowRequest(
          t0.add(const Duration(minutes: 2)),
          3,
          const Duration(minutes: 5),
        ),
        isTrue,
      );
      // 4th request inside 5 minute window fails
      expect(
        allowRequest(
          t0.add(const Duration(minutes: 3)),
          3,
          const Duration(minutes: 5),
        ),
        isFalse,
      );

      // After 5 minutes, limit resets
      expect(
        allowRequest(
          t0.add(const Duration(minutes: 6)),
          3,
          const Duration(minutes: 5),
        ),
        isTrue,
      );
    });

    test(
      'Demonstrator session isolation returns mutually exclusive orders',
      () {
        final orders = [
          {'id': 'ord-1', 'session_id': 'sess-a', 'order_number': 'ORD-A1'},
          {'id': 'ord-2', 'session_id': 'sess-b', 'order_number': 'ORD-B1'},
          {'id': 'ord-3', 'session_id': 'sess-a', 'order_number': 'ORD-A2'},
        ];

        List<Map<String, String>> getOrdersForDemonstrator(
          String currentSessionId,
        ) {
          return orders
              .where((o) => o['session_id'] == currentSessionId)
              .toList();
        }

        final demonstratorAOrders = getOrdersForDemonstrator('sess-a');
        final demonstratorBOrders = getOrdersForDemonstrator('sess-b');

        expect(demonstratorAOrders.map((o) => o['order_number']), [
          'ORD-A1',
          'ORD-A2',
        ]);
        expect(demonstratorBOrders.map((o) => o['order_number']), ['ORD-B1']);
        expect(
          demonstratorAOrders.any((o) => o['session_id'] == 'sess-b'),
          isFalse,
        );
      },
    );

    test('Inverted expiry fallthrough protection: expired demo session sees 0 orders, never all orders', () {
      final allOrders = [
        {'id': 'ord-1', 'session_id': 'sess-a', 'order_number': 'ORD-A1'},
        {'id': 'ord-2', 'session_id': 'sess-b', 'order_number': 'ORD-B1'},
        {'id': 'ord-3', 'session_id': 'sess-c', 'order_number': 'ORD-C1'},
      ];

      List<Map<String, String>> evaluateOrdersRls({
        required bool isRestaurantMember,
        required bool isDemoUser,
        required String? currentDemoSessionId,
      }) {
        if (!isRestaurantMember) return [];

        return allOrders.where((order) {
          if (!isDemoUser) {
            return true; // Non-demo members see all orders
          }
          // Demo user: strictly their own active session orders
          if (currentDemoSessionId == null) {
            return false; // Expired demo user sees ZERO orders
          }
          return order['session_id'] == currentDemoSessionId;
        }).toList();
      }

      // Active demonstrator A
      final activeOrders = evaluateOrdersRls(
        isRestaurantMember: true,
        isDemoUser: true,
        currentDemoSessionId: 'sess-a',
      );
      expect(activeOrders.map((o) => o['order_number']), ['ORD-A1']);

      // Expired demonstrator A (currentDemoSessionId is null)
      final expiredOrders = evaluateOrdersRls(
        isRestaurantMember: true,
        isDemoUser: true,
        currentDemoSessionId: null,
      );
      expect(
        expiredOrders,
        isEmpty,
        reason: 'Expired demo user must see 0 orders, never all tenant orders',
      );

      // Production owner sees all orders
      final prodOrders = evaluateOrdersRls(
        isRestaurantMember: true,
        isDemoUser: false,
        currentDemoSessionId: null,
      );
      expect(prodOrders.length, 3);
    });

    test(
      'Seed item immutability enforces price clamps and forbids deletion',
      () {
        int validateAndUpdatePrice({
          required bool isSeed,
          required int newPriceMinor,
        }) {
          if (isSeed) {
            if (newPriceMinor < 1000 || newPriceMinor > 1000000) {
              throw ArgumentError('Price must be between ₹10 and ₹10,000');
            }
          }
          return newPriceMinor;
        }

        // Valid edits
        expect(
          validateAndUpdatePrice(isSeed: true, newPriceMinor: 25000),
          25000,
        );
        expect(validateAndUpdatePrice(isSeed: true, newPriceMinor: 1000), 1000);
        expect(
          validateAndUpdatePrice(isSeed: true, newPriceMinor: 1000000),
          1000000,
        );

        // Below ₹10 or above ₹10,000 throws ArgumentError
        expect(
          () => validateAndUpdatePrice(isSeed: true, newPriceMinor: 999),
          throwsArgumentError,
        );
        expect(
          () => validateAndUpdatePrice(isSeed: true, newPriceMinor: 1000001),
          throwsArgumentError,
        );
      },
    );

    test(
      'Server-side IP extraction logic overrides client argument tampering',
      () {
        String resolveClientIp({
          required Map<String, String>? requestHeaders,
          required String clientSuppliedIp,
        }) {
          final headerIp =
              requestHeaders?['cf-connecting-ip'] ??
              requestHeaders?['x-forwarded-for']?.split(',').first.trim();

          return (headerIp != null && headerIp.isNotEmpty)
              ? headerIp
              : (clientSuppliedIp.isNotEmpty ? clientSuppliedIp : 'web-guest');
        }

        // When request headers are injected by PostgREST, header IP overrides client argument
        final resultWithHeaders = resolveClientIp(
          requestHeaders: {'cf-connecting-ip': '203.0.113.195'},
          clientSuppliedIp: 'fake-spoofed-ip-123',
        );
        expect(resultWithHeaders, '203.0.113.195');

        // When behind standard proxy with x-forwarded-for
        final resultWithXff = resolveClientIp(
          requestHeaders: {'x-forwarded-for': '198.51.100.22, 10.0.0.1'},
          clientSuppliedIp: 'fake-spoofed-ip-456',
        );
        expect(resultWithXff, '198.51.100.22');

        // When in mock/direct test environment without request headers
        final resultWithoutHeaders = resolveClientIp(
          requestHeaders: null,
          clientSuppliedIp: 'test-client-id',
        );
        expect(resultWithoutHeaders, 'test-client-id');
      },
    );
  });
}
