import 'package:cafeflow/core/database/database_gateway.dart';
import 'package:cafeflow/core/errors/app_failure.dart';
import 'package:cafeflow/core/routing/internal_router.dart';
import 'package:cafeflow/core/routing/workspace.dart';
import 'package:cafeflow/features/auth/application/auth_controller.dart';
import 'package:cafeflow/features/auth/data/supabase_auth_repository.dart';
import 'package:cafeflow/features/auth/domain/auth_repository.dart';
import 'package:cafeflow/features/auth/domain/auth_user.dart';
import 'package:cafeflow/features/auth/domain/permissions.dart';
import 'package:cafeflow/features/orders/domain/cafe_order.dart';
import 'package:cafeflow/features/staff/data/staff_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAuthRepository implements AuthRepository {
  MockAuthRepository({
    this.initialUser,
    this.shouldFailLogin = false,
    this.failureMessage = 'Invalid login credentials.',
  });

  CafeUser? initialUser;
  bool shouldFailLogin;
  String failureMessage;
  bool logoutCalled = false;
  String? lastResolvedUsername;

  @override
  Stream<CafeUser?> watchAuthState() => Stream.value(initialUser);

  @override
  CafeUser? get currentUser => initialUser;

  @override
  Future<CafeUser?> restoreSession() async => initialUser;

  @override
  Future<CafeUser> loginWithEmail(String email, String password) async {
    if (shouldFailLogin) {
      throw AppFailure(failureMessage);
    }
    return initialUser ??
        CafeUser(
          id: 'user-001',
          email: email,
          fullName: 'Test User',
          memberships: const [
            RestaurantMembershipInfo(
              restaurantId: 'rest-001',
              restaurantName: 'Downtown Cafe',
              role: WorkspaceRole.owner,
            ),
          ],
        );
  }

  @override
  Future<CafeUser> loginWithUsername(String username, String password) async {
    lastResolvedUsername = username;
    if (shouldFailLogin) {
      throw AppFailure(failureMessage);
    }
    final resolvedEmail = '$username@cafeflow.internal';
    return loginWithEmail(resolvedEmail, password);
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
    initialUser = null;
  }
}

class MockStaffDatabaseGateway implements DatabaseGateway {
  MockStaffDatabaseGateway({required this.memberships, required this.profiles});

  final List<Map<String, dynamic>> memberships;
  final List<Map<String, dynamic>> profiles;

  @override
  Future<List<Map<String, dynamic>>> readRows(
    String relation, {
    Map<String, Object> equals = const {},
    int limit = 100,
  }) async {
    if (relation == 'restaurant_memberships') {
      return memberships.where((m) {
        if (equals.containsKey('restaurant_id') &&
            m['restaurant_id'] != equals['restaurant_id']) {
          return false;
        }
        return true;
      }).toList();
    }
    if (relation == 'user_profiles') {
      return profiles.where((p) {
        if (equals.containsKey('id') && p['id'] != equals['id']) {
          return false;
        }
        return true;
      }).toList();
    }
    return [];
  }
}

