import 'package:cafeflow/core/config/app_config.dart';
import 'package:cafeflow/core/services/backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const url = 'https://example.supabase.co';
  // Synthetic test fixture, not a usable credential.
  const key = 'sb_publishable_unit_test_fixture';
  test('missing config is an explicit offline foundation state', () async {
    final result = await BackendState.initialize(const AppConfig());
    expect(result.status, BackendStatus.unconfigured);
    expect(result.client, isNull);
  });
  test('valid public configuration is accepted without claiming a connection', () {
    expect(
      const AppConfig(supabaseUrl: url, publishableKey: key).validate(),
      isNull,
    );

    // Legacy Supabase anon JWT is accepted
    const legacyAnonJwt =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRlc3QtcHJvamVjdCIsInJvbGUiOiJhbm9uIiwiaWF0IjoxNzAwMDAwMDAwLCJleHAiOjIwMDAwMDAwMDB9.signature123';
    expect(
      const AppConfig(
        supabaseUrl: url,
        publishableKey: legacyAnonJwt,
      ).validate(),
      isNull,
    );
  });
  test('partial and unsafe configuration fails closed', () async {
    const privilegedServiceRoleJwt =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRlc3QtcHJvamVjdCIsInJvbGUiOiJzZXJ2aWNlX3JvbGUiLCJpYXQiOjE3MDAwMDAwMDAsImV4cCI6MjAwMDAwMDAwMH0.signature123';
    for (final config in [
      const AppConfig(supabaseUrl: url),
      const AppConfig(publishableKey: key),
      const AppConfig(supabaseUrl: 'http://example.com', publishableKey: key),
      const AppConfig(
        supabaseUrl: 'https://user:pass@example.com',
        publishableKey: key,
      ),
      const AppConfig(
        supabaseUrl: 'https://example.com?secret=value',
        publishableKey: key,
      ),
      const AppConfig(
        supabaseUrl: url,
        publishableKey: 'sb_secret_test_fixture',
      ),
      const AppConfig(supabaseUrl: url, publishableKey: 'eyJ.privileged.jwt'),
      const AppConfig(
        supabaseUrl: url,
        publishableKey: privilegedServiceRoleJwt,
      ),
      const AppConfig(environment: 'unknown'),
    ]) {
      final result = await BackendState.initialize(config);
      expect(result.status, BackendStatus.invalidConfiguration);
      expect(result.client, isNull);
      expect(result.message, isNot(contains('sb_secret')));
    }
  });
  test('production cannot enable demo role navigation', () {
    expect(
      const AppConfig(environment: 'production', demoMode: true).allowsDemo,
      isFalse,
    );
    expect(const AppConfig(demoMode: false).allowsDemo, isFalse);
    expect(const AppConfig().allowsDemo, isTrue);
  });
}
