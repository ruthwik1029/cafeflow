import 'dart:io';

import '../routing/internal_router.dart';
import '../routing/workspace.dart';
import 'bootstrap.dart';

Future<void> launch() => bootstrap(
  (config) => createInternalRouter(
    target: Platform.isWindows
        ? InternalTarget.windows
        : InternalTarget.android,
    demoEnabled: config.allowsDemo,
  ),
);
