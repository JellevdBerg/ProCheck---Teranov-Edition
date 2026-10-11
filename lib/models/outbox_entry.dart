import 'package:hive/hive.dart';

part 'outbox_entry.g.dart';

/// Whether a queued [OutboxEntry] is a pending upsert or a pending delete.
enum OutboxOp {
  upsert,
  delete;

  static OutboxOp fromIndex(int index) => OutboxOp.values[index];
}

/// One row's worth of unsent local change to `tasks`/`projects` — written
/// when a mirror write to Supabase fails with something other than an
/// outright server rejection (offline, DNS hiccup, timeout) so it survives
/// an app restart and gets replayed once the connection comes back. Keyed
/// by [table]+[rowId] in its box (see [SyncableNotifier.outboxKey]) so a
/// second edit to the same row before the first one replays just replaces
/// this entry rather than queuing twice.
@HiveType(typeId: 8)
class OutboxEntry extends HiveObject {
  OutboxEntry({
    required this.table,
    required this.rowId,
    required this.opIndex,
    this.payload,
    this.attempts = 0,
    DateTime? queuedAt,
  }) : queuedAt = queuedAt ?? DateTime.now();

  /// `'tasks'` or `'projects'`.
  @HiveField(0)
  String table;

  @HiveField(1)
  String rowId;

  @HiveField(2)
  int opIndex;

  /// The row's `toSupabase()` map for an upsert; null for a delete.
  @HiveField(3)
  Map<String, dynamic>? payload;

  /// How many replay attempts have failed on a network error so far —
  /// stops auto-retrying past a cap (see [SyncableNotifier.replayOutbox])
  /// so a permanently-unreachable row doesn't retry forever; it stays
  /// queued (and counted) but is only retried again on the next app start.
  @HiveField(4)
  int attempts;

  @HiveField(5)
  DateTime queuedAt;

  OutboxOp get op => OutboxOp.fromIndex(opIndex);
}
