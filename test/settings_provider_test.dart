import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:procheck/data/hive_setup.dart';
import 'package:procheck/models/shortcut_binding.dart';
import 'package:procheck/providers/settings_provider.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('procheck_settings_test_');
    await setUpHive(testDirectoryPath: tempDir.path);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  test('setShortcutBinding overrides the default and persists across a fresh notifier', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(settingsProvider.notifier);
    expect(
      container.read(settingsProvider).shortcutFor(ShortcutAction.newProject).displayLabel,
      'Ctrl/Cmd + P',
    );

    notifier.setShortcutBinding(
      ShortcutAction.newProject,
      const ShortcutBinding(key: LogicalKeyboardKey.keyN, shift: true),
    );
    expect(
      container.read(settingsProvider).shortcutFor(ShortcutAction.newProject).displayLabel,
      'Shift + N',
    );

    // A fresh notifier re-reads from the Hive box, simulating an app restart.
    final reloaded = SettingsNotifier();
    addTearDown(reloaded.dispose);
    expect(
      reloaded.state.shortcutFor(ShortcutAction.newProject).displayLabel,
      'Shift + N',
    );

    notifier.resetShortcutBinding(ShortcutAction.newProject);
    expect(
      container.read(settingsProvider).shortcutFor(ShortcutAction.newProject).displayLabel,
      'Ctrl/Cmd + P',
    );
  });

  test('ShortcutBinding.sameCombo detects a duplicate across actions', () {
    const a = ShortcutBinding(key: LogicalKeyboardKey.keyN, cmdOrCtrl: true);
    const b = ShortcutBinding(key: LogicalKeyboardKey.keyN, cmdOrCtrl: true);
    const c = ShortcutBinding(key: LogicalKeyboardKey.keyN, cmdOrCtrl: true, shift: true);

    expect(a.sameCombo(b), isTrue);
    expect(a.sameCombo(c), isFalse);
  });

  test('compactRows defaults to false, persists, and round-trips through JSON', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(settingsProvider).compactRows, isFalse);

    container.read(settingsProvider.notifier).setCompactRows(true);
    expect(container.read(settingsProvider).compactRows, isTrue);
    final reloaded = SettingsNotifier();
    addTearDown(reloaded.dispose);
    expect(reloaded.state.compactRows, isTrue);

    final json = container.read(settingsProvider).toJson();
    expect(AppSettings.fromJson(json).compactRows, isTrue);
    json.remove('compactRows'); // an old backup
    expect(AppSettings.fromJson(json).compactRows, isFalse);
  });}
