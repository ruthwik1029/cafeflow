import 'package:cafeflow/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryThemeStore implements ThemeStore {
  MemoryThemeStore([this.value]);
  String? value;
  bool fail = false;
  final writes = <String>[];
  @override
  String? read() => value;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('storage unavailable');
    writes.add(value);
    this.value = value;
  }
}

void main() {
  test('unknown saved values fall back to system', () {
    final container = ProviderContainer(
      overrides: [
        themeStoreProvider.overrideWithValue(MemoryThemeStore('corrupt')),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(themeControllerProvider), ThemeMode.system);
  });
  test('rapid changes are immediate and persisted in order', () async {
    final store = MemoryThemeStore('light');
    final container = ProviderContainer(
      overrides: [themeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final controller = container.read(themeControllerProvider.notifier);
    final dark = controller.setMode(ThemeMode.dark);
    final light = controller.setMode(ThemeMode.light);
    expect(container.read(themeControllerProvider), ThemeMode.light);
    expect(await dark, isTrue);
    expect(await light, isTrue);
    expect(store.writes, ['dark', 'light']);
  });
  test('write failure is reported and later changes can recover', () async {
    final store = MemoryThemeStore()..fail = true;
    final container = ProviderContainer(
      overrides: [themeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final controller = container.read(themeControllerProvider.notifier);
    expect(await controller.setMode(ThemeMode.dark), isFalse);
    expect(container.read(themeControllerProvider), ThemeMode.dark);
    store.fail = false;
    expect(await controller.setMode(ThemeMode.light), isTrue);
  });
  test('platform preferences survive provider recreation', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = PreferencesThemeStore(preferences);
    final first = ProviderContainer(
      overrides: [themeStoreProvider.overrideWithValue(store)],
    );
    await first.read(themeControllerProvider.notifier).setMode(ThemeMode.dark);
    first.dispose();
    final second = ProviderContainer(
      overrides: [themeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(second.dispose);
    expect(second.read(themeControllerProvider), ThemeMode.dark);
  });
}
