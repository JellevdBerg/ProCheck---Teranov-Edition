import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:procheck/data/hive_setup.dart';
import 'package:procheck/providers/projects_provider.dart';
import 'package:procheck/providers/tasks_provider.dart';
import 'package:procheck/providers/undo_provider.dart';

void main() {
  group('UndoStackNotifier', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('procheck_undo_test_');
      await setUpHive(testDirectoryPath: tempDir.path);
    });

    tearDownAll(() async {
      await tempDir.delete(recursive: true);
    });

    test('undoLast on an empty stack is a no-op that returns null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(undoStackProvider.notifier).undoLast(), isNull);
    });

    test('deleting a task pushes an entry that restores it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final tasks = container.read(tasksProvider.notifier);
      final task = tasks.addBlankTask(title: 'Buy milk');
      expect(container.read(tasksProvider).map((t) => t.id), contains(task.id));

      tasks.deleteTask(task.id);
      expect(container.read(tasksProvider).map((t) => t.id), isNot(contains(task.id)));
      expect(container.read(undoStackProvider), hasLength(1));

      final message = container.read(undoStackProvider.notifier).undoLast();

      expect(message, '"Buy milk" restored');
      expect(container.read(tasksProvider).map((t) => t.id), contains(task.id));
      expect(container.read(undoStackProvider), isEmpty);
    });

    test(
      'deleting a project restores it and every task it cascade-deleted together',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final projects = container.read(projectsProvider.notifier);
        final tasks = container.read(tasksProvider.notifier);

        final project = projects.addProject('Kitchen Remodel');
        final taskA = tasks.addBlankTask(title: 'Pick tiles', projectId: project.id);
        final taskB = tasks.addBlankTask(title: 'Order sink', projectId: project.id);

        projects.deleteProject(project.id);

        expect(
          container.read(projectsProvider).map((p) => p.id),
          isNot(contains(project.id)),
        );
        expect(
          container.read(tasksProvider).map((t) => t.id),
          isNot(anyOf(contains(taskA.id), contains(taskB.id))),
        );
        expect(container.read(undoStackProvider), hasLength(1));

        final message = container.read(undoStackProvider.notifier).undoLast();

        expect(message, '"Kitchen Remodel" restored');
        expect(
          container.read(projectsProvider).map((p) => p.id),
          contains(project.id),
        );
        final restoredIds = container.read(tasksProvider).map((t) => t.id);
        expect(restoredIds, contains(taskA.id));
        expect(restoredIds, contains(taskB.id));
      },
    );

    test(
      'repeated undo walks back through consecutive deletions in reverse order',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final projects = container.read(projectsProvider.notifier);
        final tasks = container.read(tasksProvider.notifier);

        final taskA = tasks.addBlankTask(title: 'First deleted');
        final project = projects.addProject('Second deleted (a project)');
        final projectTask = tasks.addBlankTask(
          title: 'Cascaded with the project',
          projectId: project.id,
        );
        final taskC = tasks.addBlankTask(title: 'Third deleted');

        tasks.deleteTask(taskA.id);
        projects.deleteProject(project.id);
        tasks.deleteTask(taskC.id);

        final stack = container.read(undoStackProvider.notifier);
        expect(container.read(undoStackProvider), hasLength(3));

        // Ctrl+Z walks back most-recent-first: C, then the project (with
        // its cascaded task), then A.
        expect(stack.undoLast(), '"Third deleted" restored');
        expect(
          container.read(tasksProvider).map((t) => t.id),
          contains(taskC.id),
        );

        expect(stack.undoLast(), '"Second deleted (a project)" restored');
        expect(
          container.read(projectsProvider).map((p) => p.id),
          contains(project.id),
        );
        expect(
          container.read(tasksProvider).map((t) => t.id),
          contains(projectTask.id),
        );

        expect(stack.undoLast(), '"First deleted" restored');
        expect(
          container.read(tasksProvider).map((t) => t.id),
          contains(taskA.id),
        );

        expect(stack.undoLast(), isNull);
        expect(container.read(undoStackProvider), isEmpty);
      },
    );
  });
}
