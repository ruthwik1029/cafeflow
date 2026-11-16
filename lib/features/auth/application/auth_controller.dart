import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/workspace.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';
import '../domain/permissions.dart';

enum AuthStatus { unauthenticated, authenticating, authenticated, error }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.user,
    this.activeMembership,
    this.errorMessage,
  });

  final AuthStatus status;
  final CafeUser? user;
  final RestaurantMembershipInfo? activeMembership;
  final String? errorMessage;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && user != null;
  bool get isLoading => status == AuthStatus.authenticating;
  WorkspaceRole? get activeRole => activeMembership?.role;

  bool hasPermission(CafePermission permission) {
    if (activeRole == null) return false;
    return RolePermissions.hasPermission(activeRole!, permission);
  }

  AuthState copyWith({
    AuthStatus? status,
    CafeUser? user,
    RestaurantMembershipInfo? activeMembership,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      activeMembership: activeMembership ?? this.activeMembership,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class AuthController extends Notifier<AuthState> {
  AuthRepository? get _repo => ref.read(authRepositoryProvider);

  @override
  AuthState build() {
    Future.microtask(() => init());
    return const AuthState();
  }

  Future<void> init() async {
    final repo = _repo;
    if (repo == null) return;
    try {
      final user = await repo.restoreSession();
      if (user != null) {
        final membership = user.memberships.isNotEmpty
            ? user.memberships.first
            : null;
        state = AuthState(
          status: AuthStatus.authenticated,
          user: user,
          activeMembership: membership,
        );
      }
    } catch (_) {
      // Session restoration failed; remain unauthenticated
    }
  }

  Future<bool> login(String identifier, String password) async {
    final repo = _repo;
    if (repo == null) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Backend authentication service is not configured.',
      );
      return false;
    }

    state = state.copyWith(status: AuthStatus.authenticating, clearError: true);

    try {
      final clean = identifier.trim();
      final user = clean.contains('@')
          ? await repo.loginWithEmail(clean, password)
          : await repo.loginWithUsername(clean, password);

      final membership = user.memberships.isNotEmpty
          ? user.memberships.first
          : null;

      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        activeMembership: membership,
      );
      return true;
    } on AppFailure catch (e) {
      state = state.copyWith(status: AuthStatus.error, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Sign in failed. Please try again.',
      );
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _repo?.logout();
    } finally {
      // Clear user session, tenant context, and error state
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  void selectRestaurant(String restaurantId) {
    if (state.user == null) return;
    final target = state.user!.membershipFor(restaurantId);
    if (target != null) {
      state = state.copyWith(activeMembership: target);
    }
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
