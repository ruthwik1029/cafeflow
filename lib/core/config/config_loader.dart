import 'app_config.dart';
import 'config_loader_stub.dart'
    if (dart.library.io) 'config_loader_io.dart'
    as loader;

/// Resolves the application configuration across all target platforms.
AppConfig loadAppConfig() => loader.resolveAppConfig();
