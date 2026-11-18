import 'dart:async';

import 'package:cafeflow/core/bootstrap/bootstrap.dart';
import 'package:cafeflow/core/routing/internal_router.dart';
import 'package:cafeflow/core/routing/workspace.dart';
import 'package:cafeflow/core/services/backend.dart';
import 'package:cafeflow/core/theme/theme_controller.dart';
import 'package:cafeflow/features/auth/application/auth_controller.dart';
import 'package:cafeflow/features/auth/data/supabase_auth_repository.dart';
import 'package:cafeflow/features/auth/domain/auth_repository.dart';
import 'package:cafeflow/features/auth/domain/auth_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'theme_test.dart' show MemoryThemeStore;

const _unconfiguredBackend = BackendState(
  BackendStatus.unconfigured,
  'Backend not configured.',
);

class TestAuthRepository implements AuthRepository {
  TestAuthRepository({this.currentUser, this.restoringCompleter});

  @override
  CafeUser? currentUser;
  Completer<CafeUser?>? restoringCompleter;
  bool logoutCalled = false;

  @override
  Stream<CafeUser?> watchAuthState() => Stream.value(currentUser);

  @override
  Future<CafeUser?> restoreSession() async {
    if (restoringCompleter != null) {
      return restoringCompleter!.future;
    }
    return currentUser;
  }

  @override
  Future<CafeUser> loginWithEmail(String email, String password) async {
    return currentUser ??
        CafeUser(
          id: 'user-owner-1',
          email: email,
          fullName: 'Test Owner',
          memberships: const [
            RestaurantMembershipInfo(
              restaurantId: 'rest-001',
              restaurantName: 'Test Cafe',
              role: WorkspaceRole.owner,
            ),
          ],
        );
  }

  @override
  Future<CafeUser> loginWithUsername(String username, String password) async {
    return loginWithEmail('$username@cafeflow.internal', password);
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
    currentUser = null;
  }
}

CafeUser createTestUser(
  WorkspaceRole role, {
  String email = 'user@cafeflow.internal',
}) {
  return CafeUser(
    id: 'user-${role.name}',
    email: email,
    fullName: 'Test ${role.name.toUpperCase()}',
    memberships: [
      RestaurantMembershipInfo(
        restaurantId: 'rest-001',
        restaurantName: 'Downtown Cafe',
        role: role,
      ),
    ],
  );
}

