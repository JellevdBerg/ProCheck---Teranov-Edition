import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_messenger.dart';
import '../data/hive_setup.dart';
import '../data/supabase_config.dart';
import '../models/outbox_entry.dart';
import 'sync_log_provider.dart';

/// Shared sync plumbing for [TasksNotifier]/[ProjectsNotifier]: loading the
/// signed-in user's own profile (for stamping new rows), a one-time pull on
/// construction, a realtime subscription that keeps [state] current, and a
/// persistent outbox that retries whatever that pull/mirror plumbing
/// couldn't reach Supabase with — previously duplicated near-identically
/// between the two notifiers.
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
  static Box<OutboxEntry> get _outboxBox =>
      Hive.box<OutboxEntry>(outboxBoxName);

  /// How many replay attempts a queued entry gets on a network failure
  /// before it's left queued (still counted, still retried on next app
  /// start) but no longer auto-retried this session.
  static const _maxOutboxAttempts = 8;

  Timer? _retryTimer;

  String _outboxKey(String rowId) => '$syncTable:$rowId';

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

  /// Queues [rowId] for retry after a network failure mirroring it —
  /// [payload] is the row's `toSupabase()` map for an upsert, or null for a
  /// delete. Coalesces per row: replaces whatever was already queued for
  /// [rowId], so only the latest local state for it is ever replayed.
  void enqueueOutbox(String rowId, Map<String, dynamic>? payload) {
    unawaited(
      _outboxBox.put(
        _outboxKey(rowId),
        OutboxEntry(
          table: syncTable,
          rowId: rowId,
          opIndex: (payload == null ? OutboxOp.delete : OutboxOp.upsert).index,
          payload: payload,
        ),
      ),
    );
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final pending = _outboxBox.values.where((e) => e.table == syncTable);
    if (pending.isEmpty) return;
    final attempts = pending.map((e) => e.attempts).reduce(max);
    if (attempts >= _maxOutboxAttempts) return;
    // 2s, 4s, 8s, ... capped at 2 minutes.
    final delay = Duration(seconds: min(120, 2 << attempts));
    _retryTimer = Timer(delay, () => unawaited(replayOutbox()));
  }

  /// Replays every queued local change for [syncTable], oldest first — one
  /// at a time, so an early failure doesn't abort the rest. Called once
  /// after the launch-time pull (covering both "app start" and "was
  /// offline at launch, network came back"), and again on its own backoff
  /// schedule for as long as entries remain.
  Future<void> replayOutbox() async {
    _retryTimer?.cancel();
    if (!isSupabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    final entries =
        _outboxBox.values.where((e) => e.table == syncTable).toList()
          ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    for (final entry in entries) {
      if (entry.attempts >= _maxOutboxAttempts) continue;
      try {
        if (entry.op == OutboxOp.delete) {
          await supabase.from(syncTable).delete().eq('id', entry.rowId);
        } else {
          await supabase.from(syncTable).upsert(entry.payload!);
        }
        unawaited(_outboxBox.delete(_outboxKey(entry.rowId)));
      } on PostgrestException catch (e) {
        // The server actively refused this — retrying won't change that
        // (RLS, a bad value, the row no longer existing). Drop it rather
        // than retrying forever; the local copy stays as the user left it
        // (there's no "previous" snapshot left to roll back to by the
        // time a *replay* is refused, unlike the original edit's own
        // same-request rejection), so tell them it never made it up.
        ref
            .read(syncLogProvider.notifier)
            .recordError(source: syncTable, action: 'outbox', error: e);
        unawaited(_outboxBox.delete(_outboxKey(entry.rowId)));
        showSyncFailureToast(
          'A change made while offline couldn\'t be saved: ${e.message}',
        );
      } catch (e) {
        // Still offline/unreachable — leave it queued and count the
        // attempt, so a permanently-stuck entry eventually stops being
        // retried every app start.
        unawaited(
          _outboxBox.put(_outboxKey(entry.rowId), entry
            ..attempts += 1),
        );
      }
    }
    _scheduleRetry();
  }

  void disposeSync() {
    _retryTimer?.cancel();
    final channel = _channel;
    if (channel != null) {
      unawaited(supabase.removeChannel(channel));
    }
  }
}
