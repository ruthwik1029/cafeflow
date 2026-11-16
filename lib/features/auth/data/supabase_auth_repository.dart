import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/database_gateway.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/backend.dart';
import '../../../core/routing/workspace.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({required this.client, required this.gateway});

  final SupabaseClient? client;
  final DatabaseGateway gateway;
  CafeUser? _cachedUser;

  @override
  CafeUser? get currentUser => _cachedUser;

  @override
  Future<CafeUser> loginWithEmail(String email, String password) async {
    if (client == null) {
      throw const AppFailure('Authentication service is unavailable.');
    }
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || password.isEmpty) {
      throw const AppFailure('Please provide both email and password.');
    }

    try {
      final response = await client!.auth.signInWithPassword(
        email: cleanEmail,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        throw const AppFailure('Sign in failed: no user returned.');
      }

      final cafeUser = await _loadUserProfileAndMemberships(user);
      _cachedUser = cafeUser;
      return cafeUser;
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('invalid login credentials')) {
        throw const AppFailure('Invalid email or password.');
      }
      throw AppFailure(e.message);
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw const AppFailure('Sign in failed. Check connection and try again.');
    }
  }

  @override
  Future<CafeUser> loginWithUsername(String username, String password) async {
    if (client == null) {
      throw const AppFailure('Authentication service is unavailable.');
    }
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty || password.isEmpty) {
      throw const AppFailure('Please provide both username and password.');
    }

    // If user entered email format in username box, route directly to email signin
    if (cleanUsername.contains('@')) {
      return loginWithEmail(cleanUsername, password);
    }

    // Resolve username to email using the secure server-side RPC
    String? resolvedEmail;
    try {
      final res = await client!
          .rpc(
            'resolve_username_to_email',
            params: {'p_identifier': cleanUsername},
          )
          .timeout(const Duration(seconds: 10));
      resolvedEmail = res as String?;
    } catch (_) {
      throw const AppFailure('Could not resolve username. Check connection.');
    }

    if (resolvedEmail == null || resolvedEmail.isEmpty) {
      throw const AppFailure('No account found for that username.');
    }

    return loginWithEmail(resolvedEmail, password);
  }

  @override
  Future<void> logout() async {
    _cachedUser = null;
    if (client != null) {
      try {
        await client!.auth.signOut();
      } catch (_) {
        // Ignore network failure on sign out
      }
    }
  }

  @override
  Future<CafeUser?> restoreSession() async {
    if (client == null) return null;
    final session = client!.auth.currentSession;
    if (session == null || session.isExpired) {
      _cachedUser = null;
      return null;
    }
    final user = session.user;
    try {
      final cafeUser = await _loadUserProfileAndMemberships(user);
      _cachedUser = cafeUser;
      return cafeUser;
    } catch (_) {
      _cachedUser = null;
      return null;
    }
  }

  @override
  Stream<CafeUser?> watchAuthState() {
    if (client == null) {
      return Stream.value(null);
    }
    return client!.auth.onAuthStateChange.asyncMap((data) async {
      final user = data.session?.user;
      if (user == null) {
        _cachedUser = null;
        return null;
      }
      try {
        final cafeUser = await _loadUserProfileAndMemberships(user);
        _cachedUser = cafeUser;
        return cafeUser;
      } catch (_) {
        return null;
      }
    });
  }

  Future<CafeUser> _loadUserProfileAndMemberships(User user) async {
    String fullName = user.userMetadata?['full_name'] as String? ?? '';
    String phone = user.phone ?? '';
    String username = '';

    // Load from user_profiles table if available
    try {
      final profiles = await gateway.readRows(
        'user_profiles',
        equals: {'id': user.id},
        limit: 1,
      );
      if (profiles.isNotEmpty) {
        final p = profiles.first;
        fullName = (p['full_name'] as String?) ?? fullName;
        phone = (p['phone'] as String?) ?? phone;
        username = (p['username'] as String?) ?? '';
      }
    } catch (_) {
      // Fall back to auth user metadata if database row read is restricted
    }

    // Load memberships from restaurant_memberships
    final List<RestaurantMembershipInfo> memberships = [];
    try {
      final membershipRows = await gateway.readRows(
        'restaurant_memberships',
        equals: {'user_id': user.id, 'is_active': true},
        limit: 50,
      );

      for (final row in membershipRows) {
        final rId = row['restaurant_id'] as String;
        final rawRole = (row['role'] as String? ?? 'STAFF').toUpperCase();
        final role = switch (rawRole) {
          'OWNER' => WorkspaceRole.owner,
          'ADMIN' => WorkspaceRole.admin,
          'CASHIER' => WorkspaceRole.cashier,
          'KITCHEN' => WorkspaceRole.kitchen,
          'STAFF' => WorkspaceRole.staff,
          _ => WorkspaceRole.staff,
        };

        // Fetch restaurant name
        String rName = 'CafeFlow Bistro';
        try {
          final rRows = await gateway.readRows(
            'restaurants',
            equals: {'id': rId},
            limit: 1,
          );
          if (rRows.isNotEmpty) {
            rName = rRows.first['name'] as String;
          }
        } catch (_) {}

        memberships.add(
          RestaurantMembershipInfo(
            restaurantId: rId,
            restaurantName: rName,
            role: role,
          ),
        );
      }
    } catch (_) {
      // Membership read failure
    }

    return CafeUser(
      id: user.id,
      email: user.email ?? '',
      fullName: fullName.isEmpty ? (user.email ?? 'Staff') : fullName,
      phone: phone,
      username: username,
      memberships: memberships,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend.status != BackendStatus.initialized) {
    return null;
  }
  return SupabaseAuthRepository(
    client: backend.client,
    gateway: ref.watch(databaseGatewayProvider),
  );
});
