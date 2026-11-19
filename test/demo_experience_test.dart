import 'package:cafeflow/core/bootstrap/bootstrap.dart';
import 'package:cafeflow/core/routing/internal_router.dart';
import 'package:cafeflow/core/routing/workspace.dart';
import 'package:cafeflow/core/services/backend.dart';
import 'package:cafeflow/core/theme/theme_controller.dart';
import 'package:cafeflow/features/auth/application/auth_controller.dart';
import 'package:cafeflow/features/demo/application/demo_orders_controller.dart';
import 'package:cafeflow/features/orders/domain/cafe_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'theme_test.dart' show MemoryThemeStore;

const _unconfiguredBackend = BackendState(
  BackendStatus.unconfigured,
  'Backend not configured.',
);

Future<void> pumpDemoApp(
  WidgetTester tester, {
  required GoRouter router,
  required ProviderContainer container,
  Size size = const Size(1440, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    router.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: CafeFlowApp(router: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CafeFlow Password-Free Demo Mode Experience Tests', () {
    testWidgets(
      'Demo 1: Production build strictly hides Enter Demo Mode button and forces login',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
          ],
        );
        addTearDown(container.dispose);

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false, // Production
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpDemoApp(tester, router: router, container: container);

        expect(find.text('CafeFlow Workspace'), findsOneWidget);
        expect(find.text('Enter Demo Mode'), findsNothing);
        expect(find.text('Demonstration Experience'), findsNothing);
      },
    );

    testWidgets(
      'Demo 2: Demonstration build displays prominent Enter Demo Mode button',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
          ],
        );
        addTearDown(container.dispose);

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: true,
          initialLocation: '/login',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpDemoApp(tester, router: router, container: container);

        expect(find.text('Enter Demo Mode'), findsOneWidget);
        expect(find.text('Demonstration Experience'), findsOneWidget);
      },
    );

    testWidgets(
      'Demo 3: Tapping Enter Demo Mode opens Workspace Selector dialog with 3 roles',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
          ],
        );
        addTearDown(container.dispose);

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: true,
          initialLocation: '/login',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpDemoApp(tester, router: router, container: container);

        // Tap Enter Demo Mode
        await tester.tap(find.text('Enter Demo Mode'));
        await tester.pumpAndSettle();

        expect(find.text('Select Demo Workspace'), findsOneWidget);
        expect(find.text('Owner / Admin'), findsOneWidget);
        expect(find.text('Cashier / POS'), findsOneWidget);
        expect(find.text('Kitchen / KOT'), findsOneWidget);
      },
    );

    testWidgets(
      'Demo 4: Windows demonstrator selecting Owner / Admin enters Admin Dashboard',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
          ],
        );
        addTearDown(container.dispose);

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: true,
          initialLocation: '/login',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpDemoApp(tester, router: router, container: container);

        await tester.tap(find.text('Enter Demo Mode'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Owner / Admin'));
        await tester.pumpAndSettle();

        expect(
          router.routeInformationProvider.value.uri.path,
          '/admin/dashboard',
        );
        expect(find.text('DEMO MODE · OFFLINE SIMULATION'), findsOneWidget);
      },
    );

    testWidgets(
      'Demo 5: Windows demonstrator selecting Cashier / POS enters POS workspace',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
          ],
        );
        addTearDown(container.dispose);

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: true,
          initialLocation: '/login',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpDemoApp(tester, router: router, container: container);

        await tester.tap(find.text('Enter Demo Mode'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cashier / POS'));
        await tester.pumpAndSettle();

        expect(router.routeInformationProvider.value.uri.path, '/cashier/pos');
        expect(find.text('Point of sale'), findsNWidgets(2));
        expect(find.text('DEMO MODE · OFFLINE SIMULATION'), findsOneWidget);
      },
    );

    testWidgets(
      'Demo 6: Windows demonstrator selecting Kitchen / KOT enters Kitchen Display',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
          ],
        );
        addTearDown(container.dispose);

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: true,
          initialLocation: '/login',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpDemoApp(tester, router: router, container: container);

        await tester.tap(find.text('Enter Demo Mode'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Kitchen / KOT'));
        await tester.pumpAndSettle();

        expect(
          router.routeInformationProvider.value.uri.path,
          '/kitchen/display',
        );
        expect(find.text('Kitchen display'), findsNWidgets(2));
        expect(find.text('DEMO MODE · OFFLINE SIMULATION'), findsOneWidget);
      },
    );

    testWidgets(
      'Demo 7: Android demonstrator selecting Owner / Admin routes to /owner/overview',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
          ],
        );
        addTearDown(container.dispose);

        final router = createInternalRouter(
          target: InternalTarget.android,
          demoEnabled: true,
          initialLocation: '/login',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpDemoApp(
          tester,
          router: router,
          container: container,
          size: const Size(412, 915),
        );

        await tester.ensureVisible(find.text('Enter Demo Mode'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Enter Demo Mode'));
        await tester.pumpAndSettle();

        // Verify badge indicates Mobile Overview
        expect(find.text('Mobile Overview'), findsOneWidget);

        await tester.tap(find.text('Owner / Admin'));
        await tester.pumpAndSettle();

        expect(
          router.routeInformationProvider.value.uri.path,
          '/owner/overview',
        );
        expect(
          find.text('Stay close.\nWherever the day takes you.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Demo 8: Demonstrator can switch roles from workspace sidebar without logging out',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
          ],
        );
        addTearDown(container.dispose);

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: true,
          initialLocation: '/admin/dashboard',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpDemoApp(tester, router: router, container: container);
        expect(
          router.routeInformationProvider.value.uri.path,
          '/admin/dashboard',
        );

        // Tap Switch workspace in the sidebar
        await tester.tap(find.text('Switch workspace'));
        await tester.pumpAndSettle();

        // Switch to Cashier
        await tester.tap(find.text('Cashier').last);
        await tester.pumpAndSettle();

        expect(router.routeInformationProvider.value.uri.path, '/cashier/pos');
      },
    );

    testWidgets(
      'Demo 9: Demo POS orders mutate in-memory demo controller only and do not touch Supabase',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
          ],
        );
        addTearDown(container.dispose);

        final initialDemoOrdersCount = container
            .read(demoOrdersProvider)
            .length;

        // Add an order through the demo controller
        final newOrder = container
            .read(demoOrdersProvider.notifier)
            .add(
              lines: const [
                OrderLine(
                  productId: 'latte',
                  name: 'Velvet latte',
                  unitMinor: 22000,
                  quantity: 2,
                ),
              ],
              table: 'Table 03',
              instructions: 'Extra hot',
              taxMinor: 2200,
              discountMinor: 0,
            );

        final updatedOrders = container.read(demoOrdersProvider);
        expect(updatedOrders.length, initialDemoOrdersCount + 1);
        expect(updatedOrders.first.id, newOrder.id);
        expect(updatedOrders.first.table, 'Table 03');
      },
    );

    testWidgets(
      'Demo 10: Kitchen ticket status advance operates purely in memory',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
          ],
        );
        addTearDown(container.dispose);

        final newOrder = container
            .read(demoOrdersProvider.notifier)
            .add(
              lines: const [
                OrderLine(
                  productId: 'croissant',
                  name: 'Butter croissant',
                  unitMinor: 18000,
                  quantity: 1,
                ),
              ],
              table: 'Table 01',
              instructions: '',
              taxMinor: 0,
              discountMinor: 0,
            );

        expect(newOrder.status, OrderStatus.newOrder);

        // Advance to preparing
        container.read(demoOrdersProvider.notifier).advance(newOrder.id);
        final preparingOrder = container
            .read(demoOrdersProvider)
            .firstWhere((o) => o.id == newOrder.id);
        expect(preparingOrder.status, OrderStatus.preparing);

        // Advance to ready
        container.read(demoOrdersProvider.notifier).advance(newOrder.id);
        final readyOrder = container
            .read(demoOrdersProvider)
            .firstWhere((o) => o.id == newOrder.id);
        expect(readyOrder.status, OrderStatus.ready);
      },
    );
  });
}