Future<void> pumpRouterApp(
  WidgetTester tester, {
  required GoRouter router,
  required ProviderContainer container,
  Size size = const Size(1440, 1000),
  bool settle = true,
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
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  group('Production Authentication Startup and Routing Hardening', () {
    testWidgets(
      'Scenario 1: Fresh unauthenticated Windows launch opens /login in production',
      (tester) async {
        final mockRepo = TestAuthRepository(currentUser: null);
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        addTearDown(container.dispose);

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false,
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpRouterApp(tester, router: router, container: container);

        expect(find.text('CafeFlow Workspace'), findsOneWidget);
        expect(find.text('Workspace access is not enabled'), findsNothing);
        expect(router.routeInformationProvider.value.uri.path, '/login');
      },
    );

    testWidgets(
      'Scenario 2: Fresh unauthenticated Android launch opens /login in production',
      (tester) async {
        final mockRepo = TestAuthRepository(currentUser: null);
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        addTearDown(container.dispose);

        final router = createInternalRouter(
          target: InternalTarget.android,
          demoEnabled: false,
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpRouterApp(
          tester,
          router: router,
          container: container,
          size: const Size(412, 915),
        );

        expect(find.text('CafeFlow Workspace'), findsOneWidget);
        expect(find.text('Workspace access is not enabled'), findsNothing);
        expect(router.routeInformationProvider.value.uri.path, '/login');
      },
    );

    testWidgets(
      'Scenario 3: Authenticated Owner can access the Owner workspace (/owner/overview)',
      (tester) async {
        final ownerUser = createTestUser(WorkspaceRole.owner);
        final mockRepo = TestAuthRepository(currentUser: ownerUser);
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        addTearDown(container.dispose);

        // Pre-initialize auth to authenticated state
        await container.read(authControllerProvider.notifier).init();

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false,
          initialLocation: '/owner/overview',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpRouterApp(tester, router: router, container: container);

        expect(
          router.routeInformationProvider.value.uri.path,
          '/owner/overview',
        );
        expect(
          find.text('Stay close.\nWherever the day takes you.'),
          findsOneWidget,
        );
        expect(find.text('CafeFlow Workspace'), findsNothing);
      },
    );

    testWidgets(
      'Scenario 4: Cashier cannot access Owner-only routes and is redirected to /cashier/pos',
      (tester) async {
        final cashierUser = createTestUser(WorkspaceRole.cashier);
        final mockRepo = TestAuthRepository(currentUser: cashierUser);
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        addTearDown(container.dispose);

        await container.read(authControllerProvider.notifier).init();

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false,
          initialLocation: '/cashier/pos',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpRouterApp(tester, router: router, container: container);
        expect(router.routeInformationProvider.value.uri.path, '/cashier/pos');

        // Attempt unauthorized access to Owner workspace
        router.go('/owner/overview');
        await tester.pumpAndSettle();

        // Router redirects back to cashier's authorized home
        expect(router.routeInformationProvider.value.uri.path, '/cashier/pos');
      },
    );

    testWidgets(
      'Scenario 5: Kitchen users cannot access unauthorized workspaces',
      (tester) async {
        final kitchenUser = createTestUser(WorkspaceRole.kitchen);
        final mockRepo = TestAuthRepository(currentUser: kitchenUser);
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        addTearDown(container.dispose);

        await container.read(authControllerProvider.notifier).init();

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false,
          initialLocation: '/kitchen/display',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpRouterApp(tester, router: router, container: container);
        expect(
          router.routeInformationProvider.value.uri.path,
          '/kitchen/display',
        );

        // Attempt unauthorized access to Admin, Owner, and Cashier
        router.go('/admin/dashboard');
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/kitchen/display',
        );

        router.go('/owner/overview');
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/kitchen/display',
        );

        router.go('/cashier/pos');
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/kitchen/display',
        );
        expect(find.text('Every order.\nA clear next step.'), findsOneWidget);
      },
    );

    testWidgets(
      'Scenario 6: Logout redirects to /login and clears access to workspace screens',
      (tester) async {
        final ownerUser = createTestUser(WorkspaceRole.owner);
        final mockRepo = TestAuthRepository(currentUser: ownerUser);
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        addTearDown(container.dispose);

        await container.read(authControllerProvider.notifier).init();

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false,
          initialLocation: '/owner/overview',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpRouterApp(tester, router: router, container: container);
        expect(
          router.routeInformationProvider.value.uri.path,
          '/owner/overview',
        );

        // Execute logout
        await container.read(authControllerProvider.notifier).logout();
        await tester.pumpAndSettle();

        // Router automatically redirected to /login
        expect(router.routeInformationProvider.value.uri.path, '/login');
        expect(find.text('CafeFlow Workspace'), findsOneWidget);
        expect(
          find.text('Stay close.\nWherever the day takes you.'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Scenario 7: Session restoration shows /loading then navigates to authorized workspace',
      (tester) async {
        final completer = Completer<CafeUser?>();
        final mockRepo = TestAuthRepository(restoringCompleter: completer);
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        addTearDown(container.dispose);

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false,
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        // Mount before session restoration completes (no settle to avoid timing out on infinite spinner)
        await pumpRouterApp(
          tester,
          router: router,
          container: container,
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 50));

        // Expect loading state route and spinner
        expect(router.routeInformationProvider.value.uri.path, '/loading');
        expect(find.text('Initializing CafeFlow...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Complete session restoration with Owner
        completer.complete(createTestUser(WorkspaceRole.owner));
        await tester.pump();
        await tester.pumpAndSettle();

        // Router automatically navigates to Owner workspace
        expect(
          router.routeInformationProvider.value.uri.path,
          '/owner/overview',
        );
        expect(
          find.text('Stay close.\nWherever the day takes you.'),
          findsOneWidget,
        );
        expect(find.text('Initializing CafeFlow...'), findsNothing);
      },
    );

    testWidgets(
      'Scenario 8: Missing Supabase configuration fails closed without demo mode bypass',
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
          demoEnabled: false,
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpRouterApp(tester, router: router, container: container);

        // Fails closed to login screen; demo bypass is false
        expect(router.routeInformationProvider.value.uri.path, '/login');
        expect(find.text('CafeFlow Workspace'), findsOneWidget);
        expect(
          find.textContaining('Supabase backend is unavailable'),
          findsOneWidget,
        );
        expect(find.text('Continue in Offline Demo Mode'), findsNothing);

        // Cannot bypass to workspaces
        router.go('/owner/overview');
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/login');
      },
    );

    testWidgets(
      'Scenario 9: Non-production demo mode continues to work (bypasses auth when demoEnabled is true)',
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
          initialLocation: '/owner/overview',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpRouterApp(tester, router: router, container: container);

        // Demo mode allows direct workspace access
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
      'Scenario 10: Router refreshes when authentication state changes via AuthRouterListenable',
      (tester) async {
        final ownerUser = createTestUser(WorkspaceRole.owner);
        final mockRepo = TestAuthRepository(currentUser: null);
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        addTearDown(container.dispose);

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false,
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpRouterApp(tester, router: router, container: container);
        expect(router.routeInformationProvider.value.uri.path, '/login');

        // Set mock user and log in via AuthController
        mockRepo.currentUser = ownerUser;
        final success = await container
            .read(authControllerProvider.notifier)
            .login('owner@cafeflow.internal', 'pass123');
        expect(success, isTrue);

        await tester.pumpAndSettle();

        // Router automatically reacted to the state change and redirected to /owner/overview
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
      'Scenario 11A: Authenticated user with no memberships is redirected to /access and blocked from direct navigation',
      (tester) async {
        const noMembershipUser = CafeUser(
          id: 'user-no-membership',
          email: 'unassigned@cafeflow.internal',
          fullName: 'Unassigned Staff',
          memberships: [],
        );
        final mockRepo = TestAuthRepository(currentUser: noMembershipUser);
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        addTearDown(container.dispose);

        await container.read(authControllerProvider.notifier).init();

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false,
          initialLocation: '/admin/dashboard',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpRouterApp(tester, router: router, container: container);

        // Forced to /access; never defaults to Admin
        expect(router.routeInformationProvider.value.uri.path, '/access');
        expect(find.text('Workspace access is not enabled'), findsOneWidget);
        expect(find.text('Admin / Owner'), findsNothing);

        // Direct navigation to /admin/dashboard is blocked
        router.go('/admin/dashboard');
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/access');
        expect(find.text('Workspace access is not enabled'), findsOneWidget);

        // Direct navigation to /owner/overview is blocked
        router.go('/owner/overview');
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/access');
        expect(find.text('Workspace access is not enabled'), findsOneWidget);
      },
    );

    testWidgets(
      'Scenario 11B: User whose membership lookup is still loading remains on /loading without premature redirect',
      (tester) async {
        const authedUser = CafeUser(
          id: 'user-lookup',
          email: 'lookup@cafeflow.internal',
          fullName: 'Pending Staff',
          memberships: [],
        );
        final mockRepo = TestAuthRepository(currentUser: authedUser);
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        addTearDown(container.dispose);

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false,
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        // Mount and drain initial startup
        await pumpRouterApp(tester, router: router, container: container);
        expect(router.routeInformationProvider.value.uri.path, '/access');

        // Now trigger an asynchronous membership lookup in progress
        final controller = container.read(authControllerProvider.notifier);
        controller.setMembershipLoading(true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Router transitions to /loading and does not prematurely stay on or jump to /access
        expect(router.routeInformationProvider.value.uri.path, '/loading');
        expect(find.text('Initializing CafeFlow...'), findsOneWidget);

        // Once membership lookup resolves with valid membership
        controller.updateMemberships([
          const RestaurantMembershipInfo(
            restaurantId: 'rest-001',
            restaurantName: 'Downtown Bistro',
            role: WorkspaceRole.owner,
          ),
        ]);
        await tester.pumpAndSettle();

        // Router automatically navigates from /loading to authorized workspace
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
      'Scenario 11C: Valid membership loaded after authentication transitions user from /access to authorized workspace',
      (tester) async {
        const unassignedUser = CafeUser(
          id: 'user-delayed',
          email: 'delayed@cafeflow.internal',
          fullName: 'Delayed Approval Staff',
          memberships: [],
        );
        final mockRepo = TestAuthRepository(currentUser: unassignedUser);
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        addTearDown(container.dispose);

        await container.read(authControllerProvider.notifier).init();

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false,
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpRouterApp(tester, router: router, container: container);
        expect(router.routeInformationProvider.value.uri.path, '/access');
        expect(find.text('Workspace access is not enabled'), findsOneWidget);

        // Membership approval arrives dynamically
        final controller = container.read(authControllerProvider.notifier);
        controller.updateMemberships([
          const RestaurantMembershipInfo(
            restaurantId: 'rest-001',
            restaurantName: 'Downtown Bistro',
            role: WorkspaceRole.cashier,
          ),
        ]);
        await tester.pumpAndSettle();

        // Router automatically transitions out of /access into the authorized cashier workspace
        expect(router.routeInformationProvider.value.uri.path, '/cashier/pos');
        expect(
          find.text('Good service starts with the little details.'),
          findsOneWidget,
        );
        expect(find.text('Workspace access is not enabled'), findsNothing);
      },
    );

    testWidgets(
      'Scenario 11D: Revoked membership immediately removes workspace access and redirects to /access',
      (tester) async {
        final cashierUser = createTestUser(WorkspaceRole.cashier);
        final mockRepo = TestAuthRepository(currentUser: cashierUser);
        final container = ProviderContainer(
          overrides: [
            themeStoreProvider.overrideWithValue(MemoryThemeStore('light')),
            backendProvider.overrideWithValue(_unconfiguredBackend),
            authRepositoryProvider.overrideWithValue(mockRepo),
          ],
        );
        addTearDown(container.dispose);

        await container.read(authControllerProvider.notifier).init();

        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false,
          initialLocation: '/cashier/pos',
          getAuthState: () => container.read(authControllerProvider),
          refreshListenable: AuthRouterListenable(container),
        );

        await pumpRouterApp(tester, router: router, container: container);
        expect(router.routeInformationProvider.value.uri.path, '/cashier/pos');
        expect(
          find.text('Good service starts with the little details.'),
          findsOneWidget,
        );

        // Revoke membership
        final controller = container.read(authControllerProvider.notifier);
        controller.revokeMembership();
        await tester.pumpAndSettle();

        // Router immediately ejects user to /access
        expect(router.routeInformationProvider.value.uri.path, '/access');
        expect(find.text('Workspace access is not enabled'), findsOneWidget);
        expect(
          find.text('Good service starts with the little details.'),
          findsNothing,
        );

        // Re-attempting direct access fails closed to /access
        router.go('/cashier/pos');
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/access');
      },
    );
  });
}
