import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/workspace.dart';
import '../../../core/services/backend.dart';
import '../../../core/services/demo_session_service.dart';
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
    this.isRestoring = false,
    this.isLoadingMembership = false,
    this.isDemoSession = false,
    this.demoSessionId,
    this.demoPairingCode,
  });

  final AuthStatus status;
  final CafeUser? user;
  final RestaurantMembershipInfo? activeMembership;
  final String? errorMessage;
  final bool isRestoring;
  final bool isLoadingMembership;
  final bool isDemoSession;
  final String? demoSessionId;
  final String? demoPairingCode;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && user != null;
  bool get isLoading =>
      status == AuthStatus.authenticating || isRestoring || isLoadingMembership;
  bool get isAuthorizing => isRestoring || isLoadingMembership;
  bool get hasActiveMembership => activeMembership != null;
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
    bool? isRestoring,
    bool? isLoadingMembership,
    bool? isDemoSession,
    String? demoSessionId,
    String? demoPairingCode,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      activeMembership: activeMembership ?? this.activeMembership,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isRestoring: isRestoring ?? this.isRestoring,
      isLoadingMembership: isLoadingMembership ?? this.isLoadingMembership,
      isDemoSession: isDemoSession ?? this.isDemoSession,
      demoSessionId: demoSessionId ?? this.demoSessionId,
      demoPairingCode: demoPairingCode ?? this.demoPairingCode,
    );
  }
}

class AuthController extends Notifier<AuthState> {
  AuthRepository? get _repo => ref.read(authRepositoryProvider);

  @override
  AuthState build() {
    final repo = ref.watch(authRepositoryProvider);
    if (repo == null) {
      return const AuthState(isRestoring: false, isLoadingMembership: false);
    }
    Future.microtask(() => init());
    return const AuthState(isRestoring: true, isLoadingMembership: false);
  }

  Future<void> init() async {
    final repo = _repo;
    if (repo == null) {
      if (state.isRestoring || state.isLoadingMembership) {
        state = state.copyWith(isRestoring: false, isLoadingMembership: false);
      }
      return;
    }
    try {
      final user = await repo.restoreSession();
      if (user != null) {
        final membership = user.memberships.isNotEmpty
            ? user.memberships.first
            : null;
        final demoSession = ref.read(demoSessionServiceProvider).currentSession;
        state = AuthState(
          status: AuthStatus.authenticated,
          user: user,
          activeMembership: membership,
          isDemoSession: demoSession != null,
          demoSessionId: demoSession?.sessionId,
          demoPairingCode: demoSession?.pairingCode,
          isRestoring: false,
          isLoadingMembership: false,
        );
        return;
      }

      // If backend client is live & initialized, connect ephemeral demo session on cold start
      final backend = ref.read(backendProvider);
      if (backend.status == BackendStatus.initialized &&
          backend.client != null &&
          backend.config.allowsDemo &&
          state.status == AuthStatus.unauthenticated &&
          state.errorMessage == null) {
        final connected = await enterLiveDemoSession();
        if (connected) return;
      }

      state = state.copyWith(isRestoring: false, isLoadingMembership: false);
    } catch (_) {
      state = state.copyWith(isRestoring: false, isLoadingMembership: false);
    }
  }

  /// Establishes an ephemeral live Supabase demo session.
  Future<bool> enterLiveDemoSession({
    String? pairingCode,
    bool forceNew = false,
  }) async {
    final config = ref.read(appConfigProvider);
    if (!config.allowsDemo) return false;

    final backend = ref.read(backendProvider);
    if (backend.status != BackendStatus.initialized || backend.client == null) {
      return false;
    }

    final demoService = ref.read(demoSessionServiceProvider);
    state = state.copyWith(isLoadingMembership: true);
    try {
      final session = await demoService.provisionOrRestoreSession(
        pairingCode: pairingCode,
        forceNew: forceNew,
      );
      if (session != null) {
        final repo = _repo;
        final user = await repo?.restoreSession();
        final membership = (user != null && user.memberships.isNotEmpty)
            ? user.memberships.first
            : RestaurantMembershipInfo(
                restaurantId: session.restaurantId,
                restaurantName: 'Flagship Bistro',
                role: WorkspaceRole.owner,
              );

        state = AuthState(
          status: AuthStatus.authenticated,
          user:
              user ??
              CafeUser(
                id: session.sessionId,
                email: 'demo@cafeflow.internal',
                fullName: 'Demonstrator (Owner)',
                phone: '',
                username: 'demo_user',
                memberships: [membership],
              ),
          activeMembership: membership,
          isDemoSession: true,
          demoSessionId: session.sessionId,
          demoPairingCode: session.pairingCode,
          isRestoring: false,
          isLoadingMembership: false,
        );
        return true;
      }
    } catch (_) {
      // Graceful fallback to offline demo simulation
    }
    state = state.copyWith(isLoadingMembership: false);
    return false;
  }

  Future<bool> login(String identifier, String password) async {
    final repo = _repo;
    if (repo == null) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Backend authentication service is not configured.',
        isRestoring: false,
        isLoadingMembership: false,
      );
      return false;
    }

    state = state.copyWith(
      status: AuthStatus.authenticating,
      clearError: true,
      isRestoring: false,
      isLoadingMembership: false,
    );

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
        isRestoring: false,
        isLoadingMembership: false,
      );
      return true;
    } on AppFailure catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.message,
        isRestoring: false,
        isLoadingMembership: false,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Sign in failed. Please try again.',
        isRestoring: false,
        isLoadingMembership: false,
      );
      return false;
    }
  }

  Future<void> logout() async {
    try {
      if (state.isDemoSession) {
        await ref.read(demoSessionServiceProvider).endDemoSession();
      }
      await _repo?.logout();
    } finally {
      // Clear user session, tenant context, and error state
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        isRestoring: false,
        isLoadingMembership: false,
      );
    }
  }

  void setMembershipLoading(bool loading) {
    state = state.copyWith(isLoadingMembership: loading);
  }

  void revokeMembership() {
    state = AuthState(
      status: state.status,
      user: state.user != null
          ? CafeUser(
              id: state.user!.id,
              email: state.user!.email,
              fullName: state.user!.fullName,
              phone: state.user!.phone,
              username: state.user!.username,
              memberships: const [],
            )
          : null,
      activeMembership: null,
      isRestoring: false,
      isLoadingMembership: false,
    );
  }

  void updateMemberships(List<RestaurantMembershipInfo> memberships) {
    final active = memberships.isNotEmpty ? memberships.first : null;
    state = AuthState(
      status: state.status,
      user: state.user != null
          ? CafeUser(
              id: state.user!.id,
              email: state.user!.email,
              fullName: state.user!.fullName,
              phone: state.user!.phone,
              username: state.user!.username,
              memberships: memberships,
            )
          : null,
      activeMembership: active,
      isRestoring: false,
      isLoadingMembership: false,
    );
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
