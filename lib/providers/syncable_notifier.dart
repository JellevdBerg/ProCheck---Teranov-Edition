import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_config.dart';
import 'sync_log_provider.dart';

/// Shared sync plumbing for [TasksNotifier]/[ProjectsNotifier]: loading the
/// signed-in user's own profile (for stamping new rows), a one-time pull on
/// construction, and a realtime subscription that keeps [state] current —
/// previously duplicated near-identically between the two notifiers.
///
/// A mixing class `T` supplies the table name and row mapping; everything
/// else (profile caching, best-effort error logging, channel lifecycle) is
/// identical between tasks and projects.
mixin SyncableNotifier<T> on StateNotifier<List<T>> {
  Ref get ref;

  /// The Supabase table this notifier mirrors, and the `source` tag used in
  /// [syncLogProvider] entries — e.g. `'tasks'` or `'projects'`.
  String get syncTable;

  Box<T> get syncBox;

  T rowFromSupabase(Map<String, dynamic> row);

  String idOf(T item);

  /// Replaces [state] with the full local box contents, sorted — called
  /// after a pull or a realtime change lands.
  void resortState();

  RealtimeChannel? _channel;

  /// Cached from the signed-in user's own `profiles` row — used to stamp
  /// `ownerId`/`departmentId` on rows created after this resolves.
  String? ownerId;
  String? departmentId;

  String? _authorName;
  String get authorName =>
      (_authorName?.isNotEmpty ?? false) ? _authorName! : 'You';

  /// Resolves once the profile load (or the decision that there's nothing
  /// to load) finishes — the splash screen awaits this on every notifier
  /// before handing off to the app shell, so task/project creation never
  /// races ahead of [ownerId] being set. See `splash_screen.dart`.
  late final Future<void> profileReady = _loadOwnProfile();

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
      ownerId = userId;
      departmentId = row['department_id'] as String?;
      _authorName = row['display_name'] as String?;
    } catch (_) {
      // Best-effort — local-only behavior continues if this fails.
    }
  }

  Future<void> pullFromSupabase() async {
    if (!isSupabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    try {
      final rows = await supabase.from(syncTable).select();
      for (final row in rows as List) {
        final item = rowFromSupabase(row as Map<String, dynamic>);
        await syncBox.put(idOf(item), item);
      }
      resortState();
      ref.read(syncLogProvider.notifier).recordSuccessfulPull();
    } catch (e) {
      // Best-effort — local cache stays as it was.
      ref
          .read(syncLogProvider.notifier)
          .recordError(source: syncTable, action: 'pull', error: e);
    }
  }

  /// Subscribes to live inserts/updates/deletes on [syncTable] so a
  /// teammate's change shows up immediately rather than only on next
  /// launch. RLS still governs which rows this client actually receives —
  /// this just reacts to whatever comes through. Best-effort: a failed
  /// subscribe leaves the app working exactly as it did with only the
  /// launch-time pull.
  void subscribeRealtime() {
    if (!isSupabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    _channel = supabase
        .channel('${syncTable}_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: syncTable,
          callback: handleRealtimeChange,
        )
        .subscribe();
  }

  void handleRealtimeChange(PostgresChangePayload payload) {
    switch (payload.eventType) {
      case PostgresChangeEvent.delete:
        // The old row only carries its primary key once deleted.
        final id = payload.oldRecord['id'] as String?;
        if (id == null) return;
        unawaited(syncBox.delete(id));
        resortState();
      case PostgresChangeEvent.insert:
      case PostgresChangeEvent.update:
        final item = rowFromSupabase(payload.newRecord);
        unawaited(syncBox.put(idOf(item), item));
        resortState();
      case PostgresChangeEvent.all:
        break;
    }
  }

  void disposeSync() {
    final channel = _channel;
    if (channel != null) {
      unawaited(supabase.removeChannel(channel));
    }
  }
}
