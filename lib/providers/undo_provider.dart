import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/task.dart';
import 'projects_provider.dart';
import 'tasks_provider.dart';

/// A single deletion that can be walked back with Ctrl+Z. Captures
/// whatever's needed to fully restore what was removed — for a project,
/// that includes the tasks its own deletion cascaded away, so undoing it
/// brings both back together in one step.
sealed class UndoEntry {
  const UndoEntry();

  /// Shown in the toast/snackbar once this entry is undone.
  String get restoredMessage;
}

class TaskDeletionEntry extends UndoEntry {
  const TaskDeletionEntry(this.task);

  final Task task;

  @override
  String get restoredMessage => '"${task.title}" restored';
}

class ProjectDeletionEntry extends UndoEntry {
  const ProjectDeletionEntry(this.project, this.tasks);

  final Project project;

  /// The project's own tasks at the moment it was deleted — cascade-deleted
  /// alongside it, and restored alongside it.
  final List<Task> tasks;

  @override
  String get restoredMessage => '"${project.name}" restored';
}

final undoStackProvider =
    StateNotifierProvider<UndoStackNotifier, List<UndoEntry>>(
      (ref) => UndoStackNotifier(ref),
    );

/// A real history of deletions (not just the single most recent one) that
/// Ctrl+Z — and the existing floating "Undo" button — both draw from.
/// Every deletion, regardless of which screen triggered it, is pushed here
/// by [TasksNotifier.deleteTask] and [ProjectsNotifier.deleteProject]
/// directly, so nothing has to remember to record it at the UI layer.
class UndoStackNotifier extends StateNotifier<List<UndoEntry>> {
  UndoStackNotifier(this._ref) : super(const []);

  final Ref _ref;

  /// How far back Ctrl+Z can walk — unbounded growth would just be a slow
  /// memory leak for a session that deletes a lot of things.
  static const _maxDepth = 50;

  bool get canUndo => state.isNotEmpty;

  void push(UndoEntry entry) {
    final next = [...state, entry];
    state = next.length > _maxDepth
        ? next.sublist(next.length - _maxDepth)
        : next;
  }

  /// Pops and reverses the most recent entry, returning a message to show
  /// for it — or null if there's nothing left to undo.
  String? undoLast() {
    if (state.isEmpty) return null;
    final entry = state.last;
    state = state.sublist(0, state.length - 1);
    switch (entry) {
      case TaskDeletionEntry(:final task):
        _ref.read(tasksProvider.notifier).restoreTask(task);
      case ProjectDeletionEntry(:final project, :final tasks):
        _ref.read(projectsProvider.notifier).restoreProject(project);
        for (final task in tasks) {
          _ref.read(tasksProvider.notifier).restoreTask(task);
        }
    }
    return entry.restoredMessage;
  }
}
