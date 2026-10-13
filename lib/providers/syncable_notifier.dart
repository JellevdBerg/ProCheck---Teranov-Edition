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

/// What came of trying to push one row's upsert to Supabase — see
/// [SyncableNotifier.upsertWithConflictCheck].
enum UpsertOutcome {
  /// Landed. The mixin has already written the server's own copy of the
  /// row (picked up via `.select()`, so it carries the server-assigned
  /// `updated_at`) back into [SyncableNotifier.syncBox].
  success,

  /// Refused because [SyncWriteResult.baseUpdatedAt] no longer matched the
  /// row's current `updated_at` — someone else changed it first. Per the
  /// spec, the server wins outright (no merge): the mixin has already
  /// overwritten the local copy with the server's current row.
  conflict,

  /// The row no longer exists server-side (deleted by someone else while
  /// this edit sat unsent). The mixin has already removed it locally.
  deletedRemotely,

  /// The server actively refused the write (RLS, a bad value) — retrying
  /// won't change that.
  rejected,

  /// Couldn't reach the server at all (offline, timeout, DNS).
  networkFailure,
}

/// Whether an auth event should trigger a fresh sync: someone signed in
/// whose data this notifier hasn't synced yet (first sign-in, or signing back
/// in after a sign-out wiped the local cache).
bool needsResync({
  required AuthChangeEvent event,
  required String? sessionUserId,
  required String? syncedUserId,
}) {
  if (event == AuthChangeEvent.signedOut) return false;
  return sessionUserId != null && sessionUserId != syncedUserId;
}

class SyncWriteResult<T> {
  const SyncWriteResult(this.outcome, {this.remote, this.error});

  final UpsertOutcome outcome;

  /// The server's current copy of the row — set for [UpsertOutcome.success]
  /// and [UpsertOutcome.conflict].
  final T? remote;

