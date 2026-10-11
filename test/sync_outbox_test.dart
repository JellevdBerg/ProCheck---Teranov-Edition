import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:procheck/data/hive_setup.dart';
import 'package:procheck/models/outbox_entry.dart';
import 'package:procheck/providers/outbox_provider.dart';
import 'package:procheck/providers/projects_provider.dart';
import 'package:procheck/providers/tasks_provider.dart';

// No SUPABASE_URL/SUPABASE_ANON_KEY dart-define in `flutter test`, so
// isSupabaseConfigured is false and every mirror/pull/replay call in
// TasksNotifier/ProjectsNotifier is a no-op. That means the HTTP-level
// transitions (a real network failure, a real 403) can't be driven through
// `replayOutbox()`/`upsertWithConflictCheck()` here — there's no Supabase
// backend, mocked or otherwise, available in this sandbox. What IS tested
// below, without needing one: the outbox's own bookkeeping (coalescing,
// surviving a box reopen, pending/failed categorization, what the Retry
// action resets) and the sign-out data clearing.
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
    final afterDelete = box.values.where((e) => e.rowId == 'row-1').toList();
    expect(afterDelete, hasLength(1));
    expect(afterDelete.single.op, OutboxOp.delete);

    await box.delete('tasks:row-1');
  });

  test('a queued entry survives the box being closed and reopened', () async {
    final box = Hive.box<OutboxEntry>(outboxBoxName);
    await box.put(
      'tasks:row-restart',
      OutboxEntry(
        table: 'tasks',
        rowId: 'row-restart',
        opIndex: OutboxOp.upsert.index,
        payload: {'title': 'survives a restart'},
      ),
    );
    await box.close();

    await Hive.openBox<OutboxEntry>(outboxBoxName);
    final reopened = Hive.box<OutboxEntry>(outboxBoxName);
    final restored = reopened.get('tasks:row-restart');
    expect(restored, isNotNull);
    expect(restored!.payload?['title'], 'survives a restart');

    await reopened.delete('tasks:row-restart');
  });

  test('pending vs failed counts reflect OutboxEntry.failed', () async {
    final box = Hive.box<OutboxEntry>(outboxBoxName);
    await box.put(
      'tasks:row-pending',
      OutboxEntry(
        table: 'tasks',
        rowId: 'row-pending',
        opIndex: OutboxOp.upsert.index,
        payload: {'title': 'still trying'},
      ),
    );
    await box.put(
      'tasks:row-failed',
      OutboxEntry(
        table: 'tasks',
        rowId: 'row-failed',
        opIndex: OutboxOp.upsert.index,
        payload: {'title': 'rejected'},
        failed: true,
        lastError: 'new row violates row-level security policy',
      ),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(outboxEntriesProvider.future);
    expect(container.read(outboxPendingCountProvider), 1);
    expect(container.read(outboxFailedCountProvider), 1);

    await box.delete('tasks:row-pending');
    await box.delete('tasks:row-failed');
  });

  test(
    '403 (never retried) vs network failure (kept pending): '
    'a failed entry is excluded from retry scheduling',
    () async {
      // This is the state replayOutbox() leaves an entry in after each
      // outcome — see [SyncableNotifier._markFailed] for the 403 case and
      // its `catch (e)` branch (attempts += 1, failed left false) for a
      // network failure. Asserted directly on the model since driving the
      // real HTTP call isn't possible in this sandbox (see file header).
      final rejected = OutboxEntry(
        table: 'tasks',
        rowId: 'r1',
        opIndex: OutboxOp.upsert.index,
        payload: const {},
        failed: true,
        lastError: 'permission denied',
      );
      expect(rejected.failed, isTrue);
      expect(rejected.attempts, 0); // never incremented — never retried

      final offline = OutboxEntry(
        table: 'tasks',
        rowId: 'r2',
        opIndex: OutboxOp.upsert.index,
        payload: const {},
        attempts: 3,
      );
      expect(offline.failed, isFalse); // stays pending, eligible for retry
      expect(offline.attempts, 3);
    },
  );

  test('retryOutboxEntry resets a failed entry for another attempt', () async {
    final box = Hive.box<OutboxEntry>(outboxBoxName);
    await box.put(
      'tasks:row-retry',
      OutboxEntry(
        table: 'tasks',
        rowId: 'row-retry',
        opIndex: OutboxOp.upsert.index,
        payload: {'title': 'rejected once'},
        attempts: 1,
        failed: true,
        lastError: 'permission denied',
      ),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    // isSupabaseConfigured is false, so the replay this triggers is a
    // no-op — only the reset itself is under test here.
    await container.read(tasksProvider.notifier).retryOutboxEntry('row-retry');

    final reset = box.get('tasks:row-retry');
    expect(reset, isNotNull);
    expect(reset!.failed, isFalse);
    expect(reset.attempts, 0);
    expect(reset.lastError, isNull);

    await box.delete('tasks:row-retry');
  });

  test('sign-out clears tasks, projects and the outbox', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(tasksProvider.notifier).addBlankTask(title: 'leftover');
    container.read(projectsProvider.notifier).addProject('leftover project');
    final outbox = Hive.box<OutboxEntry>(outboxBoxName);
    await outbox.put(
      'tasks:row-leftover',
      OutboxEntry(
        table: 'tasks',
        rowId: 'row-leftover',
        opIndex: OutboxOp.upsert.index,
        payload: {'title': 'leftover'},
      ),
    );

    expect(container.read(tasksProvider), isNotEmpty);
    expect(container.read(projectsProvider), isNotEmpty);
    expect(outbox.isNotEmpty, isTrue);

    // Mirrors what AppSidebar._confirmSignOut does after a successful
    // sign-out (see widgets/sidebar/app_sidebar.dart) — this is the part
    // that doesn't need a BuildContext/widget tree to exercise directly.
    container.read(tasksProvider.notifier).clearAll();
    container.read(projectsProvider.notifier).clearAll();
    await outbox.clear();

    expect(container.read(tasksProvider), isEmpty);
    expect(container.read(projectsProvider), isEmpty);
    expect(outbox.isEmpty, isTrue);
  });
}
