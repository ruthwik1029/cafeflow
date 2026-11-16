import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../config/config_loader.dart';
import '../services/backend.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

Future<void> bootstrap(GoRouter Function(AppConfig) createRouter) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = loadAppConfig();
  ThemeStore themeStore;
  try {
    themeStore = PreferencesThemeStore(await SharedPreferences.getInstance());
  } catch (_) {
    themeStore = UnavailableThemeStore();
  }
  final backend = await BackendState.initialize(config);
  runApp(
    ProviderScope(
      overrides: [
        themeStoreProvider.overrideWithValue(themeStore),
        backendProvider.overrideWithValue(backend),
      ],
      child: CafeFlowApp(router: createRouter(config)),
    ),
  );
}

class CafeFlowApp extends ConsumerWidget {
  const CafeFlowApp({required this.router, super.key});
  final GoRouter router;
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'CafeFlow',
    debugShowCheckedModeBanner: false,
    theme: CafeTheme.light,
    darkTheme: CafeTheme.dark,
    themeMode: ref.watch(themeControllerProvider),
    themeAnimationDuration:
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 180),
    routerConfig: router,
  );
}
