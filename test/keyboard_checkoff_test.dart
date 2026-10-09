import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:procheck/data/hive_setup.dart';
import 'package:procheck/providers/tasks_provider.dart';
import 'package:procheck/theme/nocturne_theme.dart';
import 'package:procheck/widgets/task_tile.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('procheck_kbd_');
    await setUpHive(testDirectoryPath: tempDir.path);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  testWidgets('arrow keys move row focus and space toggles that task', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(tasksProvider.notifier);
    notifier.addBlankTask(title: 'First');
    notifier.addBlankTask(title: 'Second');
    // Displayed order (the provider sorts); first = top row, second = below.
    final [a, b] = [for (final t in container.read(tasksProvider)) t.id];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNocturneTheme(
            brightness: Brightness.light,
            accent: const Color(0xFF3355CC),
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Column(
                children: [
                  for (final t in ref.watch(tasksProvider))
                    TaskTile(key: ValueKey(t.id), task: t, onDelete: () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    bool checked(String id) =>
        container.read(tasksProvider).firstWhere((t) => t.id == id).isChecked;

    // Focus the first row (as Tab would), then Down + Space hits the second.
    tester
        .widget<Focus>(
          find
              .descendant(
                of: find.byType(TaskRowFocus).first,
                matching: find.byType(Focus),
              )
              .first,
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(checked(a), isFalse);
    expect(checked(b), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(checked(a), isTrue);
  });
}
