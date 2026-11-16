import 'core/bootstrap/launch_public.dart'
    if (dart.library.io) 'core/bootstrap/launch_internal.dart'
    as launcher;

Future<void> main() => launcher.launch();
