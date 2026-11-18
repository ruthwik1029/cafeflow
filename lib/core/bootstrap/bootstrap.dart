import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../config/config_loader.dart';
import '../services/backend.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

typedef AppRouterFactory = GoRouter Function(
  AppConfig config,
  ProviderContainer container,
);

Future<void> bootstrap(AppRouterFactory createRouter) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = loadAppConfig();
  ThemeStore themeStore;
  try {
    themeStore = PreferencesThemeStore(await SharedPreferences.getInstance());
  } catch (_) {
    themeStore = UnavailableThemeStore();
  }
  final backend = await BackendState.initialize(config);
  final container = ProviderContainer(
    overrides: [
      themeStoreProvider.overrideWithValue(themeStore),
      backendProvider.overrideWithValue(backend),
    ],
  );
  final router = createRouter(config, container);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: CafeFlowApp(router: router),
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
