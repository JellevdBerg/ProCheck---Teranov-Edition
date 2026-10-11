import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:procheck/data/hive_setup.dart';
import 'package:procheck/models/outbox_entry.dart';
import 'package:procheck/providers/tasks_provider.dart';

// No SUPABASE_URL/SUPABASE_ANON_KEY dart-define in `flutter test`, so
// isSupabaseConfigured is false and every mirror/pull/replay call in
// TasksNotifier is a no-op — this only exercises the outbox's own
// coalescing, independent of ever actually reaching Supabase.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('procheck_outbox_test_');
    await setUpHive(testDirectoryPath: tempDir.path);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  test('enqueueOutbox coalesces repeated edits to the same row', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(tasksProvider.notifier);
    final box = Hive.box<OutboxEntry>(outboxBoxName);

    notifier.enqueueOutbox('row-1', {'title': 'first'});
    notifier.enqueueOutbox('row-1', {'title': 'second'});
    // Hive's in-memory keystore updates synchronously on put(); the
    // unawaited Future is only the disk flush, so no delay is needed
    // before reading it back.

    final entries = box.values.where((e) => e.rowId == 'row-1').toList();
    expect(entries, hasLength(1));
    expect(entries.single.payload?['title'], 'second');
    expect(entries.single.op, OutboxOp.upsert);

    notifier.enqueueOutbox('row-1', null);
    final afterDelete =
        box.values.where((e) => e.rowId == 'row-1').toList();
    expect(afterDelete, hasLength(1));
    expect(afterDelete.single.op, OutboxOp.delete);
  });
}
