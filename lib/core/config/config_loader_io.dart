import 'dart:io';

import 'app_config.dart';

/// Desktop / Mobile IO implementation: resolves configuration from compile-time defines,
/// OS system environment variables, or local `.env` files.
AppConfig resolveAppConfig() {
  final fromCompile = AppConfig.fromEnvironment();
  if (fromCompile.hasBackendValues) {
    return fromCompile;
  }

  // Check system environment variables first
  final sysUrl = Platform.environment['SUPABASE_URL']?.trim() ?? '';
  final sysKey = Platform.environment['SUPABASE_PUBLISHABLE_KEY']?.trim() ?? '';
  final sysEnv = Platform.environment['APP_ENV']?.trim() ?? '';
  final sysDemo = Platform.environment['DEMO_MODE']?.trim();

  if (sysUrl.isNotEmpty && sysKey.isNotEmpty) {
    return AppConfig(
      environment: sysEnv.isNotEmpty ? sysEnv : fromCompile.environment,
      supabaseUrl: sysUrl,
      publishableKey: sysKey,
      demoMode: sysDemo != null
          ? sysDemo.toLowerCase() == 'true'
          : fromCompile.demoMode,
    );
  }

  // Look for a local .env file in candidate directories
  final candidates = <File>[
    File('.env'),
    File('${Directory.current.path}/.env'),
  ];

  try {
    final exeDir = File(Platform.resolvedExecutable).parent;
    candidates.add(File('${exeDir.path}/.env'));
    candidates.add(File('${exeDir.parent.path}/.env'));
  } catch (_) {
    // Ignore executable path resolution errors
  }

  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      try {
        final lines = candidate.readAsLinesSync();
        final parsed = <String, String>{};
        for (final rawLine in lines) {
          final line = rawLine.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final eqIdx = line.indexOf('=');
          if (eqIdx > 0) {
            final key = line.substring(0, eqIdx).trim();
            final value = line.substring(eqIdx + 1).trim();
            // Remove optional quotes
            if ((value.startsWith('"') && value.endsWith('"')) ||
                (value.startsWith("'") && value.endsWith("'"))) {
              parsed[key] = value.substring(1, value.length - 1);
            } else {
              parsed[key] = value;
            }
          }
        }

        final fileUrl = parsed['SUPABASE_URL'] ?? sysUrl;
        final fileKey = parsed['SUPABASE_PUBLISHABLE_KEY'] ?? sysKey;
        final fileEnv = parsed['APP_ENV'] ?? sysEnv;
        final fileDemo = parsed['DEMO_MODE'] ?? sysDemo;

        if (fileUrl.isNotEmpty || fileKey.isNotEmpty) {
          return AppConfig(
            environment: fileEnv.isNotEmpty ? fileEnv : fromCompile.environment,
            supabaseUrl: fileUrl,
            publishableKey: fileKey,
            demoMode: fileDemo != null
                ? fileDemo.toLowerCase() == 'true'
                : fromCompile.demoMode,
          );
        }
      } catch (_) {
        // Continue to next candidate on read failure
      }
    }
  }

  return fromCompile;
}
