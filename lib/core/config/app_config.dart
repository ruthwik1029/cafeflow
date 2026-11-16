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

  String? validate() {
    if (!AppEnvironment.values.any((value) => value.name == environment)) {
      return 'APP_ENV must be development, staging, or production.';
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
    if (!RegExp(r'^sb_publishable_[A-Za-z0-9_-]+$').hasMatch(publishableKey)) {
      return 'Supply a Supabase publishable key; privileged keys are forbidden.';
    }
    return null;
  }
}
