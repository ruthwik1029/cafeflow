import 'package:cafeflow/core/bootstrap/bootstrap.dart';
import 'package:cafeflow/core/routing/internal_router.dart';
import 'package:cafeflow/core/routing/workspace.dart';
import 'package:cafeflow/core/theme/theme_controller.dart';
import 'package:cafeflow/features/auth/application/auth_controller.dart';
import 'package:cafeflow/features/auth/domain/auth_user.dart';
import 'package:cafeflow/features/customer_website/presentation/customer_router.dart';
import 'package:cafeflow/features/workspaces/domain/workspace_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'theme_test.dart' show MemoryThemeStore;

Future<void> mount(
  WidgetTester tester,
  GoRouter router, {
  Size size = const Size(1440, 1000),
  String theme = 'light',
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    router.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        themeStoreProvider.overrideWithValue(MemoryThemeStore(theme)),
      ],
      child: CafeFlowApp(router: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('rolesFor returns expected roles for windows and android targets', () {
    expect(rolesFor(InternalTarget.windows), const [
      WorkspaceRole.admin,
      WorkspaceRole.owner,
      WorkspaceRole.cashier,
      WorkspaceRole.kitchen,
    ]);
    expect(rolesFor(InternalTarget.android), const [
      WorkspaceRole.owner,
      WorkspaceRole.staff,
    ]);
  });

  for (final theme in ['light', 'dark']) {
    for (final role in WorkspaceRole.values) {
      testWidgets('$role renders $theme at narrow width with large text', (
        tester,
      ) async {
        final target = [WorkspaceRole.staff].contains(role)
            ? InternalTarget.android
            : InternalTarget.windows;
        await mount(
          tester,
          createInternalRouter(
            target: target,
            demoEnabled: true,
            initialLocation: workspaceFor(role).home,
          ),
          size: const Size(320, 700),
          theme: theme,
          scale: 1.8,
        );
        expect(tester.takeException(), isNull);
        expect(find.text(workspaceFor(role).headline), findsOneWidget);
      });
    }
  }
  testWidgets('desktop navigation opens module and role-specific workspace', (
    tester,
  ) async {
    final router = createInternalRouter(
      target: InternalTarget.windows,
      demoEnabled: true,
    );
    await mount(tester, router);
    await tester.tap(find.text('Menu management').first);
    await tester.pumpAndSettle();
    expect(find.text('Menu management starts here'), findsOneWidget);
    await tester.tap(find.text('Switch workspace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen / KOT').last);
    await tester.pumpAndSettle();
    expect(find.text('Every order.\nA clear next step.'), findsOneWidget);
    await tester.tap(find.text('Switch workspace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Owner').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Stay close.\nWherever the day takes you.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Windows router registers and renders Owner workspace at /owner/overview',
    (tester) async {
      final router = createInternalRouter(
        target: InternalTarget.windows,
        demoEnabled: true,
        initialLocation: '/owner/overview',
      );
      await mount(tester, router);
      expect(
        find.text('Stay close.\nWherever the day takes you.'),
        findsOneWidget,
      );
      expect(find.text('Sales overview'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Windows Owner login resolves to Owner overview route', (
    tester,
  ) async {
    const ownerAuth = AuthState(
      status: AuthStatus.authenticated,
      user: CafeUser(
        id: '00000000-0000-0000-0000-000000000001',
        email: 'owner@cafeflow.com',
        fullName: 'Bistro Owner',
      ),
      activeMembership: RestaurantMembershipInfo(
        restaurantId: '00000000-0000-0000-0000-000000000003',
        restaurantName: 'Flagship Bistro',
        role: WorkspaceRole.owner,
      ),
    );
    final router = createInternalRouter(
      target: InternalTarget.windows,
      demoEnabled: true,
      initialLocation: '/login',
      getAuthState: () => ownerAuth,
    );
    await mount(tester, router);
    expect(
      find.text('Stay close.\nWherever the day takes you.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Windows rejects staff routes while Android allows Owner and Staff',
    (tester) async {
      await mount(
        tester,
        createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: true,
          initialLocation: '/staff/tables',
        ),
      );
      expect(find.text('Workspace not available'), findsOneWidget);

      await mount(
        tester,
        createInternalRouter(
          target: InternalTarget.android,
          demoEnabled: true,
          initialLocation: '/owner/overview',
        ),
      );
      expect(
        find.text('Stay close.\nWherever the day takes you.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('Android rejects desktop routes', (tester) async {
    await mount(
      tester,
      createInternalRouter(
        target: InternalTarget.android,
        demoEnabled: true,
        initialLocation: '/admin/dashboard',
      ),
    );
    expect(find.text('Workspace not available'), findsOneWidget);
  });
  testWidgets('disabled demo does not expose workspace screens', (
    tester,
  ) async {
    await mount(
      tester,
      createInternalRouter(target: InternalTarget.windows, demoEnabled: false),
    );
    expect(find.text('CafeFlow Workspace'), findsOneWidget);
    expect(find.text('Workspace access is not enabled'), findsNothing);
  });
  testWidgets('public router rejects every internal role and design system', (
    tester,
  ) async {
    final router = createCustomerRouter(initialLocation: '/');
    await mount(tester, router);
    expect(find.text('Good coffee.\nGreat company.'), findsOneWidget);
    for (final workspace in workspaceCatalog) {
      router.go(workspace.home);
      await tester.pumpAndSettle();
      expect(find.text('This page is not on the menu'), findsOneWidget);
      expect(find.text('Switch workspace'), findsNothing);
    }
    router.go('/admin/design-system');
    await tester.pumpAndSettle();
    expect(find.text('This page is not on the menu'), findsOneWidget);
  });
  testWidgets(
    'public site is responsive and theme switches without restarting',
    (tester) async {
      await mount(
        tester,
        createCustomerRouter(initialLocation: '/'),
        size: const Size(390, 844),
      );
      await tester.tap(find.byTooltip('Change theme'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is CheckedPopupMenuItem<ThemeMode> &&
              widget.value == ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.text('Good coffee.\nGreat company.'));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(tester.takeException(), isNull);
    },
  );
}
