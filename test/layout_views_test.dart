import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:procheck/data/hive_setup.dart';
import 'package:procheck/data/test_data_seed.dart';
import 'package:procheck/models/task.dart';
import 'package:procheck/providers/projects_provider.dart';
import 'package:procheck/providers/tasks_provider.dart';
import 'package:procheck/screens/calendar_screen.dart';
import 'package:procheck/screens/dashboard_screen.dart';
import 'package:procheck/screens/day_screen.dart';
import 'package:procheck/screens/today_screen.dart';
import 'package:procheck/screens/upcoming_screen.dart';
import 'package:procheck/theme/nocturne_theme.dart';
import 'package:procheck/widgets/due_date_calendar_dialog.dart';

void noop3(String? a, String b, BuildContext c) {}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('procheck_layout_');
    await setUpHive(testDirectoryPath: tempDir.path);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  const widths = [360.0, 720.0, 1280.0, 2000.0, 2560.0];
  const height = 900.0;

  ProviderContainer seeded() {
    final container = ProviderContainer();
    final data = buildTestData();
    container.read(projectsProvider.notifier).restoreAll(data.projects);
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final extra = [
      // A crowded day, a weekend-crossing span and a month-spanning task
      // exercise lane capping, the "+N" chips and compact-cell dots.
      for (var i = 0; i < 12; i++)
        Task(
          id: 'crowd$i',
          title: 'Crowded task number $i with a rather long title',
          createdAt: day,
          dueDate: day.add(const Duration(hours: 10)),
          projectId: data.projects.first.id,
          priorityIndex: i % 4,
        ),
      Task(
        id: 'span',
        title: 'Spans the weekend',
        createdAt: day,
        dueDate: day.add(const Duration(days: 3)),
        dueDateEnd: day.add(const Duration(days: 10)),
      ),
      Task(
        id: 'longspan',
        title: 'Runs across weeks',
        createdAt: day,
        dueDate: day.subtract(const Duration(days: 9)),
        dueDateEnd: day.add(const Duration(days: 14)),
      ),
    ];
    container.read(tasksProvider.notifier).restoreAll([
      ...data.tasks,
      ...extra,
    ]);
    return container;
  }

  final screens = <String, Widget Function()>{
    'dashboard': () =>
        DashboardScreen(
          onOpenProject: (_, _) {},
          onOpenTask: noop3,
          onOpenOrgChart: () {},
        ),
    'calendar': () => CalendarScreen(onDaySelected: (_) {}, onOpenTask: noop3),
    'today': () => const TodayScreen(onOpenTask: noop3),
    'upcoming': () => const UpcomingScreen(onOpenTask: noop3),
    'day': () => DayScreen(date: DateTime.now(), onOpenTask: noop3),
  };

  for (final brightness in Brightness.values) {
    for (final entry in screens.entries) {
      for (final width in widths) {
        testWidgets('${entry.key} @ ${width.toInt()} ${brightness.name}', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, height);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final container = seeded();
          addTearDown(container.dispose);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: buildNocturneTheme(
                  brightness: brightness,
                  accent: nocturneAccentPalette.first,
                ),
                home: Scaffold(body: entry.value()),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  // The calendar's other view and the day-cell dialog at the narrow and wide
  // extremes.
  for (final width in [360.0, 2560.0]) {
    testWidgets('calendar week view @ ${width.toInt()}', (tester) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = seeded();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildNocturneTheme(
              brightness: Brightness.light,
              accent: nocturneAccentPalette.first,
            ),
            home: Scaffold(
              body: CalendarScreen(onDaySelected: (_) {}, onOpenTask: noop3),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('due date dialog @ ${width.toInt()}', (tester) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildNocturneTheme(
            brightness: Brightness.dark,
            accent: nocturneAccentPalette.first,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDueDateCalendarDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