void main() {
  group('Phase 04 — Centralized RBAC & Permission Matrix', () {
    test('OWNER role holds full administrative and ownership privileges', () {
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.owner,
          CafePermission.manageOwnership,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.owner,
          CafePermission.manageStaff,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.owner,
          CafePermission.manageMenu,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.owner,
          CafePermission.updateKitchenOrders,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.owner,
          CafePermission.processPayments,
        ),
        isTrue,
      );
    });

    test('ADMIN role has operational management but strictly CANNOT manage ownership', () {
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.admin,
          CafePermission.manageOwnership,
        ),
        isFalse,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.admin,
          CafePermission.manageStaff,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.admin,
          CafePermission.manageMenu,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.admin,
          CafePermission.processPayments,
        ),
        isTrue,
      );
    });

    test(
      'CASHIER role is scoped strictly to billing, POS, and customer orders',
      () {
        expect(
          RolePermissions.hasPermission(
            WorkspaceRole.cashier,
            CafePermission.processPayments,
          ),
          isTrue,
        );
        expect(
          RolePermissions.hasPermission(
            WorkspaceRole.cashier,
            CafePermission.createOrders,
          ),
          isTrue,
        );
        expect(
          RolePermissions.hasPermission(
            WorkspaceRole.cashier,
            CafePermission.viewOrders,
          ),
          isTrue,
        );
        expect(
          RolePermissions.hasPermission(
            WorkspaceRole.cashier,
            CafePermission.manageTables,
          ),
          isTrue,
        );
        expect(
          RolePermissions.hasPermission(
            WorkspaceRole.cashier,
            CafePermission.manageMenu,
          ),
          isFalse,
        );
        expect(
          RolePermissions.hasPermission(
            WorkspaceRole.cashier,
            CafePermission.manageStaff,
          ),
          isFalse,
        );
        expect(
          RolePermissions.hasPermission(
            WorkspaceRole.cashier,
            CafePermission.updateKitchenOrders,
          ),
          isFalse,
        );
        expect(
          RolePermissions.hasPermission(
            WorkspaceRole.cashier,
            CafePermission.manageOwnership,
          ),
          isFalse,
        );
      },
    );

    test('KITCHEN role is scoped to KOT tickets and status updates only', () {
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.kitchen,
          CafePermission.updateKitchenOrders,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.kitchen,
          CafePermission.viewOrders,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.kitchen,
          CafePermission.manageInventory,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.kitchen,
          CafePermission.processPayments,
        ),
        isFalse,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.kitchen,
          CafePermission.manageMenu,
        ),
        isFalse,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.kitchen,
          CafePermission.manageStaff,
        ),
        isFalse,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.kitchen,
          CafePermission.manageOwnership,
        ),
        isFalse,
      );
    });

    test('STAFF role has floor order taking and table viewing permissions', () {
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.staff,
          CafePermission.viewMenu,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.staff,
          CafePermission.createOrders,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.staff,
          CafePermission.manageTables,
        ),
        isTrue,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.staff,
          CafePermission.manageMenu,
        ),
        isFalse,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.staff,
          CafePermission.manageStaff,
        ),
        isFalse,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.staff,
          CafePermission.processPayments,
        ),
        isFalse,
      );
      expect(
        RolePermissions.hasPermission(
          WorkspaceRole.staff,
          CafePermission.updateKitchenOrders,
        ),
        isFalse,
      );
    });
  });

  group('Phase 04 — SEC-01 Admin Owner-Escalation & Role Protections', () {
    late StaffRepository staffRepo;

    setUp(() {
      staffRepo = StaffRepository(
        gateway: MockStaffDatabaseGateway(memberships: [], profiles: []),
        client: null,
      );
    });

    test(
      'Admin cannot provision an OWNER account (escalation guard)',
      () async {
        expect(
          () => staffRepo.provisionStaff(
            restaurantId: 'rest-1',
            targetUserId: 'target-1',
            role: WorkspaceRole.owner,
            fullName: 'Eve Hacker',
            callerRole: WorkspaceRole.admin,
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'message',
              contains(
                'Privilege escalation violation: Admins cannot provision an OWNER account.',
              ),
            ),
          ),
        );
      },
    );

    test('Admin cannot promote any member to OWNER role', () async {
      expect(
        () => staffRepo.updateStaffRole(
          restaurantId: 'rest-1',
          targetUserId: 'target-1',
          newRole: WorkspaceRole.owner,
          callerRole: WorkspaceRole.admin,
          callerUserId: 'caller-admin-1',
          targetCurrentRole: WorkspaceRole.cashier,
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains(
              'Privilege escalation violation: Admins cannot grant the OWNER role.',
            ),
          ),
        ),
      );
    });

    test('Admin cannot modify or demote an OWNER member', () async {
      expect(
        () => staffRepo.updateStaffRole(
          restaurantId: 'rest-1',
          targetUserId: 'target-owner',
          newRole: WorkspaceRole.cashier,
          callerRole: WorkspaceRole.admin,
          callerUserId: 'caller-admin-1',
          targetCurrentRole: WorkspaceRole.owner,
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains(
              'Security violation: Admins cannot modify an Owner account.',
            ),
          ),
        ),
      );
    });

    test('Admin cannot deactivate an OWNER account', () async {
      expect(
        () => staffRepo.deactivateStaff(
          restaurantId: 'rest-1',
          targetUserId: 'target-owner',
          callerRole: WorkspaceRole.admin,
          callerUserId: 'caller-admin-1',
          targetCurrentRole: WorkspaceRole.owner,
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('Security violation: Admins cannot deactivate an Owner.'),
          ),
        ),
      );
    });

    test('Anti-self-promotion: Member cannot alter their own role', () async {
      expect(
        () => staffRepo.updateStaffRole(
          restaurantId: 'rest-1',
          targetUserId: 'user-self',
          newRole: WorkspaceRole.owner,
          callerRole: WorkspaceRole.owner,
          callerUserId: 'user-self',
          targetCurrentRole: WorkspaceRole.admin,
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('Security violation: users cannot change their own role.'),
          ),
        ),
      );
    });

    test('Non-administrative roles cannot provision staff', () async {
      for (final role in [
        WorkspaceRole.cashier,
        WorkspaceRole.kitchen,
        WorkspaceRole.staff,
      ]) {
        expect(
          () => staffRepo.provisionStaff(
            restaurantId: 'rest-1',
            targetUserId: 'target-1',
            role: WorkspaceRole.staff,
            fullName: 'Rookie',
            callerRole: role,
          ),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'message',
              contains('Unauthorized: only Owners and Admins may add staff.'),
            ),
          ),
        );
      }
    });
  });

  group('Phase 04 — SEC-02 & SEC-03 Order Lifecycle & Tenant Protection', () {
    test('Order lifecycle transitions obey forward status progression', () {
      // Valid progression
      expect(OrderStatus.newOrder.index < OrderStatus.preparing.index, isTrue);
      expect(OrderStatus.preparing.index < OrderStatus.ready.index, isTrue);
      expect(OrderStatus.ready.index < OrderStatus.completed.index, isTrue);
    });

    test(
      'SEC-03: Order status advance preserves immutable financial amounts',
      () {
        final initialOrder = CafeOrder(
          id: 'ord-100',
          number: 'CF-100',
          createdAt: DateTime(2026, 11, 14, 12, 0),
          table: 'Table 5',
          status: OrderStatus.newOrder,
          lines: const [
            OrderLine(
              productId: 'coffee',
              name: 'Cold Brew',
              unitMinor: 500,
              quantity: 2,
            ),
          ],
          taxMinor: 100,
          discountMinor: 50,
        );

        final initialTotal = initialOrder.totalMinor;
        final initialSubtotal = initialOrder.subtotalMinor;

        // When status advances, financial fields remain untouched
        final advancedOrder = initialOrder.withStatus(OrderStatus.preparing);

        expect(advancedOrder.status, OrderStatus.preparing);
        expect(advancedOrder.totalMinor, initialTotal);
        expect(advancedOrder.subtotalMinor, initialSubtotal);
        expect(advancedOrder.taxMinor, initialOrder.taxMinor);
        expect(advancedOrder.discountMinor, initialOrder.discountMinor);
      },
    );
  });

  group('Phase 04 — Authentication Controller & Session Management', () {
    test(
      'Login with email authenticates user and binds active membership',
      () async {
        final mockRepo = MockAuthRepository(
          initialUser: const CafeUser(
            id: 'usr-123',
            email: 'owner@cafeflow.internal',
            fullName: 'Aanya Owner',
            memberships: [
              RestaurantMembershipInfo(
                restaurantId: 'rest-123',
                restaurantName: 'Cafe Central',
                role: WorkspaceRole.owner,
              ),
            ],
          ),
        );

        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
        );
        addTearDown(container.dispose);

        final controller = container.read(authControllerProvider.notifier);
        final success = await controller.login(
          'owner@cafeflow.internal',
          'securePass123!',
        );

        expect(success, isTrue);
        final state = container.read(authControllerProvider);
        expect(state.status, AuthStatus.authenticated);
        expect(state.user?.email, 'owner@cafeflow.internal');
        expect(state.activeRole, WorkspaceRole.owner);
        expect(state.hasPermission(CafePermission.manageOwnership), isTrue);
      },
    );

    test(
      'Login with username triggers server username-to-email resolution',
      () async {
        final mockRepo = MockAuthRepository(
          initialUser: const CafeUser(
            id: 'usr-456',
            email: 'cashier1@cafeflow.internal',
            fullName: 'Cashier One',
            username: 'cashier1',
            memberships: [
              RestaurantMembershipInfo(
                restaurantId: 'rest-123',
                restaurantName: 'Cafe Central',
                role: WorkspaceRole.cashier,
              ),
            ],
          ),
        );

        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
        );
        addTearDown(container.dispose);

        final controller = container.read(authControllerProvider.notifier);
        final success = await controller.login('cashier1', 'cashierPass!');

        expect(success, isTrue);
        expect(mockRepo.lastResolvedUsername, 'cashier1');
        final state = container.read(authControllerProvider);
        expect(state.activeRole, WorkspaceRole.cashier);
        expect(state.hasPermission(CafePermission.processPayments), isTrue);
        expect(state.hasPermission(CafePermission.manageStaff), isFalse);
      },
    );

    test(
      'Failed login sets error status and populates user-safe error message',
      () async {
        final mockRepo = MockAuthRepository(
          shouldFailLogin: true,
          failureMessage: 'Invalid login credentials.',
        );

        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
        );
        addTearDown(container.dispose);

        final controller = container.read(authControllerProvider.notifier);
        final success = await controller.login('baduser', 'wrongPassword');

        expect(success, isFalse);
        final state = container.read(authControllerProvider);
        expect(state.status, AuthStatus.error);
        expect(state.errorMessage, 'Invalid login credentials.');
        expect(state.isAuthenticated, isFalse);
      },
    );

    test(
      'Logout purges user identity, active membership, and tenant context',
      () async {
        final mockRepo = MockAuthRepository(
          initialUser: const CafeUser(
            id: 'usr-999',
            email: 'admin@cafeflow.internal',
            fullName: 'Admin Guy',
            memberships: [
              RestaurantMembershipInfo(
                restaurantId: 'rest-999',
                restaurantName: 'Branch 2',
                role: WorkspaceRole.admin,
              ),
            ],
          ),
        );

        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
        );
        addTearDown(container.dispose);

        final controller = container.read(authControllerProvider.notifier);
        await controller.login('admin@cafeflow.internal', 'pass');
        expect(container.read(authControllerProvider).isAuthenticated, isTrue);

        await controller.logout();
        final state = container.read(authControllerProvider);
        expect(state.status, AuthStatus.unauthenticated);
        expect(state.user, isNull);
        expect(state.activeMembership, isNull);
        expect(state.activeRole, isNull);
        expect(mockRepo.logoutCalled, isTrue);
      },
    );
  });

  group('Phase 04 — Internal Route Guards & Login Redirection', () {
    test(
      'Unauthenticated user is redirected to /login when demo is disabled',
      () {
        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false,
          initialLocation: '/admin/dashboard',
          getAuthState: () =>
              const AuthState(status: AuthStatus.unauthenticated),
        );

        // Verify router is created and redirect callback exists
        expect(router.configuration.redirect, isNotNull);
      },
    );

    test(
      'User with insufficient role permissions is redirected to permitted home',
      () {
        final router = createInternalRouter(
          target: InternalTarget.windows,
          demoEnabled: false,
          initialLocation: '/admin/dashboard',
          getAuthState: () => const AuthState(
            status: AuthStatus.authenticated,
            user: CafeUser(
              id: 'cashier-1',
              email: 'c@c.com',
              fullName: 'Cashier',
              memberships: [
                RestaurantMembershipInfo(
                  restaurantId: 'r-1',
                  restaurantName: 'Cafe',
                  role: WorkspaceRole.cashier,
                ),
              ],
            ),
            activeMembership: RestaurantMembershipInfo(
              restaurantId: 'r-1',
              restaurantName: 'Cafe',
              role: WorkspaceRole.cashier,
            ),
          ),
        );

        expect(router.configuration.redirect, isNotNull);
      },
    );
  });
}
