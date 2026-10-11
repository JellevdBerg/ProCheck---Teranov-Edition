import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../data/hive_setup.dart';
import '../models/outbox_entry.dart';

Box<OutboxEntry> get _outboxBox => Hive.box<OutboxEntry>(outboxBoxName);

/// Every queued local change to `tasks`/`projects`, live — the source for
/// the app shell's sync status indicator and its details list. Updates as
/// the outbox box changes (an edit queued, a replay succeeding, a Retry).
final outboxEntriesProvider = StreamProvider<List<OutboxEntry>>((ref) {
  return Stream.multi((controller) {
    void emit() => controller.add(_outboxBox.values.toList());
    emit();
    final subscription = _outboxBox.watch().listen((_) => emit());
    controller.onCancel = subscription.cancel;
  });
});

/// How many local task/project changes are still waiting to reach
/// Supabase (not yet given up on) — see [outboxEntriesProvider].
final outboxPendingCountProvider = Provider<int>((ref) {
  final entries = ref.watch(outboxEntriesProvider).valueOrNull ?? const [];
  return entries.where((e) => !e.failed).length;
});

/// How many queued changes the server has actively refused (RLS, etc.) —
/// these are never auto-retried; the status details list offers Retry.
final outboxFailedCountProvider = Provider<int>((ref) {
  final entries = ref.watch(outboxEntriesProvider).valueOrNull ?? const [];
  return entries.where((e) => e.failed).length;
});
