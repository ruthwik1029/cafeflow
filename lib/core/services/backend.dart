import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../errors/app_failure.dart';

enum BackendStatus { unconfigured, invalidConfiguration, initialized, failed }

class BackendState {
  const BackendState(this.status, this.message, {this.client});
  final BackendStatus status;
  final String message;
  final SupabaseClient? client;

  static Future<BackendState> initialize(AppConfig config) async {
    final problem = config.validate();
    if (problem != null) {
      return BackendState(BackendStatus.invalidConfiguration, problem);
    }
    if (!config.hasBackendValues) {
      return const BackendState(
        BackendStatus.unconfigured,
        'Add your project URL and publishable key to enable the client.',
      );
    }
    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.publishableKey,
        debug: false,
        authOptions: const FlutterAuthClientOptions(
          detectSessionInUri: false,
          autoRefreshToken: true,
        ),
      );
      return BackendState(
        BackendStatus.initialized,
        'Client initialized. Database connectivity and access are not verified.',
        client: Supabase.instance.client,
      );
    } catch (_) {
      return const BackendState(
        BackendStatus.failed,
        'The backend client could not initialize. Check configuration and connectivity.',
      );
    }
  }
}

final backendProvider = Provider<BackendState>(
  (ref) => const BackendState(
    BackendStatus.unconfigured,
    'Backend is not configured.',
  ),
);
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  final client = ref.watch(backendProvider).client;
  if (client == null) throw const AppFailure('Backend is unavailable.');
  return client;
});
