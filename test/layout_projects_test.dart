import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:procheck/data/hive_setup.dart';
import 'package:procheck/data/test_data_seed.dart';
import 'package:procheck/models/task.dart';
import 'package:procheck/models/task_priority.dart';
import 'package:procheck/providers/projects_provider.dart';
import 'package:procheck/providers/tasks_provider.dart';
import 'package:procheck/screens/archived_screen.dart';
import 'package:procheck/screens/empty_state.dart';
import 'package:procheck/screens/project_detail_overlay.dart';
import 'package:procheck/screens/projects_screen.dart';
import 'package:procheck/theme/nocturne_theme.dart';
import 'package:procheck/widgets/smart_view_task_row.dart';
import 'package:procheck/widgets/task_tile.dart';

/// Pumps the Projects, project-detail, Archived and empty-state screens at
/// phone through ultra-wide widths in both themes; any overflow surfaces as
/// a framework exception, which `takeException` catches.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('procheck_layout_test_');
    await setUpHive(testDirectoryPath: tempDir.path);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  const widths = [360.0, 720.0, 1280.0, 2000.0];

  for (final brightness in Brightness.values) {
    for (final width in widths) {
      testWidgets('projects screens fit at ${width.toInt()}px, $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final container = ProviderContainer();
        addTearDown(container.dispose);
        final seed = buildTestData();
        final longTitle = Task(
          id: 'long',
          title:
              'An unreasonably long task title that keeps going and going to '
              'prove that wrapping works at every width',
          createdAt: DateTime.now(),
          projectId: seed.projects.first.id,
          priorityIndex: TaskPriority.high.index,
          dueDate: DateTime.now().subtract(const Duration(days: 1)),
          notes: 'Some notes that should preview on a single line only.',
        );
        container.read(projectsProvider.notifier).restoreAll(seed.projects);
        container.read(tasksProvider.notifier).restoreAll([
          ...seed.tasks,
          longTitle,
        ]);
        container
            .read(projectsProvider.notifier)
            .addComment(
              seed.projects.first.id,
              'Alex',
              'A comment long enough to wrap onto several lines in the narrow '
                  'side panel without overflowing anything at all.',
            );

        Widget wrap(Widget child) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildNocturneTheme(
              brightness: brightness,
              accent: nocturneAccentPalette.first,
            ),
            home: Scaffold(body: child),
          ),
        );

        final screens = <String, Widget>{
          'projects': ProjectsScreen(
            onShowUndo: ({required label, required onUndo}) {},
            onOpenProject: (_, _) {},
          ),
          'detail': ProjectDetailOverlay(
            projectId: seed.projects.first.id,
            onClose: () {},
          ),
          'archived': ArchivedScreen(
            onOpenProject: (_, _) {},
            onOpenTask: (_, _, _) {},
          ),
          'empty': const EmptyState(
            icon: Icons.archive_outlined,
            message: 'No archived projects.\nArchive a project to see it here.',
          ),
          'smart row': Center(
            child: SmartViewTaskRow(
              task: longTitle,
              projectName: 'Website Redesign',
              onOpenTask: (_, _, _) {},
            ),
          ),
        };

        for (final entry in screens.entries) {
          await tester.pumpWidget(wrap(entry.value));
          await tester.pump(const Duration(milliseconds: 500));
          final ex = tester.takeException();
          expect(
            ex,
            isNull,
            reason:
                '${entry.key} at $width: ${ex is FlutterError ? ex.toStringDeep() : ex}',
          );

          // Expand the first task row to exercise the detail editor too.
          if (entry.key == 'projects' || entry.key == 'detail') {
            final tile = find.byType(TaskTile).first;
            await tester.tap(
              find.descendant(of: tile, matching: find.byType(ListTile)).first,
            );
            await tester.pump(const Duration(milliseconds: 500));
            expect(
              tester.takeException(),
              isNull,
              reason: '${entry.key} expanded at $width',
            );
          }
        }
      });
    }
  }
}
