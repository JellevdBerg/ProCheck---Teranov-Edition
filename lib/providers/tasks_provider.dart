import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/app_messenger.dart';
import '../data/hive_setup.dart';
import '../data/notification_service.dart';
import '../data/sound_service.dart';
import '../data/supabase_config.dart';
import '../models/activity_entry.dart';
import '../models/attachment.dart';
import '../models/subtask.dart';
import '../models/task.dart';
import '../models/task_priority.dart';
import '../models/task_template.dart';
import 'projects_provider.dart';
import 'sync_log_provider.dart';
import 'syncable_notifier.dart';
import 'undo_provider.dart';

final tasksProvider = StateNotifierProvider<TasksNotifier, List<Task>>((ref) {
  return TasksNotifier(ref);
});

/// Persistence to Hive is fire-and-forget, same as the local-only app
/// always has: [state] is the source of truth for the UI and is updated
/// synchronously, while the on-disk copy catches up in the background.
///
/// When Supabase is configured and signed in (see [isSupabaseConfigured]),
/// every write is additionally mirrored to the `tasks` table — also
/// fire-and-forget, so a flaky connection never blocks the UI — and a
/// one-time pull on construction merges in whatever's visible to this
/// user there (their own tasks, what's assigned to them, their
/// department's, per the RLS policies). See [SyncableNotifier] for the
/// profile-load/pull/realtime plumbing shared with [ProjectsNotifier].
class TasksNotifier extends StateNotifier<List<Task>>
    with SyncableNotifier<Task> {
  TasksNotifier(this.ref) : super(_box.values.toList()) {
    _sortState();
    unawaited(profileReady);
    unawaited(pullFromSupabase().then((_) => subscribeRealtime()));
  }

  @override
  final Ref ref;

  static Box<Task> get _box => Hive.box<Task>(taskBoxName);

  @override
  String get syncTable => 'tasks';

  @override
  Box<Task> get syncBox => _box;

  @override
  Task rowFromSupabase(Map<String, dynamic> row) => Task.fromSupabase(row);

  @override
  String idOf(Task item) => item.id;

  @override
  void resortState() {
    state = _box.values.toList();
    _sortState();
  }

  @override
  void dispose() {
    disposeSync();
    super.dispose();
  }

  /// Every task — used where that's explicitly correct (backup export,
  /// Settings > Wipe All Data already clearing the whole box).
  List<Task> get allValues => _box.values.toList();

  Future<void> _mirrorUpsert(Task task, {Task? previous}) async {
    if (!isSupabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    // ownerId/departmentId are blank for a task created before the
    // profile resolves — sending that as a uuid column fails server-side.
    // The splash screen now gates creation UI behind [profileReady], so
    // this is only a safety net (e.g. restoring very old local data).
    if (task.ownerId.isEmpty) return;
    try {
      await supabase.from('tasks').upsert(task.toSupabase());
    } on PostgrestException catch (e) {
      // The server actively refused this write (most commonly an RLS
      // policy) — the local optimistic update is now wrong, so roll it
      // back (or, for a brand-new task with no prior state, remove it)
      // and tell the user, instead of leaving it silently stuck.
      ref
          .read(syncLogProvider.notifier)
          .recordError(source: 'tasks', action: 'upsert', error: e);
      _rollback(task, previous, e);
    } catch (e) {
      // Offline/network failure — stays local-only by design, same as
      // always; only logged for the dev panel.
      ref
          .read(syncLogProvider.notifier)
          .recordError(source: 'tasks', action: 'upsert', error: e);
    }
  }

  void _rollback(Task rejected, Task? previous, PostgrestException e) {
    if (previous != null) {
      unawaited(_box.put(previous.id, previous));
      _replace(previous);
    } else {
      unawaited(_box.delete(rejected.id));
      state = state.where((t) => t.id != rejected.id).toList();
    }
    showSyncFailureToast('Couldn\'t save "${rejected.title}": ${e.message}');
  }

  Future<void> _mirrorDelete(String taskId) async {
    if (!isSupabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    try {
      await supabase.from('tasks').delete().eq('id', taskId);
    } catch (e) {
      // Best-effort.
      ref
          .read(syncLogProvider.notifier)
          .recordError(source: 'tasks', action: 'delete', error: e);
    }
  }

  /// Logs a task-level event to its parent project's Activity log — a
  /// no-op for unfiled tasks (no project to log against).
  void _logActivity(Task task, ActivityKind kind, String description) {
    final projectId = task.projectId;
    if (projectId == null) return;
    ref.read(projectsProvider.notifier).logActivity(
      projectId,
      ActivityEntry(
        kindIndex: kind.index,
        description: description,
        timestamp: DateTime.now(),
      ),
    );
  }

  void _sortState() {
    final sorted = [...state]
      ..sort((a, b) {
        final order = b.sortOrder.compareTo(a.sortOrder);
        if (order != 0) return order;
        return b.createdAt.compareTo(a.createdAt);
      });
    state = sorted;
  }

  void _replace(Task updated) {
    state = [
      for (final t in state)
        if (t.id == updated.id) updated else t,
    ];
  }

  /// Persists [task] — a freshly built [Task.copyWith] instance, never the
  /// same object already in [state] — and swaps it into [state] in place.
  /// Building a new instance rather than mutating the existing one in the
  /// box is what lets value-equality-based selectors (see [Task.operator
  /// ==]) detect the edit: mutating the box's cached instance in place
  /// would mean the "old" and "new" values a selector compares are the
  /// very same object, always equal regardless of what changed.
  void _persist(Task task) {
    final previous = state.firstWhereOrNull((t) => t.id == task.id);
    unawaited(_box.put(task.id, task));
    unawaited(_mirrorUpsert(task, previous: previous));
    _replace(task);
  }

  Task addBlankTask({
    required String title,
    String? projectId,
    TaskPriority priority = TaskPriority.none,
    DateTime? dueDate,
    DateTime? dueDateEnd,
  }) {
    return _addTask(
      title: title,
      projectId: projectId,
      subtasks: const [],
      priority: priority,
      dueDate: dueDate,
      dueDateEnd: dueDateEnd,
    );
  }

  Task addFromTemplate({
    required TaskTemplate template,
    String? projectId,
    String? title,
    TaskPriority priority = TaskPriority.none,
    DateTime? dueDate,
    DateTime? dueDateEnd,
  }) {
    final subtasks = template.subtasks
        .map(
          (templateSubtask) =>
              Subtask(id: const Uuid().v4(), title: templateSubtask.title),
        )
        .toList();
    // Fresh Attachment copies rather than the template's own instances —
    // each HiveObject should belong to one parent's list, not be shared
    // between the template and every task instantiated from it.
    final attachments = template.attachments
        .map((a) => Attachment(name: a.name, size: a.size, path: a.path))
        .toList();
    return _addTask(
      title: title ?? template.name,
      projectId: projectId,
      subtasks: subtasks,
      templateId: template.id,
      priority: priority,
      notes: template.notes,
      attachments: attachments,
      dueDate: dueDate,
      dueDateEnd: dueDateEnd,
    );
  }

  Task _addTask({
    required String title,
    String? projectId,
    required List<Subtask> subtasks,
    String? templateId,
    TaskPriority priority = TaskPriority.none,
    String? notes,
    List<Attachment>? attachments,
    DateTime? dueDate,
    DateTime? dueDateEnd,
  }) {
    final task = Task(
      id: const Uuid().v4(),
      title: title,
      subtasks: subtasks,
      createdAt: DateTime.now(),
      projectId: projectId,
      templateId: templateId,
      priorityIndex: priority.index,
      notes: notes,
      attachments: attachments,
      dueDate: dueDate,
      dueDateEnd: dueDate == null ? null : dueDateEnd,
      ownerId: ownerId ?? '',
      departmentId: departmentId ?? '',
    );
    unawaited(_box.put(task.id, task));
    unawaited(_mirrorUpsert(task));
    state = [task, ...state];
    _logActivity(task, ActivityKind.taskAdded, '$authorName added "${task.title}"');
    if (dueDate != null) {
      unawaited(NotificationService.instance.scheduleForTask(task));
    }
    return task;
  }

  void renameTask(String taskId, String title) {
    final task = _box.get(taskId);
    if (task == null) return;
    final updated = task.copyWith(title: title);
    _persist(updated);
    _logActivity(
      updated,
      ActivityKind.taskEdited,
      '$authorName edited "${updated.title}"',
    );
  }

  void moveToProject(String taskId, String? projectId) {
    final task = _box.get(taskId);
    if (task == null) return;
    _persist(task.copyWith(projectId: projectId));
  }

  /// Assigns [taskId] to [assigneeId] (or clears the assignment when null).
  /// Only a manager's assignment actually lands once Supabase is
  /// configured — the `tasks_update` RLS policy enforces that server-side;
  /// this client doesn't duplicate that check.
  void assignTask(String taskId, String? assigneeId) {
    final task = _box.get(taskId);
    if (task == null) return;
    _persist(task.copyWith(assigneeId: assigneeId));
  }

  /// Sets how long this task is expected to take, in minutes — shown in the
  /// team dashboard's occupancy totals. Pass null to clear it.
  void setTaskEstimate(String taskId, int? estimatedMinutes) {
    final task = _box.get(taskId);
    if (task == null) return;
    _persist(task.copyWith(estimatedMinutes: estimatedMinutes));
  }

  void deleteTask(String taskId) {
    final task = _box.get(taskId);
    if (task != null) {
      unawaited(NotificationService.instance.cancelForTask(task));
    }
    unawaited(_box.delete(taskId));
    unawaited(_mirrorDelete(taskId));
    state = state.where((t) => t.id != taskId).toList();
    if (task != null) {
      ref.read(undoStackProvider.notifier).push(TaskDeletionEntry(task));
    }
  }

  /// Re-adds a previously-deleted [task] exactly as it was — used to undo an
  /// accidental deletion. Reschedules its due-date notification if it had
  /// one and isn't checked off.
  void restoreTask(Task task) {
    unawaited(_box.put(task.id, task));
    unawaited(_mirrorUpsert(task));
    state = [task, ...state];
    _sortState();
    if (task.dueDate != null && !task.isChecked) {
      unawaited(NotificationService.instance.scheduleForTask(task));
    }
  }

  /// Reassigns [orderedIds]' sortOrder to reflect the drag-and-drop order
  /// the caller wants for them — a project's task list, or the home
  /// screen's unfiled tasks, each reordered independently of the other.
  /// Every id in the list gets a fresh, small, strictly-decreasing
  /// sortOrder (simpler and more robust than fractional midpoint
  /// insertion), which — being far smaller than any timestamp-based
  /// sortOrder — always sorts below a task nobody has manually touched yet,
  /// without disturbing that task's position relative to others like it.
  void reorderTasks(List<String> orderedIds) {
    final n = orderedIds.length;
    final updatedById = <String, Task>{};
    for (var i = 0; i < n; i++) {
      final task = _box.get(orderedIds[i]);
      if (task == null) continue;
      final updated = task.copyWith(sortOrder: (n - i).toDouble());
      unawaited(_box.put(updated.id, updated));
      unawaited(_mirrorUpsert(updated, previous: task));
      updatedById[updated.id] = updated;
    }
    if (updatedById.isEmpty) return;
    state = [for (final t in state) updatedById[t.id] ?? t];
    _sortState();
  }

  /// Toggling a task cascades the new value down to every subtask. To
  /// toggle a single subtask, use [toggleSubtask] instead: the task is
  /// then checked exactly when all of its subtasks are.
  void toggleTask(String taskId) {
    final task = _box.get(taskId);
    if (task == null) return;
    final newValue = !task.isChecked;
    final updated = task.copyWith(
      isChecked: newValue,
      completedAt: newValue ? DateTime.now() : null,
      subtasks: [
        for (final subtask in task.subtasks)
          subtask.copyWith(isChecked: newValue),
      ],
    );
    _persist(updated);
    _syncNotificationForCompletionChange(updated);
    if (newValue) {
      unawaited(SoundService.instance.playCheckoff());
      _logActivity(
        updated,
        ActivityKind.taskCompleted,
        '$authorName completed "${updated.title}"',
      );
    }
  }

  void toggleSubtask(String taskId, String subtaskId) {
    final task = _box.get(taskId);
    if (task == null) return;
    final wasChecked = task.isChecked;
    final newSubtasks = [
      for (final subtask in task.subtasks)
        subtask.id == subtaskId
            ? subtask.copyWith(isChecked: !subtask.isChecked)
            : subtask,
    ];
    final nowChecked = newSubtasks.every((s) => s.isChecked);
    final updated = task.copyWith(
      subtasks: newSubtasks,
      isChecked: nowChecked,
      completedAt: nowChecked ? DateTime.now() : null,
    );
    _persist(updated);
    _syncNotificationForCompletionChange(updated);
    if (updated.isChecked && !wasChecked) {
      unawaited(SoundService.instance.playCheckoff());
    }
  }

  /// A completed task has nothing left to remind about, so its due-date
  /// notification (if any) is cancelled; un-completing it (still possible
  /// via [toggleTask]/[toggleSubtask]) puts it back if the due date hasn't
  /// passed yet.
  void _syncNotificationForCompletionChange(Task task) {
    if (task.isChecked) {
      unawaited(NotificationService.instance.cancelForTask(task));
    } else if (task.dueDate != null) {
      unawaited(NotificationService.instance.scheduleForTask(task));
    }
  }

  void setTaskNotes(String taskId, String? notes) {
    final task = _box.get(taskId);
    if (task == null) return;
    _persist(task.copyWith(notes: notes));
  }

  void setTaskDueDate(String taskId, DateTime? dueDate, {DateTime? dueDateEnd}) {
    final task = _box.get(taskId);
    if (task == null) return;
    final updated = task.copyWith(
      dueDate: dueDate,
      dueDateEnd: dueDate == null ? null : dueDateEnd,
    );
    _persist(updated);
    unawaited(NotificationService.instance.scheduleForTask(updated));
  }

  void setTaskPriority(String taskId, TaskPriority priority) {
    final task = _box.get(taskId);
    if (task == null) return;
    _persist(task.copyWith(priorityIndex: priority.index));
  }

  void addAttachments(String taskId, List<Attachment> attachments) {
    if (attachments.isEmpty) return;
    final task = _box.get(taskId);
    if (task == null) return;
    _persist(task.copyWith(attachments: [...task.attachments, ...attachments]));
  }

  void removeAttachment(String taskId, int index) {
    final task = _box.get(taskId);
    if (task == null) return;
    if (index < 0 || index >= task.attachments.length) return;
    _persist(
      task.copyWith(attachments: [...task.attachments]..removeAt(index)),
    );
  }

  void addSubtask(String taskId, String title) {
    final task = _box.get(taskId);
    if (task == null) return;
    final newSubtasks = [
      ...task.subtasks,
      Subtask(id: const Uuid().v4(), title: title),
    ];
    // A freshly-added, unchecked subtask means the task can no longer be
    // considered done.
    _persist(
      task.copyWith(
        subtasks: newSubtasks,
        isChecked: newSubtasks.every((s) => s.isChecked),
      ),
    );
  }

  void removeSubtask(String taskId, String subtaskId) {
    final task = _box.get(taskId);
    if (task == null) return;
    final newSubtasks = task.subtasks.where((s) => s.id != subtaskId).toList();
    _persist(
      task.copyWith(
        subtasks: newSubtasks,
        isChecked: newSubtasks.isEmpty
            ? task.isChecked
            : newSubtasks.every((s) => s.isChecked),
      ),
    );
  }

  void resetProgress(String taskId) {
    final task = _box.get(taskId);
    if (task == null) return;
    _persist(
      task.copyWith(
        isChecked: false,
        subtasks: [
          for (final subtask in task.subtasks)
            subtask.copyWith(isChecked: false),
        ],
      ),
    );
  }

  /// Deletes every task that belongs to [projectId], along with their
  /// subtasks (which live embedded in each task, so nothing else to clean
  /// up). Used when the project itself is deleted.
  void deleteTasksInProject(String projectId) {
    final toDelete = state.where((t) => t.projectId == projectId).toList();
    if (toDelete.isEmpty) return;
    for (final task in toDelete) {
      unawaited(NotificationService.instance.cancelForTask(task));
      unawaited(_box.delete(task.id));
      unawaited(_mirrorDelete(task.id));
    }
    final idsToDelete = toDelete.map((t) => t.id).toSet();
    state = state.where((t) => !idsToDelete.contains(t.id)).toList();
  }

  /// Wipes every task. Used by Settings > Wipe All Data. Local only — this
  /// never deletes anything from Supabase, since a wipe is meant to reset
  /// *this device*, not every teammate's shared data.
  void clearAll() {
    unawaited(NotificationService.instance.cancelAll());
    unawaited(_box.clear());
    state = [];
  }

  /// Replaces every task with [tasks]. Used when restoring from a backup —
  /// anything currently stored locally is discarded first. Mirrors every
  /// restored row to Supabase too (unlike [clearAll], this isn't meant to
  /// be local-only — see the `supabase/README.md` note on backup/restore).
  void restoreAll(List<Task> tasks) {
    unawaited(NotificationService.instance.cancelAll());
    unawaited(_replaceBoxContents(tasks));
    state = [...tasks];
    _sortState();
    for (final task in tasks) {
      unawaited(_mirrorUpsert(task));
      if (task.dueDate != null && !task.isChecked) {
        unawaited(NotificationService.instance.scheduleForTask(task));
      }
    }
  }

  /// Replaces [_box]'s entire contents with [tasks] — used by [restoreAll].
  /// `clear()` and `putAll()` are each async (the web/IndexedDB backend has
  /// no synchronous fast path for either), so firing them off unawaited in
  /// sequence — as every other fire-and-forget write in this class does —
  /// lets them race: if `clear()`'s own in-memory keystore wipe lands after
  /// `putAll()`'s, the just-restored tasks are wiped right back out from
  /// under the box, even though [state] (and so the UI) already reflects
  /// them. Awaiting `clear()` before starting `putAll()` keeps them in
  /// order. [state] no longer depends on reading `_box.values` back, so it
  /// stays correct regardless of how long this takes to land on disk.
  Future<void> _replaceBoxContents(List<Task> tasks) async {
    await _box.clear();
    await _box.putAll({for (final t in tasks) t.id: t});
  }
}
