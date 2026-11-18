import 'dart:io';

import '../../features/auth/application/auth_controller.dart';
import '../routing/internal_router.dart';
import '../routing/workspace.dart';
import 'bootstrap.dart';

Future<void> launch() => bootstrap(
  (config, container) => createInternalRouter(
    target: Platform.isWindows
        ? InternalTarget.windows
        : InternalTarget.android,
    demoEnabled: config.allowsDemo,
    getAuthState: () => container.read(authControllerProvider),
    refreshListenable: AuthRouterListenable(container),
  ),
);
