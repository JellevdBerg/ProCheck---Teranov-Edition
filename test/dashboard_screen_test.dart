import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:procheck/data/hive_setup.dart';
import 'package:procheck/models/project.dart';
import 'package:procheck/models/task.dart';
import 'package:procheck/providers/projects_provider.dart';
import 'package:procheck/providers/tasks_provider.dart';
import 'package:procheck/screens/dashboard_screen.dart';
import 'package:procheck/theme/nocturne_theme.dart';

void main() {
  final now = DateTime(2026, 9, 16, 12);

  Task makeTask({bool isChecked = false, DateTime? dueDate}) => Task(
    id: 't',
    title: 'Task',
    createdAt: now,
    isChecked: isChecked,
    dueDate: dueDate,
  );

  group('isOpenTask', () {
    test('an unchecked task with no due date is open', () {
      expect(isOpenTask(makeTask(), now), isTrue);
    });

    test('an unchecked overdue task is open', () {
      expect(
        isOpenTask(makeTask(dueDate: now.subtract(const Duration(days: 1))), now),
        isTrue,
      );
    });

    test('an unchecked task due in the future is not open', () {
      expect(
        isOpenTask(makeTask(dueDate: now.add(const Duration(days: 1))), now),
        isFalse,
      );
    });

    test('a checked task is never open, regardless of due date', () {
      expect(isOpenTask(makeTask(isChecked: true), now), isFalse);
      expect(
        isOpenTask(
          makeTask(isChecked: true, dueDate: now.subtract(const Duration(days: 1))),
          now,
        ),
        isFalse,
      );
    });
  });

  group('isPendingTask', () {
    test('an unchecked task due in the future is pending', () {
      expect(
        isPendingTask(makeTask(dueDate: now.add(const Duration(days: 1))), now),
        isTrue,
      );
    });

    test('an unchecked task with no due date is not pending', () {
      expect(isPendingTask(makeTask(), now), isFalse);
    });

    test('an unchecked overdue task is not pending', () {
      expect(
        isPendingTask(makeTask(dueDate: now.subtract(const Duration(days: 1))), now),
        isFalse,
      );
    });

    test('a checked task is never pending, regardless of due date', () {
      expect(
        isPendingTask(
          makeTask(isChecked: true, dueDate: now.add(const Duration(days: 1))),
          now,
        ),
        isFalse,
      );
    });

    test('open and pending are mutually exclusive for every task', () {
      for (final task in [
        makeTask(),
        makeTask(dueDate: now.add(const Duration(days: 1))),
        makeTask(dueDate: now.subtract(const Duration(days: 1))),
        makeTask(isChecked: true),
        makeTask(isChecked: true, dueDate: now.add(const Duration(days: 1))),
      ]) {
        expect(isOpenTask(task, now) && isPendingTask(task, now), isFalse);
      }
    });
  });

  group('isDueThisWeek', () {
    test('due in 3 days is this week', () {
      expect(isDueThisWeek(makeTask(dueDate: now.add(const Duration(days: 3))), now), isTrue);
    });

    test('due later today is this week', () {
      expect(isDueThisWeek(makeTask(dueDate: now.add(const Duration(hours: 2))), now), isTrue);
    });

    test('due in 10 days is not this week', () {
      expect(isDueThisWeek(makeTask(dueDate: now.add(const Duration(days: 10))), now), isFalse);
    });

    test('overdue is not this week', () {
      expect(isDueThisWeek(makeTask(dueDate: now.subtract(const Duration(days: 1))), now), isFalse);
    });

    test('no due date is not this week', () {
      expect(isDueThisWeek(makeTask(), now), isFalse);
    });

    test('a checked task is never this week, regardless of due date', () {
      expect(
        isDueThisWeek(makeTask(isChecked: true, dueDate: now.add(const Duration(days: 3))), now),
        isFalse,
      );
    });
  });

  group('computeProjectSummaries', () {
    var counter = 0;
    Project makeProject(String name) => Project(id: 'p${counter++}_$name', name: name, createdAt: now);
    Task makeProjectTask(String projectId, {bool isChecked = false, DateTime? dueDate}) => Task(
      id: 't${counter++}',
      title: 'task',
      createdAt: now,
      projectId: projectId,
      isChecked: isChecked,
      dueDate: dueDate,
    );

    test('open is total minus done, progress is done/total', () {
      final project = makeProject('Alpha');
      final tasks = [
        makeProjectTask(project.id, isChecked: true),
        makeProjectTask(project.id),
        makeProjectTask(project.id),
      ];

      final result = computeProjectSummaries([project], tasks, now).single;

      expect(result.total, 3);
      expect(result.done, 1);
      expect(result.open, 2);
      expect(result.progress, closeTo(1 / 3, 1e-9));
      expect(result.hasOverdue, isFalse);
    });

    test('a project with no tasks has a null progress and zero open', () {
      final project = makeProject('Empty');

      final result = computeProjectSummaries([project], const [], now).single;

      expect(result.total, 0);
      expect(result.open, 0);
      expect(result.progress, isNull);
    });

    test('an unchecked past-due task marks the project overdue', () {
      final project = makeProject('Alpha');
      final tasks = [
        makeProjectTask(project.id, dueDate: now.subtract(const Duration(days: 1))),
      ];

      final result = computeProjectSummaries([project], tasks, now).single;

      expect(result.hasOverdue, isTrue);
    });

    test('a checked past-due task does not mark the project overdue', () {
      final project = makeProject('Alpha');
      final tasks = [
        makeProjectTask(project.id, isChecked: true, dueDate: now.subtract(const Duration(days: 1))),
      ];

      final result = computeProjectSummaries([project], tasks, now).single;

      expect(result.hasOverdue, isFalse);
    });

    test('ranks an overdue project before a merely-busy one', () {
      final busy = makeProject('Busy'); // 3 open, not overdue
      final overdue = makeProject('Overdue'); // 1 open, overdue
      final tasks = [
        makeProjectTask(busy.id),
        makeProjectTask(busy.id),
        makeProjectTask(busy.id),
        makeProjectTask(overdue.id, dueDate: now.subtract(const Duration(days: 1))),
      ];

      final result = computeProjectSummaries([busy, overdue], tasks, now);

      expect(result.map((r) => r.project.name).toList(), ['Overdue', 'Busy']);
    });

    test('among non-overdue projects, more open work sorts first', () {
      final quiet = makeProject('Quiet'); // 1 open
      final busy = makeProject('Busy'); // 2 open
      final tasks = [
        makeProjectTask(quiet.id),
        makeProjectTask(busy.id),
        makeProjectTask(busy.id),
      ];

      final result = computeProjectSummaries([quiet, busy], tasks, now);

      expect(result.map((r) => r.project.name).toList(), ['Busy', 'Quiet']);
    });

    test('ties break by project name', () {
      final bravo = makeProject('Bravo');
      final alpha = makeProject('Alpha');
      final tasks = [makeProjectTask(bravo.id), makeProjectTask(alpha.id)];

      final result = computeProjectSummaries([bravo, alpha], tasks, now);

      expect(result.map((r) => r.project.name).toList(), ['Alpha', 'Bravo']);
    });

    test('returns nothing for an empty project list', () {
      expect(computeProjectSummaries(const [], const [], now), isEmpty);
    });
  });

  group('DashboardScreen', () {
    late Directory tempDir;

    // Hive keeps opened boxes cached in memory by name for the life of the
    // process, regardless of a later Hive.init(newPath) call — so, as with
    // the rest of this test suite's widget tests, these two tests share
    // Hive state and must not assume a pristine box. setUpAll/tearDownAll
    // (once for the group, not once per test) makes that sharing explicit;
    // the empty-state test runs first, before anything below adds data.
    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('procheck_dashboard_test_');
      await setUpHive(testDirectoryPath: tempDir.path);
    });

    tearDownAll(() async {
      await tempDir.delete(recursive: true);
    });

    Widget wrap(Widget child, ProviderContainer container) {
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildNocturneTheme(
            brightness: Brightness.dark,
            accent: nocturneAccentPalette.first,
          ),
          home: Scaffold(body: child),
        ),
      );
    }

    // Runs before any other test in this group adds data — see the note by
    // setUpAll above on why these tests share Hive state.
    testWidgets('shows each section\'s own empty state when nothing exists yet', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        wrap(
          DashboardScreen(onOpenProject: (_, _) {}, onOpenTask: (_, _, _) {}, onOpenOrgChart: () {}),
          container,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No active projects yet.'), findsOneWidget);
      expect(find.text('Nothing needs your attention right now.'), findsOneWidget);
      expect(find.text('No recent activity yet.'), findsOneWidget);
    });

    testWidgets(
      'stat row and attention list reflect real data and skip an archived project',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final launch = container
            .read(projectsProvider.notifier)
            .addProject('Launch', colorIndex: 0);
        final shelved = container
            .read(projectsProvider.notifier)
            .addProject('Shelved', colorIndex: 1);
        container.read(projectsProvider.notifier).archiveProject(shelved.id);

        final tasksNotifier = container.read(tasksProvider.notifier);
        final overdue = tasksNotifier.addBlankTask(
          title: 'Overdue in Launch',
          projectId: launch.id,
        );
        tasksNotifier.setTaskDueDate(
          overdue.id,
          DateTime.now().subtract(const Duration(days: 1)),
        );
        // A task in the archived project must not count anywhere.
        final ignored = tasksNotifier.addBlankTask(
          title: 'In shelved project',
          projectId: shelved.id,
        );
        tasksNotifier.setTaskDueDate(
          ignored.id,
          DateTime.now().subtract(const Duration(days: 1)),
        );

        await tester.pumpWidget(
          wrap(
            DashboardScreen(onOpenProject: (_, _) {}, onOpenTask: (_, _, _) {}, onOpenOrgChart: () {}),
            container,
          ),
        );
        await tester.pumpAndSettle();

        // Scoped to a stat card's own Card ancestor via its exact label —
        // the value Text sits before the label Text in that card's tree.
        String statValueFor(String label) {
          final cardFinder = find
              .ancestor(of: find.text(label), matching: find.byType(Card))
              .first;
          final texts = tester
              .widgetList<Text>(
                find.descendant(of: cardFinder, matching: find.byType(Text)),
              )
              .toList();
          return texts.first.data!;
        }

        expect(statValueFor('Overdue'), '1');

        expect(find.text('Shelved'), findsNothing);
        expect(find.text('Overdue in Launch'), findsOneWidget);
        expect(find.text('In shelved project'), findsNothing);

        // "Launch" shows up in the attention row, the Projects table row,
        // and twice in Recent Activity (its own "created" entry plus the
        // "added" entry for the overdue task).
        expect(find.text('Launch'), findsNWidgets(4));
      },
    );

    testWidgets(
      'a task checked off today counts toward Completed today, not toward Overdue',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final project = container
            .read(projectsProvider.notifier)
            .addProject('Finisher');
        final tasksNotifier = container.read(tasksProvider.notifier);
        final task = tasksNotifier.addBlankTask(
          title: 'Finish this',
          projectId: project.id,
        );
        tasksNotifier.toggleTask(task.id);

        await tester.pumpWidget(
          wrap(
            DashboardScreen(onOpenProject: (_, _) {}, onOpenTask: (_, _, _) {}, onOpenOrgChart: () {}),
            container,
          ),
        );
        await tester.pumpAndSettle();

        String statValueFor(String label) {
          final cardFinder = find
              .ancestor(of: find.text(label), matching: find.byType(Card))
              .first;
          final texts = tester
              .widgetList<Text>(
                find.descendant(of: cardFinder, matching: find.byType(Text)),
              )
              .toList();
          return texts.first.data!;
        }

        expect(statValueFor('Completed today'), '1');
      },
    );

    testWidgets(
      'tapping an attention-list task opens its project via onOpenTask',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final project = container
            .read(projectsProvider.notifier)
            .addProject('ClickTarget');
        final tasksNotifier = container.read(tasksProvider.notifier);
        final overdue = tasksNotifier.addBlankTask(
          title: 'Click this overdue task',
          projectId: project.id,
        );
        tasksNotifier.setTaskDueDate(
          overdue.id,
          DateTime.now().subtract(const Duration(days: 1)),
        );

        String? openedProjectId;
        String? openedTaskId;
        await tester.pumpWidget(
          wrap(
            DashboardScreen(
              onOpenOrgChart: () {},
              onOpenProject: (_, _) {},
              onOpenTask: (projectId, taskId, _) {
                openedProjectId = projectId;
                openedTaskId = taskId;
              },
            ),
            container,
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Click this overdue task'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Click this overdue task'));
        await tester.pumpAndSettle();

        expect(openedProjectId, project.id);
        expect(openedTaskId, overdue.id);
      },
    );

    testWidgets(
      'tapping a Projects table row opens that project via onOpenProject',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(projectsProvider.notifier).addProject('Table Target');

        String? openedProjectId;
        await tester.pumpWidget(
          wrap(
            DashboardScreen(
              onOpenOrgChart: () {},
              onOpenProject: (projectId, _) => openedProjectId = projectId,
              onOpenTask: (_, _, _) {},
            ),
            container,
          ),
        );
        await tester.pumpAndSettle();

        // "Table Target" also shows up in Recent Activity (its own
        // "created" entry) — that row isn't wrapped in an InkWell, so
        // scoping to one that is isolates the actual table row to tap.
        final tableRowText = find.descendant(
          of: find.byType(InkWell),
          matching: find.text('Table Target'),
        );
        await tester.ensureVisible(tableRowText);
        await tester.pumpAndSettle();
        await tester.tap(tableRowText);
        await tester.pumpAndSettle();

        expect(
          openedProjectId,
          container.read(projectsProvider).firstWhere((p) => p.name == 'Table Target').id,
        );
      },
    );

    testWidgets(
      'tapping the PROJECT column header sorts, then reverses, the Projects table',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(projectsProvider.notifier).addProject('Sortable');

        await tester.pumpWidget(
          wrap(
            DashboardScreen(onOpenProject: (_, _) {}, onOpenTask: (_, _, _) {}, onOpenOrgChart: () {}),
            container,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('PROJECT'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_upward), findsNothing);
        expect(find.byIcon(Icons.arrow_downward), findsNothing);

        await tester.tap(find.text('PROJECT'));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

        await tester.tap(find.text('PROJECT'));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

        // A third tap drops back to the default (unsorted) order.
        await tester.tap(find.text('PROJECT'));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.arrow_upward), findsNothing);
        expect(find.byIcon(Icons.arrow_downward), findsNothing);
      },
    );

    testWidgets(
      'every Projects table column header always shows a sort icon, even unsorted',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(projectsProvider.notifier).addProject('AnyProject');

        await tester.pumpWidget(
          wrap(
            DashboardScreen(onOpenProject: (_, _) {}, onOpenTask: (_, _, _) {}, onOpenOrgChart: () {}),
            container,
          ),
        );
        await tester.pumpAndSettle();

        // One per sortable column (PROJECT, TASKS, PROGRESS, STATUS) — the
        // whole point is that the sort affordance is visible before anyone
        // taps anything.
        expect(find.byIcon(Icons.unfold_more), findsNWidgets(4));
      },
    );

    testWidgets(
      'tapping the STATUS header sorts projects by urgency (overdue first)',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final calm = container.read(projectsProvider.notifier).addProject('Calm');
        final onFire = container.read(projectsProvider.notifier).addProject('OnFire');
        final tasksNotifier = container.read(tasksProvider.notifier);
        tasksNotifier.addBlankTask(title: 'Calm task', projectId: calm.id);
        final urgent = tasksNotifier.addBlankTask(
          title: 'Urgent task',
          projectId: onFire.id,
        );
        tasksNotifier.setTaskDueDate(
          urgent.id,
          DateTime.now().subtract(const Duration(days: 1)),
        );

        await tester.pumpWidget(
          wrap(
            DashboardScreen(onOpenProject: (_, _) {}, onOpenTask: (_, _, _) {}, onOpenOrgChart: () {}),
            container,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('STATUS'));
        await tester.pumpAndSettle();

        // Project names also appear in Today & Needs Attention and Recent
        // Activity — scoping to the Projects card (found via its own
        // PROJECT header) isolates the table row.
        final projectsCard = find
            .ancestor(of: find.text('PROJECT'), matching: find.byType(Card))
            .first;
        double tableRowY(String projectName) => tester
            .getTopLeft(
              find.descendant(of: projectsCard, matching: find.text(projectName)),
            )
            .dy;

        // Ascending by urgency rank: OVERDUE (0) sorts before open (1).
        expect(tableRowY('OnFire'), lessThan(tableRowY('Calm')));
      },
    );

    testWidgets(
      'tapping Overdue flashes the Attention card even when already visible',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final project = container
            .read(projectsProvider.notifier)
            .addProject('Flasher');
        final tasksNotifier = container.read(tasksProvider.notifier);
        final overdue = tasksNotifier.addBlankTask(
          title: 'Overdue in Flasher',
          projectId: project.id,
        );
        tasksNotifier.setTaskDueDate(
          overdue.id,
          DateTime.now().subtract(const Duration(days: 1)),
        );

        await tester.pumpWidget(
          wrap(
            DashboardScreen(onOpenProject: (_, _) {}, onOpenTask: (_, _, _) {}, onOpenOrgChart: () {}),
            container,
          ),
        );
        await tester.pumpAndSettle();

        Card attentionCard() => tester.widget<Card>(
          find
              .ancestor(
                of: find.text('Today & Needs Attention'),
                matching: find.byType(Card),
              )
              .first,
        );

        expect(attentionCard().color, isNull);

        await tester.tap(find.text('Overdue').first);
        await tester.pump();
        expect(attentionCard().color, isNotNull);

        await tester.pump(const Duration(milliseconds: 800));
        expect(attentionCard().color, isNull);
      },
    );
  });
}
