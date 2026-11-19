import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/design_system/presentation/design_system_page.dart';
import '../../features/workspaces/domain/workspace_catalog.dart';
import '../../features/workspaces/presentation/workspace_section_dispatcher.dart';
import '../../features/workspaces/presentation/workspace_shell.dart';
import '../widgets/cafe_components.dart';
import 'workspace.dart';

class AuthRouterListenable extends ChangeNotifier {
  AuthRouterListenable(ProviderContainer container) {
    _subscription = container.listen<AuthState>(authControllerProvider, (
      previous,
      next,
    ) {
      if (previous?.status != next.status ||
          previous?.user?.id != next.user?.id ||
          previous?.activeMembership?.restaurantId !=
              next.activeMembership?.restaurantId ||
          previous?.activeMembership?.role != next.activeMembership?.role ||
          previous?.isRestoring != next.isRestoring ||
          previous?.isLoadingMembership != next.isLoadingMembership) {
        notifyListeners();
      }
    });
  }

  late final ProviderSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

GoRouter createInternalRouter({
  required InternalTarget target,
  required bool demoEnabled,
  String? initialLocation,
  AuthState Function()? getAuthState,
  Listenable? refreshListenable,
}) {
  final workspaces = rolesFor(target).map(workspaceFor).toList();
  return GoRouter(
    initialLocation:
        initialLocation ?? (demoEnabled ? workspaces.first.home : '/login'),
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final auth = getAuthState?.call() ?? const AuthState();
      final isAuth = auth.isAuthenticated;
      final isLoginRoute = state.uri.path == '/login';
      final isLoadingRoute = state.uri.path == '/loading';
      final isAccessRoute = state.uri.path == '/access';
      final isRootRoute = state.uri.path == '/';

      // 1. While auth state is initializing, restoring session, or loading membership
      if (auth.isAuthorizing) {
        return isLoadingRoute ? null : '/loading';
      }

      // 2. If finished restoring/loading and currently on /loading
      if (isLoadingRoute) {
        if (!isAuth) {
          return demoEnabled ? workspaces.first.home : '/login';
        }
        if (auth.activeRole != null) {
          return workspaceFor(auth.activeRole!).home;
        }
        return demoEnabled ? workspaces.first.home : '/access';
      }

      // 3. Unauthenticated access guard
      if (!isAuth && !demoEnabled) {
        return isLoginRoute ? null : '/login';
      }

      // 4. Authenticated user with NO verified restaurant membership or role (Production)
      if (isAuth && auth.activeRole == null && !demoEnabled) {
        return isAccessRoute ? null : '/access';
      }

      // 5. Authenticated user visiting /login, /access, or root when authorized with a role
      if (isAuth &&
          auth.activeRole != null &&
          (isLoginRoute || isAccessRoute || isRootRoute)) {
        return workspaceFor(auth.activeRole!).home;
      }

      // 6. Role-based route guard for authenticated users with active role
      if (isAuth && auth.activeRole != null) {
        final currentRole = auth.activeRole!;
        final allowedHome = workspaceFor(currentRole).home;

        // If the user attempts to enter a workspace route belonging to a different role
        for (final ws in workspaceCatalog) {
          if (ws.role != currentRole &&
              state.uri.path.startsWith('/${ws.role.name}')) {
            // Cashier, Kitchen, Staff cannot jump into Owner/Admin workspaces
            if (currentRole != WorkspaceRole.owner &&
                currentRole != WorkspaceRole.admin) {
              return allowedHome;
            }
          }
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, _) => demoEnabled ? workspaces.first.home : '/login',
      ),
      GoRoute(
        path: '/loading',
        builder: (_, _) => const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(height: 16),
                Text(
                  'Initializing CafeFlow...',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) =>
            LoginPage(demoBypassAllowed: demoEnabled, target: target),
      ),
      GoRoute(
        path: '/access',
        builder: (_, _) => Scaffold(
          body: SafeArea(
            child: PageBody(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CafeEmptyState(
                    title: 'Workspace access is not enabled',
                    message: 'Authentication and trusted role authorization are required. Sign in or enable demo mode in non-production builds.',
                    icon: Icons.lock_outline,
                  ),
                  const SizedBox(height: 24),
                  Consumer(
                    builder: (context, ref, _) => CafeButton(
                      label: 'Sign out',
                      onPressed: () async {
                        await ref
                            .read(authControllerProvider.notifier)
                            .logout();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      for (final workspace in workspaces)
        ShellRoute(
          builder: (context, state, child) => WorkspaceShell(
            workspace: workspace,
            available: workspaces,
            location: state.uri.path,
            child: child,
          ),
          routes: [
            for (final section in workspace.sections)
              GoRoute(
                path: workspace.path(section.id),
                builder: (_, _) => WorkspaceSectionDispatcher(
                  workspace: workspace,
                  section: section,
                ),
              ),
            GoRoute(
              path: workspace.path('design-system'),
              builder: (_, _) => const DesignSystemPage(),
            ),
          ],
        ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: SafeArea(
        child: PageBody(
          child: Column(
            children: [
              const CafeEmptyState(
                title: 'Workspace not available',
                message: 'This address is not part of this application target.',
              ),
              const SizedBox(height: 20),
              CafeButton(
                label: 'Go to workspace',
                onPressed: () => context.go(workspaces.first.home),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
