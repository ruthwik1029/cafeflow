import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ThemeStore {
  String? read();
  Future<void> write(String value);
}

class PreferencesThemeStore implements ThemeStore {
  const PreferencesThemeStore(this.preferences);
  final SharedPreferences preferences;
  static const key = 'cafeflow.theme';
  @override
  String? read() => preferences.getString(key);
  @override
  Future<void> write(String value) async {
    if (!await preferences.setString(key, value)) {
      throw StateError('Theme preference could not be saved.');
    }
  }
}

class UnavailableThemeStore implements ThemeStore {
  @override
  String? read() => null;
  @override
  Future<void> write(String value) async =>
      throw StateError('Preference storage is unavailable.');
}

final themeStoreProvider = Provider<ThemeStore>(
  (ref) => UnavailableThemeStore(),
);
final themeControllerProvider = NotifierProvider<ThemeController, ThemeMode>(
  ThemeController.new,
);

class ThemeController extends Notifier<ThemeMode> {
  Future<void> _pending = Future<void>.value();
  @override
  ThemeMode build() {
    final saved = ref.watch(themeStoreProvider).read();
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => ThemeMode.system,
    );
  }

  Future<bool> setMode(ThemeMode mode) async {
    state = mode;
    final store = ref.read(themeStoreProvider);
    // Serialize rapid toggles so an older preference cannot win on disk.
    final operation = _pending.then((_) => store.write(mode.name));
    _pending = operation.catchError((Object _) {});
    try {
      await operation;
      return true;
    } catch (_) {
      return false;
    }
  }
}
