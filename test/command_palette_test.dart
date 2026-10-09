import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:procheck/data/hive_setup.dart';
import 'package:procheck/main.dart';
import 'package:procheck/screens/settings_screen.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('procheck_palette_');
    await setUpHive(testDirectoryPath: tempDir.path);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  testWidgets('Ctrl+K opens the palette; typing filters; Enter navigates', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: ProcheckApp()));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    final field = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.hintText == 'Type a command or search',
    );
    expect(field, findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
    expect(find.text('GO TO'), findsOneWidget);
    expect(find.text('ACTIONS'), findsOneWidget);

    await tester.enterText(field, 'zzzzqq');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);

    await tester.enterText(field, 'settings');
    await tester.pumpAndSettle();
    expect(find.text('ACTIONS'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(field, findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
