import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../data/hive_setup.dart';
import '../models/outbox_entry.dart';

/// How many local task/project changes are still waiting to reach
/// Supabase — kept here (rather than read out of [SyncableNotifier]
/// directly) so anything that just needs the count, like a future "syncing…"
/// indicator, doesn't have to depend on the tasks/projects notifiers
/// themselves. Updates live as the outbox box changes.
final outboxPendingCountProvider = StreamProvider<int>((ref) {
  final box = Hive.box<OutboxEntry>(outboxBoxName);
  return Stream.multi((controller) {
    controller.add(box.length);
    final subscription = box.watch().listen((_) => controller.add(box.length));
    controller.onCancel = subscription.cancel;
  });
});
