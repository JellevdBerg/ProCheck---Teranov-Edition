import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:procheck/models/department.dart';
import 'package:procheck/models/task.dart';
import 'package:procheck/theme/nocturne_theme.dart';
import 'package:procheck/widgets/task_filter_bar.dart';

void main() {
  Task t(String id, {String? assignee, String dept = ''}) => Task(
    id: id,
    title: id,
    createdAt: DateTime(2026),
    assigneeId: assignee,
    departmentId: dept,
  );
  final tasks = [
    t('a', assignee: 'me', dept: 'd1'),
    t('b', assignee: 'x', dept: 'd2'),
  ];

  test('filter logic', () {
    expect(const TaskFilter().apply(tasks, 'me'), tasks);
    expect(const TaskFilter(mine: true).apply(tasks, 'me').map((e) => e.id), [
      'a',
    ]);
    expect(const TaskFilter(mine: true).apply(tasks, null), isEmpty);
    expect(
      const TaskFilter(departmentId: 'd2').apply(tasks, 'me').map((e) => e.id),
      ['b'],
    );
    expect(
      const TaskFilter(mine: true, departmentId: 'd2').apply(tasks, 'me'),
      isEmpty,
    );
  });

  Future<void> pump(
    WidgetTester tester,
    TaskFilterOptions opts,
    Widget child,
  ) => tester.pumpWidget(
    ProviderScope(
      overrides: [taskFilterOptionsProvider.overrideWithValue(opts)],
      child: MaterialApp(
        theme: buildNocturneTheme(
          brightness: Brightness.light,
          accent: nocturneAccentPalette.first,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );

  testWidgets('hidden in single-user mode', (tester) async {
    await pump(
      tester,
      (userId: null, departments: const []),
      TaskFilterBar(filter: const TaskFilter(), onChanged: (_) {}),
    );
    expect(find.text('All'), findsNothing);
  });

  testWidgets('chips, department chooser and clear action', (tester) async {
    var filter = const TaskFilter();
    final depts = [
      const Department(id: 'd1', name: 'Ops', isOperator: true, isIt: false),
      const Department(id: 'd2', name: 'Sales', isOperator: false, isIt: false),
    ];
    await pump(
      tester,
      (userId: 'me', departments: depts),
      StatefulBuilder(
        builder: (context, setState) => FilteredEmptyState(
          icon: Icons.check,
          message: 'Nothing here.',
          filter: filter,
          gutter: 16,
          onChanged: (f) => setState(() => filter = f),
        ),
      ),
    );
    expect(find.text('Clear filter'), findsNothing);
    await tester.tap(find.text('Assigned to me'));
    await tester.pump();
    expect(filter.mine, isTrue);
    expect(find.text('Clear filter'), findsOneWidget);

    await tester.tap(find.text('Department'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sales').last);
    await tester.pumpAndSettle();
    expect(filter.departmentId, 'd2');

    await tester.tap(find.text('Clear filter'));
    await tester.pump();
    expect(filter.isActive, isFalse);
  });
}