  final PostgrestException? error;
}

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

  /// This row's last-known server `updated_at`, or null if it was never
  /// confirmed on the server — used as the optimistic-concurrency check in
  /// [upsertWithConflictCheck].
  DateTime? updatedAtOf(T item);

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
  late Future<void> profileReady = _loadOwnProfile();

  StreamSubscription<AuthState>? _authSub;
  String? _syncedUserId;

  /// Re-runs the profile load, pull and realtime subscription whenever a
  /// different/new session appears. The constructor-time sync only covers
  /// the user signed in at launch; without this, signing out (which clears
  /// the local cache) and back in left the notifiers empty and session-less
  /// until the app was restarted. Call once from the notifier's constructor.
  void listenForSignIn() {
    if (!isSupabaseConfigured) return;
    _syncedUserId = supabase.auth.currentUser?.id;
    _authSub = supabase.auth.onAuthStateChange.listen((auth) {
      if (auth.event == AuthChangeEvent.signedOut) _syncedUserId = null;
      final userId = auth.session?.user.id;
      if (!needsResync(
        event: auth.event,
        sessionUserId: userId,
        syncedUserId: _syncedUserId,
      )) {
        return;
      }
      _syncedUserId = userId;
      unawaited(_resyncForNewSession());
    });
  }

  Future<void> _resyncForNewSession() async {
    ownerId = null;
    departmentId = null;
    _authorName = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) await supabase.removeChannel(channel);
    profileReady = _loadOwnProfile();
    await profileReady;
    await pullFromSupabase();
    subscribeRealtime();
    await replayOutbox();
  }

  Future<void> _loadOwnProfile() async {
    if (!isSupabaseConfigured) return;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _clearIfDifferentAccount(userId);
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

  /// Hive boxes live on the device, not per-account — without this, signing
  /// in as someone else on the same machine would surface the previous
  /// account's cached tasks/projects (and retry their stuck outbox entries)
  /// until this account's own pull happened to overwrite them. Keyed off
  /// the last signed-in user id recorded in the settings box; a first-ever
  /// sign-in on this device (no recorded id) clears nothing.
  Future<void> _clearIfDifferentAccount(String userId) async {
    final settings = Hive.box(settingsBoxName);
    const key = 'lastSignedInUserId';
    final last = settings.get(key) as String?;
    if (last != null && last != userId) {
      await syncBox.clear();
      await _outboxBox.clear();
      resortState();
    }
    unawaited(settings.put(key, userId));
  }

  Future<void> pullFromSupabase() async {
    if (!isSupabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    try {
      final rows = await supabase.from(syncTable).select();
      final pendingIds = _outboxBox.values
          .where((e) => e.table == syncTable)
          .map((e) => e.rowId)
          .toSet();
      for (final row in rows as List) {
        final item = rowFromSupabase(row as Map<String, dynamic>);
        // A row with an unresolved outbox entry keeps this device's own
        // pending edit rather than being clobbered by the pre-edit (or
        // otherwise stale) server copy — same reasoning as the realtime
        // guard in [handleRealtimeChange].
        if (pendingIds.contains(idOf(item))) continue;
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
        if (_outboxBox.containsKey(_outboxKey(id))) return;
        unawaited(syncBox.delete(id));
        resortState();
      case PostgresChangeEvent.insert:
      case PostgresChangeEvent.update:
        final item = rowFromSupabase(payload.newRecord);
        final id = idOf(item);
        // This device has an unresolved local edit for the same row — keep
        // it rather than overwriting it with whatever just came over
        // realtime; the outbox replay (or its conflict check) is what
        // gets to decide this row's fate next, not an unrelated event.
        if (_outboxBox.containsKey(_outboxKey(id))) return;
        unawaited(syncBox.put(id, item));
        resortState();
      case PostgresChangeEvent.all:
        break;
    }
  }

  /// Pushes one row's upsert, gated on [baseUpdatedAt] when it's not null:
  /// the write only lands if the row's `updated_at` on the server still
  /// matches what this device last saw. A mismatch means someone else
  /// changed it first — per spec, the server wins outright (no merge UI):
  /// this device's edit is dropped and its local copy is overwritten with
  /// whatever the server now has. [baseUpdatedAt] null means this row was
  /// never confirmed on the server (a brand-new local row), so it's a
  /// plain insert instead.
  Future<SyncWriteResult<T>> upsertWithConflictCheck(
    String rowId,
    Map<String, dynamic> payload, {
    DateTime? baseUpdatedAt,
  }) async {
    try {
      final response = baseUpdatedAt == null
          ? await supabase.from(syncTable).upsert(payload).select()
          : await supabase
                .from(syncTable)
                .update(payload)
                .eq('id', rowId)
                .eq('updated_at', baseUpdatedAt.toIso8601String())
                .select();
      if (response.isNotEmpty) {
        final remote = rowFromSupabase(response.first);
        await syncBox.put(idOf(remote), remote);
        resortState();
        return SyncWriteResult(UpsertOutcome.success, remote: remote);
      }
      // The condition matched nothing: either the row's `updated_at` moved
      // on since, or it's gone. Read its current state either way so the
      // local copy stops disagreeing with the server.
      final rows = await supabase.from(syncTable).select().eq('id', rowId);
      if (rows.isEmpty) {
        await syncBox.delete(rowId);
        resortState();
        return const SyncWriteResult(UpsertOutcome.deletedRemotely);
      }
      final remote = rowFromSupabase(rows.first);
      await syncBox.put(idOf(remote), remote);
      resortState();
      // Still exactly the version this edit was based on, yet nothing was
      // updated: nobody beat us to it — RLS let us read the row (a
      // department-mate's) but not change it. Not a conflict.
      final remoteAt = updatedAtOf(remote);
      if (remoteAt != null && remoteAt.isAtSameMomentAs(baseUpdatedAt!)) {
        return SyncWriteResult(
          UpsertOutcome.rejected,
          error: PostgrestException(
            message: "You don't have permission to change this",
            code: '42501',
          ),
        );
      }
      return SyncWriteResult(UpsertOutcome.conflict, remote: remote);
    } on PostgrestException catch (e) {
      return SyncWriteResult(UpsertOutcome.rejected, error: e);
    } catch (e) {
      return const SyncWriteResult(UpsertOutcome.networkFailure);
    }
  }

  /// Queues [rowId] for retry after a network failure mirroring it —
  /// [payload] is the row's `toSupabase()` map for an upsert, or null for a
  /// delete; [baseUpdatedAt] carries the conflict-check value through to
  /// the eventual replay (see [upsertWithConflictCheck]). Coalesces per
  /// row: replaces whatever was already queued for [rowId], so only the
  /// latest local state for it is ever replayed.
  void enqueueOutbox(
    String rowId,
    Map<String, dynamic>? payload, {
    DateTime? baseUpdatedAt,
  }) {
    unawaited(
      _outboxBox.put(
        _outboxKey(rowId),
        OutboxEntry(
          table: syncTable,
          rowId: rowId,
          opIndex: (payload == null ? OutboxOp.delete : OutboxOp.upsert).index,
          payload: payload,
          baseUpdatedAt: baseUpdatedAt?.toIso8601String(),
        ),
      ),
    );
    _scheduleRetry();
  }

  /// Resets a [OutboxEntry.failed] entry and retries it right away — the
  /// status details list's Retry action.
  Future<void> retryOutboxEntry(String rowId) async {
    final key = _outboxKey(rowId);
    final entry = _outboxBox.get(key);
    if (entry == null) return;
    entry.failed = false;
    entry.attempts = 0;
    entry.lastError = null;
    await _outboxBox.put(key, entry);
    await replayOutbox();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final pending = _outboxBox.values.where(
      (e) => e.table == syncTable && !e.failed,
    );
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
  /// schedule for as long as unfailed entries remain.
  Future<void> replayOutbox() async {
    _retryTimer?.cancel();
    if (!isSupabaseConfigured) return;
    if (supabase.auth.currentUser == null) return;
    final entries =
        _outboxBox.values
            .where((e) => e.table == syncTable && !e.failed)
            .toList()
          ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    for (final entry in entries) {
      if (entry.attempts >= _maxOutboxAttempts) continue;
      final key = _outboxKey(entry.rowId);
      if (entry.op == OutboxOp.delete) {
        try {
          await supabase.from(syncTable).delete().eq('id', entry.rowId);
          unawaited(_outboxBox.delete(key));
        } on PostgrestException catch (e) {
          _markFailed(entry, key, e);
        } catch (e) {
          unawaited(_outboxBox.put(key, entry..attempts += 1));
        }
        continue;
      }
      final result = await upsertWithConflictCheck(
        entry.rowId,
        entry.payload!,
        baseUpdatedAt: entry.baseUpdatedAt == null
            ? null
            : DateTime.parse(entry.baseUpdatedAt!),
      );
      switch (result.outcome) {
        case UpsertOutcome.success:
          unawaited(_outboxBox.delete(key));
        case UpsertOutcome.conflict:
        case UpsertOutcome.deletedRemotely:
          unawaited(_outboxBox.delete(key));
          ref
              .read(syncLogProvider.notifier)
              .recordError(
                source: syncTable,
                action: 'outbox',
                error: 'changed elsewhere while offline',
              );
          showSyncFailureToast(
            describeConflict(result.remote, result.outcome),
          );
        case UpsertOutcome.rejected:
          _markFailed(entry, key, result.error!);
        case UpsertOutcome.networkFailure:
          unawaited(_outboxBox.put(key, entry..attempts += 1));
      }
    }
    _scheduleRetry();
  }

  /// A one-line message for the toast/details list when [UpsertOutcome]
  /// is [UpsertOutcome.conflict]/[UpsertOutcome.deletedRemotely] — each
  /// notifier knows how to name its own row (a task's title, a project's
  /// name).
  String describeConflict(T? remote, UpsertOutcome outcome);

  void _markFailed(OutboxEntry entry, String key, PostgrestException e) {
    // The server actively refused this — retrying won't change that (RLS,
    // a bad value, the row no longer existing to update). Left in the
    // outbox (so the status UI can show it) but never retried again
    // automatically; the user's own Retry action is what tries it again.
    ref.read(syncLogProvider.notifier).recordError(
          source: syncTable,
          action: 'outbox',
          error: e,
        );
    entry.failed = true;
    entry.lastError = e.message;
    unawaited(_outboxBox.put(key, entry));
  }

  void disposeSync() {
    _authSub?.cancel();
    _retryTimer?.cancel();
    final channel = _channel;
    if (channel != null) {
      unawaited(supabase.removeChannel(channel));
    }
  }
}
