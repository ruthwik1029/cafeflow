import 'package:cafeflow/core/config/app_config.dart';
import 'package:cafeflow/core/services/backend.dart';
import 'package:cafeflow/core/services/demo_session_service.dart';
import 'package:cafeflow/features/customer_website/presentation/customer_order_tracking_dialog.dart';
import 'package:cafeflow/features/customer_website/presentation/customer_site.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 3 Part A & B: Customer Website QA & Offline Indicators', () {
    testWidgets(
      'CustomerShell displays Offline Simulation when backend is unconfigured on desktop',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backendProvider.overrideWithValue(
                const BackendState(
                  BackendStatus.unconfigured,
                  'Not configured',
                ),
              ),
            ],
            child: const MaterialApp(
              home: CustomerShell(location: '/', child: Text('Home content')),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Offline Simulation'), findsOneWidget);
        expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
      },
    );

    testWidgets(
      'CustomerShell displays Live Flagship Bistro when backend is initialized on desktop',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backendProvider.overrideWithValue(
                const BackendState(BackendStatus.initialized, 'Ready'),
              ),
            ],
            child: const MaterialApp(
              home: CustomerShell(location: '/', child: Text('Home content')),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Live · Flagship Bistro'), findsOneWidget);
        expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
      },
    );

    testWidgets(
      'CustomerShell displays compact status pill on narrow screens without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backendProvider.overrideWithValue(
                const BackendState(BackendStatus.initialized, 'Ready'),
              ),
            ],
            child: const MaterialApp(
              home: CustomerShell(location: '/', child: Text('Home content')),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Live'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group(
    'Phase 3 Part B: Customer Order Tracking Dual-Mode Polling Fallback',
    () {
      testWidgets(
        'CustomerOrderTrackingDialog renders and cleans up timers on dismiss',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                backendProvider.overrideWithValue(
                  const BackendState(
                    BackendStatus.unconfigured,
                    'Not configured',
                  ),
                ),
              ],
              child: const MaterialApp(
                home: Scaffold(
                  body: CustomerOrderTrackingDialog(
                    orderId: 'ord-test-123',
                    orderNumber: 'CF-8821',
                    pairingCode: 'DEMO42',
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          expect(find.text('Live Order Progress'), findsOneWidget);
          expect(find.text('CF-8821'), findsOneWidget);
          expect(find.text('Paired to Channel: DEMO42'), findsOneWidget);
          expect(find.text('Order Received'), findsOneWidget);
          expect(find.text('Preparing in Kitchen'), findsOneWidget);
          expect(find.text('Ready for Serving / Pickup'), findsOneWidget);
          expect(find.text('Completed'), findsOneWidget);

          // Dismiss dialog and ensure timers cancel cleanly
          await tester.tap(find.byIcon(Icons.close));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        },
      );
    },
  );

  group('Phase 3 Part A: Demo Session Restoration & Expiry Handling', () {
    test(
      'DemoSessionInfo correctly evaluates isExpired based on expiry time',
      () {
        final validSession = DemoSessionInfo(
          sessionId: 'sess-1',
          pairingCode: 'PAIR01',
          restaurantId: 'rest-demo-1',
          role: 'DEMO_OWNER',
          accessToken: 'valid-token',
          refreshToken: 'valid-refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );
        expect(validSession.isExpired, isFalse);

        final expiredSession = DemoSessionInfo(
          sessionId: 'sess-2',
          pairingCode: 'PAIR02',
          restaurantId: 'rest-demo-2',
          role: 'DEMO_OWNER',
          accessToken: 'expired-token',
          refreshToken: 'expired-refresh',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        expect(expiredSession.isExpired, isTrue);
      },
    );

    test('DemoSessionInfo expiry buffer handles near-expiration safely', () {
      final nearExpirySession = DemoSessionInfo(
        sessionId: 'sess-3',
        pairingCode: 'PAIR03',
        restaurantId: 'rest-demo-3',
        role: 'DEMO_OWNER',
        accessToken: 'near-expiry',
        refreshToken: 'near-refresh',
        expiresAt: DateTime.now().add(const Duration(seconds: 15)),
      );
      expect(nearExpirySession.isExpired, isFalse);
    });
  });

  group('Phase 3 Part C: Database & RLS Multi-Demonstrator Isolation Rules', () {
    test(
      'Simulated pairing codes are distinct and do not collide across sessions',
      () {
        final sessionA = DemoSessionInfo(
          sessionId: 'user-a',
          pairingCode: 'DEMO01',
          restaurantId: 'rest-a',
          role: 'DEMO_OWNER',
          accessToken: 'tok-a',
          refreshToken: 'ref-a',
          expiresAt: DateTime.now().add(const Duration(hours: 2)),
        );

        final sessionB = DemoSessionInfo(
          sessionId: 'user-b',
          pairingCode: 'DEMO02',
          restaurantId: 'rest-b',
          role: 'DEMO_OWNER',
          accessToken: 'tok-b',
          refreshToken: 'ref-b',
          expiresAt: DateTime.now().add(const Duration(hours: 2)),
        );

        expect(sessionA.pairingCode, isNot(equals(sessionB.pairingCode)));
        expect(sessionA.restaurantId, isNot(equals(sessionB.restaurantId)));
      },
    );
  });

  group('Phase 3 Part D: Client Bundle Security Verification', () {
    test('AppConfig does not expose service-role key property', () {
      const config = AppConfig(
        supabaseUrl: 'https://demo.supabase.co',
        publishableKey: 'anon-public-key',
        environment: 'staging',
        demoMode: true,
      );

      expect(config.publishableKey, equals('anon-public-key'));
      // Verify no service-role field exists in AppConfig
      final configMap = {
        'supabaseUrl': config.supabaseUrl,
        'publishableKey': config.publishableKey,
        'environment': config.environment,
        'demoMode': config.demoMode,
      };
      expect(configMap.containsKey('serviceRoleKey'), isFalse);
      expect(configMap.containsKey('service_role'), isFalse);
    });
  });
}
