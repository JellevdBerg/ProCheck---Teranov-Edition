import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/hive_setup.dart';
import '../data/supabase_config.dart';
import '../models/activity_entry.dart';
import '../models/project.dart';
import '../models/project_comment.dart';
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
/// department's, per the RLS policies; see [TasksNotifier] for the
/// identical pattern on tasks). There's no realtime subscription yet, so a
/// teammate's change shows up on next launch, not live.
class ProjectsNotifier extends StateNotifier<List<Project>> {
  ProjectsNotifier(Ref ref) : _ref = ref, super(_box.values.toList()) {
    _sortState();
    unawaited(_loadOwnProfile());
    unawaited(_pullFromSupabase().then((_) => _subscribeRealtime()));
  }

  final Ref _ref;
  RealtimeChannel? _channel;

  static Box<Project> get _box => Hive.box<Project>(projectBoxName);

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      unawaited(supabase.removeChannel(channel));
    }
    super.dispose();
  }

  /// Subscribes to live inserts/updates/deletes on the `projects` table —
  /// see [TasksNotifier._subscribeRealtime] for the identical pattern and
  /// its caveats (RLS-governed, best-effort).
  void _subscribeRealtime() {
    if (!isSupabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    _channel = supabase
        .channel('projects_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'projects',
          callback: _handleRealtimeChange,
        )
        .subscribe();
  }

  void _handleRealtimeChange(PostgresChangePayload payload) {
    switch (payload.eventType) {
      case PostgresChangeEvent.delete:
        final id = payload.oldRecord['id'] as String?;
        if (id == null) return;
        unawaited(_box.delete(id));
        state = state.where((p) => p.id != id).toList();
      case PostgresChangeEvent.insert:
      case PostgresChangeEvent.update:
        final project = Project.fromSupabase(payload.newRecord);
        unawaited(_box.put(project.id, project));
        state = [
          for (final p in state)
            if (p.id == project.id) project else p,
          if (!state.any((p) => p.id == project.id)) project,
        ];
        _sortState();
      case PostgresChangeEvent.all:
        break;
    }
  }
  static final _neverOpened = DateTime.fromMillisecondsSinceEpoch(0);

  /// Every project — used where that's explicitly correct (backup export,
  /// Settings > Wipe All Data already clearing the whole box).
  List<Project> get allValues => _box.values.toList();

  /// Cached from the signed-in user's own `profiles` row — used to stamp
  /// [ownerId]/[departmentId] on projects created after this resolves. A
  /// project created before it resolves (a narrow window right after
  /// launch) falls back to blank, same as pure local/offline use.
  String? _ownerId;
  String? _departmentId;

  Future<void> _loadOwnProfile() async {
    if (!isSupabaseConfigured) return;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final row = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      _ownerId = userId;
      _departmentId = row['department_id'] as String?;
    } catch (_) {
      // Best-effort — local-only behavior continues if this fails.
    }
  }

  /// Pulls every project visible to this user on Supabase (per RLS) into
  /// the local box, then refreshes [state]. Best-effort: a failed/offline
  /// pull just leaves the local cache as it was.
  Future<void> _pullFromSupabase() async {
    if (!isSupabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    try {
      final rows = await supabase.from('projects').select();
      for (final row in rows as List) {
        final project = Project.fromSupabase(row as Map<String, dynamic>);
        await _box.put(project.id, project);
      }
      state = _box.values.toList();
      _sortState();
    } catch (_) {
      // Best-effort — local cache stays as it was.
    }
  }

  Future<void> _mirrorUpsert(Project project) async {
    if (!isSupabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    try {
      await supabase.from('projects').upsert(project.toSupabase());
    } catch (_) {
      // Best-effort — the local Hive copy is still correct; it just hasn't
      // reached the backend (offline, or an RLS policy refused it).
    }
  }

  Future<void> _mirrorDelete(String projectId) async {
    if (!isSupabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    try {
      await supabase.from('projects').delete().eq('id', projectId);
    } catch (_) {
      // Best-effort.
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
      ownerId: _ownerId ?? '',
      departmentId: _departmentId ?? '',
    );
    project.activityLog.add(
      ActivityEntry(
        kindIndex: ActivityKind.projectCreated.index,
        description: 'You created this project',
        timestamp: DateTime.now(),
      ),
    );
    unawaited(_box.put(project.id, project));
    unawaited(_mirrorUpsert(project));
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
    unawaited(_box.put(project.id, project));
    unawaited(_mirrorUpsert(project));
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
  }

  void addComment(String id, String author, String text) {
    final project = _box.get(id);
    if (project == null) return;
    _persist(
      project.copyWith(
        comments: [
          ...project.comments,
          ProjectComment(
            id: const Uuid().v4(),
            author: author,
            text: text,
            timestamp: DateTime.now(),
          ),
        ],
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
    final cascadedTasks = _ref
        .read(tasksProvider)
        .where((t) => t.projectId == id)
        .toList();
    // Deleting a project takes its tasks (and their subtasks) with it.
    _ref.read(tasksProvider.notifier).deleteTasksInProject(id);
    unawaited(_box.delete(id));
    unawaited(_mirrorDelete(id));
    state = state.where((p) => p.id != id).toList();
    _ref
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
  /// backup — anything currently stored is discarded first.
  void restoreAll(List<Project> projects) {
    unawaited(_replaceBoxContents(projects));
    state = [...projects];
    _sortState();
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
