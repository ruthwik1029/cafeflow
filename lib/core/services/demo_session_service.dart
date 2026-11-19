import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'backend.dart';

/// Metadata for an active or provisioned ephemeral demo session.
class DemoSessionInfo {
  const DemoSessionInfo({
    required this.sessionId,
    required this.pairingCode,
    required this.restaurantId,
    required this.role,
    required this.expiresAt,
    this.accessToken,
    this.refreshToken,
  });

  final String sessionId;
  final String pairingCode;
  final String restaurantId;
  final String role;
  final DateTime expiresAt;
  final String? accessToken;
  final String? refreshToken;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'demo_session_id': sessionId,
    'pairing_code': pairingCode,
    'restaurant_id': restaurantId,
    'role': role,
    'expires_at': expiresAt.toIso8601String(),
    if (accessToken != null) 'access_token': accessToken,
    if (refreshToken != null) 'refresh_token': refreshToken,
  };

  factory DemoSessionInfo.fromJson(Map<String, dynamic> json) =>
      DemoSessionInfo(
        sessionId: json['demo_session_id'] as String? ?? '',
        pairingCode: json['pairing_code'] as String? ?? '',
        restaurantId:
            json['restaurant_id'] as String? ??
            'a0000000-0000-0000-0000-000000000001',
        role: json['role'] as String? ?? 'DEMO_OWNER',
        expiresAt:
            DateTime.tryParse(json['expires_at'] as String? ?? '') ??
            DateTime.now().add(const Duration(hours: 2)),
        accessToken: json['access_token'] as String?,
        refreshToken: json['refresh_token'] as String?,
      );
}

/// Service that provisions, restores, and manages ephemeral Supabase demo sessions.
class DemoSessionService {
  DemoSessionService({required this.client, required this.config, this.prefs});

  static const String prefsKey = 'cafeflow_active_demo_session';

  final SupabaseClient? client;
  final AppConfig config;
  final SharedPreferences? prefs;

  DemoSessionInfo? _currentSession;
  DemoSessionInfo? get currentSession => _currentSession;

  Future<SharedPreferences?> _getPrefs() async {
    if (prefs != null) return prefs;
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  /// Restores an existing cached demo session or provisions a fresh ephemeral session
  /// via the provision-demo-session Supabase Edge Function.
  Future<DemoSessionInfo?> provisionOrRestoreSession({
    String? pairingCode,
    String role = 'DEMO_OWNER',
    bool forceNew = false,
  }) async {
    // 1. Strict Fail-Closed Production Guard
    if (!config.allowsDemo) {
      return null;
    }

    final supabase = client;
    if (supabase == null) {
      return null;
    }

    final p = await _getPrefs();

    // 2. Attempt restoration from cache if not forcing fresh creation
    if (!forceNew && pairingCode == null) {
      final cachedJson = p?.getString(prefsKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final cached = DemoSessionInfo.fromJson(
            jsonDecode(cachedJson) as Map<String, dynamic>,
          );
          if (!cached.isExpired && cached.refreshToken != null) {
            try {
              final authRes = await supabase.auth.setSession(
                cached.refreshToken!,
              );
              if (authRes.session != null) {
                _currentSession = cached;
                return cached;
              }
            } catch (_) {
              // Expired or revoked remotely -> discard and provision fresh
              await p?.remove(prefsKey);
            }
          } else {
            await p?.remove(prefsKey);
          }
        } catch (_) {
          await p?.remove(prefsKey);
        }
      }
    }

    // 3. Call provision-demo-session Edge Function
    try {
      final clientAttestation = defaultTargetPlatform == TargetPlatform.windows
          ? 'cafeflow-desktop-demo'
          : 'cafeflow-mobile-demo';

      final response = await supabase.functions.invoke(
        'provision-demo-session',
        headers: {'x-cafeflow-client': clientAttestation},
        body: {
          if (pairingCode != null && pairingCode.trim().isNotEmpty)
            'pairing_code': pairingCode.trim(),
          'role': role,
        },
      );

      if (response.status != 200 || response.data == null) {
        return null;
      }

      final data = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : jsonDecode(response.data.toString()) as Map<String, dynamic>;

      final refreshToken = data['refresh_token'] as String?;
      final accessToken = data['access_token'] as String?;
      final sessionId = data['demo_session_id'] as String? ?? '';
      final assignedPairingCode = data['pairing_code'] as String? ?? '';
      final restaurantId =
          data['restaurant_id'] as String? ??
          'a0000000-0000-0000-0000-000000000001';
      final assignedRole = data['role'] as String? ?? role;

      final expiresAt = data['expires_at'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              ((data['expires_at'] as num).toInt()) * 1000,
            )
          : DateTime.now().add(const Duration(hours: 2));

      // 4. Set GoTrue session on Supabase client
      if (refreshToken != null) {
        await supabase.auth.setSession(refreshToken);
      }

      final sessionInfo = DemoSessionInfo(
        sessionId: sessionId,
        pairingCode: assignedPairingCode,
        restaurantId: restaurantId,
        role: assignedRole,
        expiresAt: expiresAt,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      _currentSession = sessionInfo;
      await p?.setString(prefsKey, jsonEncode(sessionInfo.toJson()));
      return sessionInfo;
    } catch (_) {
      // Graceful fallback to offline demo simulation
      return null;
    }
  }

  /// Ends and purges active ephemeral demo session.
  Future<void> endDemoSession() async {
    _currentSession = null;
    final p = await _getPrefs();
    await p?.remove(prefsKey);
    try {
      await client?.auth.signOut();
    } catch (_) {}
  }
}

final demoSessionServiceProvider = Provider<DemoSessionService>((ref) {
  final backend = ref.watch(backendProvider);
  return DemoSessionService(client: backend.client, config: backend.config);
});
