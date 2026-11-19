import 'dart:convert';

enum AppEnvironment { development, staging, production }

/// These values are public in a compiled client. Never place secrets here.
class AppConfig {
  const AppConfig({
    this.environment = 'development',
    this.supabaseUrl = '',
    this.publishableKey = '',
    this.demoMode = true,
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
    environment: String.fromEnvironment('APP_ENV', defaultValue: 'development'),
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    demoMode: bool.fromEnvironment('DEMO_MODE', defaultValue: true),
  );

  final String environment;
  final String supabaseUrl;
  final String publishableKey;
  final bool demoMode;
  bool get hasBackendValues =>
      supabaseUrl.isNotEmpty || publishableKey.isNotEmpty;
  bool get allowsDemo => demoMode && environment != 'production';

  static bool _isValidPublishableKey(String key) {
    if (RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(key)) {
      return true;
    }
    // Support legacy Supabase anon JWTs while strictly forbidding service_role
    if (RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$')
        .hasMatch(key)) {
      return _isLegacyAnonJwt(key);
    }
    return false;
  }

  static bool _isLegacyAnonJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    try {
      var payload = parts[1];
      final remainder = payload.length % 4;
      if (remainder == 2) {
        payload += '==';
      } else if (remainder == 3) {
        payload += '=';
      } else if (remainder == 1) {
        return false;
      }
      final decodedBytes = base64Url.decode(payload);
      final decoded = utf8.decode(decodedBytes);
      // Strictly forbid service_role or admin tokens
      if (decoded.contains('service_role') ||
          decoded.contains('supabase_admin')) {
        return false;
      }
      final json = jsonDecode(decoded);
      if (json is Map && json['role'] == 'anon') {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  String? validate() {
    if (!AppEnvironment.values.any((value) => value.name == environment)) {
      return 'APP_ENV must be development, staging, or production.';
    }
    if (environment == 'production' && !hasBackendValues) {
      return 'Production configuration is missing. SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are required.';
    }
    if (!hasBackendValues) return null;
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return 'SUPABASE_URL must be an HTTPS project origin.';
    }
    if (!_isValidPublishableKey(publishableKey)) {
      return 'Supply a Supabase publishable key; privileged keys are forbidden.';
    }
    return null;
  }
}
