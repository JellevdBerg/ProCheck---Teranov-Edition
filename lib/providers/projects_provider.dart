import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/app_messenger.dart';
import '../data/hive_setup.dart';
import '../data/supabase_config.dart';
import '../models/activity_entry.dart';
import '../models/project.dart';
import '../models/project_comment.dart';
import 'sync_log_provider.dart';
import 'syncable_notifier.dart';
import 'tasks_provider.dart';
import 'undo_provider.dart';

final projectsProvider = StateNotifierProvider<ProjectsNotifier, List<Project>>(
  (ref) {
    return ProjectsNotifier(ref);
  },
);

/// See [ProjectsNotifier.logActivity].
const _maxActivityLogEntries = 200;

/// Persistence to Hive is fire-and-forget: [state] is the source of truth
/// for the UI and is updated synchronously, while the on-disk copy catches
/// up in the background.
///
/// When Supabase is configured and signed in (see [isSupabaseConfigured]),
/// every write is additionally mirrored to the `projects` table — also
/// fire-and-forget — and a one-time pull on construction merges in
/// whatever's visible to this user there (their own projects, their
/// department's, per the RLS policies). See [SyncableNotifier] for the
/// profile-load/pull/realtime plumbing shared with [TasksNotifier].
class ProjectsNotifier extends StateNotifier<List<Project>>
    with SyncableNotifier<Project> {
  ProjectsNotifier(this.ref) : super(_box.values.toList()) {
    _sortState();
    unawaited(profileReady);
    unawaited(
      pullFromSupabase().then((_) {
        subscribeRealtime();
        unawaited(replayOutbox());
      }),
    );
  }

  @override
  final Ref ref;

  static Box<Project> get _box => Hive.box<Project>(projectBoxName);

  @override
  String get syncTable => 'projects';

  @override
  Box<Project> get syncBox => _box;

  @override
  Project rowFromSupabase(Map<String, dynamic> row) =>
      Project.fromSupabase(row);

  @override
  String idOf(Project item) => item.id;

  @override
  void resortState() {
    state = _box.values.toList();
    _sortState();
  }

  @override
  DateTime? updatedAtOf(Project item) => item.updatedAt;

  @override
  String describeConflict(Project? remote, UpsertOutcome outcome) =>
      outcome == UpsertOutcome.deletedRemotely
          ? 'A project was deleted elsewhere before your change reached it.'
          : '"${remote?.name ?? 'A project'}" was changed elsewhere — your offline edit wasn\'t applied.';

  @override
  void dispose() {
    disposeSync();
    super.dispose();
  }

  static final _neverOpened = DateTime.fromMillisecondsSinceEpoch(0);

  /// Every project — used where that's explicitly correct (backup export,
  /// Settings > Wipe All Data already clearing the whole box).
  List<Project> get allValues => _box.values.toList();

  /// Returns whether the row reached the server (false when skipped or
  /// failed), so a first-time insert can be followed by its append calls.
  Future<bool> _mirrorUpsert(
    Project project, {
    bool includeAppendOnly = false,
    Project? previous,
  }) async {
    if (!isSupabaseConfigured) return false;
    if (supabase.auth.currentUser == null) return false;
    // ownerId is blank for a project created before the profile resolves —
    // sending that as a uuid column fails server-side. The splash screen
    // now gates creation UI behind [profileReady], so this is only a
    // safety net (e.g. restoring very old local data).
    if (project.ownerId.isEmpty) return false;
    final payload = project.toSupabase(includeAppendOnly: includeAppendOnly);
    final result = await upsertWithConflictCheck(
      project.id,
      payload,
      baseUpdatedAt: previous?.updatedAt,
    );
    switch (result.outcome) {
      case UpsertOutcome.success:
        return true;
      case UpsertOutcome.conflict:
      case UpsertOutcome.deletedRemotely:
        ref.read(syncLogProvider.notifier).recordError(
              source: 'projects',
              action: 'upsert',
              error: 'changed elsewhere',
            );
        showSyncFailureToast(describeConflict(result.remote, result.outcome));
        return false;
      case UpsertOutcome.rejected:
        // The server actively refused this write (most commonly an RLS
        // policy) — roll the optimistic local update back (or remove a
        // brand-new project with no prior state) and tell the user.
        ref
            .read(syncLogProvider.notifier)
            .recordError(source: 'projects', action: 'upsert', error: result.error!);
        _rollback(project, previous, result.error!);
        return false;
      case UpsertOutcome.networkFailure:
        // Queued for retry (see [SyncableNotifier.replayOutbox]).
        ref
            .read(syncLogProvider.notifier)
            .recordError(source: 'projects', action: 'upsert', error: 'offline');
        enqueueOutbox(project.id, payload, baseUpdatedAt: previous?.updatedAt);
        return false;
    }
  }

  void _rollback(Project rejected, Project? previous, PostgrestException e) {
    if (previous != null) {
      unawaited(_box.put(previous.id, previous));
      state = [
        for (final p in state)
          if (p.id == previous.id) previous else p,
      ];
    } else {
      unawaited(_box.delete(rejected.id));
      state = state.where((p) => p.id != rejected.id).toList();
    }
    showSyncFailureToast('Couldn\'t save "${rejected.name}": ${e.message}');
  }

  /// Appends ONE comment/activity entry to the server's copy atomically (see
  /// `20261009100000_atomic_appends_and_profile_directory.sql`), so two
  /// people adding entries at once both land. The regular upsert no longer
  /// carries these columns.
  ///
  /// Falls back to the old whole-row upsert (columns included) when the
  /// function isn't deployed yet, or when the server doesn't have the row
  /// (e.g. a project created offline) — in the latter case that upsert is the
  /// insert, so the history still reaches the server. If RLS refuses the
  /// row, that upsert is refused the same way and logged, as before.
  Future<void> _appendRemote(
    String function,
    String param,
    String projectId,
    Map<String, dynamic> entry,
  ) async {
    if (!isSupabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    final project = _box.get(projectId);
    if (project == null || project.ownerId.isEmpty) return;
    try {
      await supabase.rpc(
        function,
        params: {'p_project_id': projectId, param: entry},
      );
    } catch (e) {
      final missingFunction = e is PostgrestException && e.code == 'PGRST202';
      final missingRow =
          e is PostgrestException &&
          e.message.contains('project not found or not permitted');
      if (missingFunction || missingRow) {
        final latest = _box.get(projectId);
        if (latest != null) {
          await _mirrorUpsert(latest, includeAppendOnly: true);
        }
        return;
      }
      ref
          .read(syncLogProvider.notifier)
          .recordError(source: 'projects', action: function, error: e);
    }
  }

  Future<void> _mirrorDelete(String projectId) async {
    if (!isSupabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    try {
      await supabase.from('projects').delete().eq('id', projectId);
    } catch (e) {
      // Best-effort — queued for retry if this was a network failure.
      ref
          .read(syncLogProvider.notifier)
          .recordError(source: 'projects', action: 'delete', error: e);
      enqueueOutbox(projectId, null);
    }
  }

  void _sortState() {
    final sorted = [...state]
      ..sort((a, b) {
        final recency = (b.lastOpenedAt ?? _neverOpened).compareTo(
          a.lastOpenedAt ?? _neverOpened,
        );
        if (recency != 0) return recency;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    state = sorted;
  }

  Project addProject(String name, {int colorIndex = 0}) {
    final project = Project(
      id: const Uuid().v4(),
      name: name,
      createdAt: DateTime.now(),
      colorIndex: colorIndex,
      ownerId: ownerId ?? '',
      departmentId: departmentId ?? '',
    );
    final created = ActivityEntry(
      kindIndex: ActivityKind.projectCreated.index,
      description: '$authorName created this project',
      timestamp: DateTime.now(),
    );
    project.activityLog.add(created);
    unawaited(_box.put(project.id, project));
    // The insert goes first (without the append-only columns); its "created"
    // entry then lands through the same atomic append as every later one.
    unawaited(
      _mirrorUpsert(project).then((inserted) {
        if (inserted) {
          return _appendRemote(
            'append_project_activity',
            'p_entry',
            project.id,
            created.toJson(),
          );
        }
      }),
    );
    state = [...state, project];
    _sortState();
    return project;
  }

  /// Persists [project] — a freshly built [Project.copyWith] instance,
  /// never the same object already in [state] — and swaps it into [state]
  /// in place. See [TasksNotifier._persist] for why a new instance (rather
  /// than mutating the box's cached one) is required for value-equality
  /// selectors to detect the edit.
  void _persist(Project project) {
    final previous = state.firstWhereOrNull((p) => p.id == project.id);
    unawaited(_box.put(project.id, project));
    unawaited(_mirrorUpsert(project, previous: previous));
    state = [
      for (final p in state)
        if (p.id == project.id) project else p,
    ];
  }

  void renameProject(String id, String name) {
    final project = _box.get(id);
    if (project == null) return;
    _persist(project.copyWith(name: name));
    _sortState();
  }

  void setProjectColor(String id, int colorIndex) {
    final project = _box.get(id);
    if (project == null) return;
    _persist(project.copyWith(colorIndex: colorIndex));
  }

  /// Marks a project as just opened, so it sorts to the front.
  void touchProject(String id) {
    final project = _box.get(id);
    if (project == null) return;
    _persist(project.copyWith(lastOpenedAt: DateTime.now()));
    _sortState();
  }

  /// Archives [id]: it drops out of the main grid/search without deleting
  /// anything, and stays reachable from the Archived tab.
  void archiveProject(String id) {
    final project = _box.get(id);
    if (project == null) return;
    _persist(project.copyWith(archived: true));
  }

  /// Hands the project to another department (IT / Operator only — the
  /// database rejects anyone else). Its tasks follow it.
  void setProjectDepartment(String id, String departmentId) {
    final project = _box.get(id);
    if (project == null) return;
    _persist(project.copyWith(departmentId: departmentId));
  }

  void toggleFavorite(String id) {
    final project = _box.get(id);
    if (project == null) return;
    _persist(project.copyWith(favorite: !project.favorite));
  }

  /// Appends an entry to [id]'s Activity log — called by [TasksNotifier] for
  /// task-level events (added/completed/edited) on tasks filed under a
  /// project, in addition to [addProject]'s own "created" entry.
  ///
  /// Capped to the most recent [_maxActivityLogEntries]: a long-lived
  /// project otherwise accumulates one entry per task event forever, and
  /// since the whole log is persisted with the project's Hive record (not
  /// lazily loaded), an uncapped log makes every single edit to that
  /// project progressively more expensive to save. The feed only ever
  /// shows the most recent entries anyway (see dashboard_screen.dart's
  /// `_buildActivityFeed`), so older ones being dropped is unobservable.
  void logActivity(String id, ActivityEntry entry) {
    final project = _box.get(id);
    if (project == null) return;
    final log = [...project.activityLog, entry];
    _persist(
      project.copyWith(
        activityLog: log.length > _maxActivityLogEntries
            ? log.sublist(log.length - _maxActivityLogEntries)
            : log,
      ),
    );
    unawaited(
      _appendRemote('append_project_activity', 'p_entry', id, entry.toJson()),
    );
  }

  void addComment(String id, String author, String text) {
    final project = _box.get(id);
    if (project == null) return;
    final comment = ProjectComment(
      id: const Uuid().v4(),
      author: author,
      text: text,
      timestamp: DateTime.now(),
    );
    _persist(project.copyWith(comments: [...project.comments, comment]));
    unawaited(
      _appendRemote(
        'append_project_comment',
        'p_comment',
        id,
        comment.toJson(),
      ),
    );
  }

  /// Puts an archived project back in the main grid.
  void unarchiveProject(String id) {
    final project = _box.get(id);
    if (project == null) return;
    _persist(project.copyWith(archived: false));
    _sortState();
  }

  void deleteProject(String id) {
    final project = _box.get(id);
    if (project == null) return;
    // Captured before the cascade below removes them from state, so the
    // undo entry can bring them back along with the project itself.
    final cascadedTasks = ref
        .read(tasksProvider)
        .where((t) => t.projectId == id)
        .toList();
    // Deleting a project takes its tasks (and their subtasks) with it.
    ref.read(tasksProvider.notifier).deleteTasksInProject(id);
    unawaited(_box.delete(id));
    unawaited(_mirrorDelete(id));
    state = state.where((p) => p.id != id).toList();
    ref
        .read(undoStackProvider.notifier)
        .push(ProjectDeletionEntry(project, cascadedTasks));
  }

  /// Re-adds a previously-deleted [project] exactly as it was — used by the
  /// undo stack to reverse [deleteProject]. Its cascade-deleted tasks are
  /// restored separately, by the same undo entry.
  void restoreProject(Project project) {
    unawaited(_box.put(project.id, project));
    unawaited(_mirrorUpsert(project));
    state = [...state, project];
    _sortState();
  }

  /// Wipes every project. Used by Settings > Wipe All Data. Local only —
  /// this never deletes anything from Supabase, since a wipe is meant to
  /// reset *this device*, not every teammate's shared data.
  void clearAll() {
    unawaited(_box.clear());
    state = [];
  }

  /// Replaces every project with [projects]. Used when restoring from a
  /// backup — anything currently stored is discarded first. Mirrors every
  /// restored row to Supabase too (unlike [clearAll], this isn't meant to
  /// be local-only — see the `supabase/README.md` note on backup/restore).
  void restoreAll(List<Project> projects) {
    unawaited(_replaceBoxContents(projects));
    state = [...projects];
    _sortState();
    for (final project in projects) {
      unawaited(_mirrorUpsert(project, includeAppendOnly: true));
    }
  }

  /// Replaces [_box]'s entire contents with [projects] — used by
  /// [restoreAll]. `clear()` and `putAll()` are each async with no
  /// synchronous fast path, so `clear()` must be awaited before `putAll()`
  /// starts — firing both off unawaited in sequence lets them race, and a
  /// `clear()` that lands after `putAll()` wipes the just-restored data
  /// back out of the box.
  Future<void> _replaceBoxContents(List<Project> projects) async {
    await _box.clear();
    await _box.putAll({for (final p in projects) p.id: p});
  }
}
