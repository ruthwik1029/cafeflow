import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/design_system/presentation/design_system_page.dart';
import '../../features/workspaces/domain/workspace_catalog.dart';
import '../../features/workspaces/presentation/workspace_section_dispatcher.dart';
import '../../features/workspaces/presentation/workspace_shell.dart';
import '../widgets/cafe_components.dart';
import 'workspace.dart';

GoRouter createInternalRouter({
  required InternalTarget target,
  required bool demoEnabled,
  String? initialLocation,
  AuthState Function()? getAuthState,
}) {
  final workspaces = rolesFor(target).map(workspaceFor).toList();
  return GoRouter(
    initialLocation: initialLocation ?? workspaces.first.home,
    redirect: (context, state) {
      final auth = getAuthState?.call();

      // If live authentication state is provided
      if (auth != null) {
        final isAuth = auth.isAuthenticated;
        final isLoginRoute = state.uri.path == '/login';

        // Unauthenticated access
        if (!isAuth && !demoEnabled) {
          return isLoginRoute ? null : '/login';
        }

        // Already authenticated user visiting login page -> redirect to permitted home
        if (isAuth && isLoginRoute) {
          final role = auth.activeRole ?? workspaces.first.role;
          return workspaceFor(role).home;
        }

        // Role-based route guard
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
      }

      // Legacy demo disabled guard for offline testing
      if (!demoEnabled &&
          state.uri.path != '/access' &&
          state.uri.path != '/login') {
        return '/access';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => workspaces.first.home),
      GoRoute(
        path: '/login',
        builder: (_, _) => LoginPage(demoBypassAllowed: demoEnabled),
      ),
      GoRoute(
        path: '/access',
        builder: (_, _) => const Scaffold(
          body: SafeArea(
            child: PageBody(
              child: CafeEmptyState(
                title: 'Workspace access is not enabled',
                message: 'Authentication and trusted role authorization are required. Sign in or enable demo mode in non-production builds.',
                icon: Icons.lock_outline,
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
