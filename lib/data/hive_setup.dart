import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/activity_entry.dart';
import '../models/attachment.dart';
import '../models/outbox_entry.dart';
import '../models/project.dart';
import '../models/project_comment.dart';
import '../models/subtask.dart';
import '../models/task.dart';
import '../models/task_template.dart';
import '../models/template_subtask.dart';

const projectBoxName = 'projects';
const taskBoxName = 'tasks';
const taskTemplateBoxName = 'task_templates';
const settingsBoxName = 'settings';

/// Pending `tasks`/`projects` writes that a flaky connection kept from
/// reaching Supabase — see [SyncableNotifier]. Not wiped by
/// Settings > Wipe All Data (that resets *this device's* cache, not
/// in-flight syncs) but is cleared on sign-out, same as [taskBoxName]/
/// [projectBoxName] — see `auth_provider.dart`.
const outboxBoxName = 'outbox';

/// Hive box files that live directly in the data directory (each has a
/// matching `.lock` file), used when migrating data to a new location.
const _boxFileNames = [
  projectBoxName,
  taskBoxName,
  taskTemplateBoxName,
  settingsBoxName,
  outboxBoxName,
];

/// Initializes Hive and opens the app's boxes.
///
/// Pass [testDirectoryPath] in tests to store data on disk without going
/// through the `path_provider` platform channel.
Future<void> setUpHive({String? testDirectoryPath}) async {
  if (testDirectoryPath != null) {
    Hive.init(testDirectoryPath);
  } else if (!kIsWeb && Platform.isWindows) {
    Hive.init((await _windowsDataDirectory()).path);
  } else {
    await Hive.initFlutter();
  }

  _registerAdapter(SubtaskAdapter());
  _registerAdapter(TaskAdapter());
  _registerAdapter(ProjectAdapter());
  _registerAdapter(TemplateSubtaskAdapter());
  _registerAdapter(TaskTemplateAdapter());
  _registerAdapter(AttachmentAdapter());
  _registerAdapter(ActivityEntryAdapter());
  _registerAdapter(ProjectCommentAdapter());
  _registerAdapter(OutboxEntryAdapter());

  await Future.wait([
    Hive.openBox<Project>(projectBoxName,
        compactionStrategy: _compactionStrategy),
    Hive.openBox<Task>(taskBoxName, compactionStrategy: _compactionStrategy),
    Hive.openBox<TaskTemplate>(taskTemplateBoxName,
        compactionStrategy: _compactionStrategy),
    Hive.openBox(settingsBoxName, compactionStrategy: _compactionStrategy),
    Hive.openBox<OutboxEntry>(outboxBoxName,
        compactionStrategy: _compactionStrategy),
  ]);
}

/// Every delete and every overwrite of an existing key leaves a stale frame
/// behind in the box's file on disk until it's compacted. Hive's own default
/// strategy only compacts once deleted frames are both more than 60 AND over
/// 15% of the box, so a box that mostly grows (task/project edits far
/// outnumber deletions) can accumulate thousands of dead frames — and a
/// correspondingly bloated file — without ever crossing that 15% ratio.
/// This strategy drops the ratio requirement and compacts on the absolute
/// count alone, so dead frames actually get reclaimed as the app is used.
bool _compactionStrategy(int entries, int deletedEntries) =>
    deletedEntries > 60;

/// Older versions stored data loose in the user's Documents folder — Windows'
/// "application documents directory" has no app-specific subfolder of its
/// own, so that's just the user's actual Documents. Data now lives under
/// `%LocalAppData%\ProCheck` instead. Any box not yet present there is
/// copied over from the old location the first time this runs; the
/// originals are left in place rather than deleted.
Future<Directory> _windowsDataDirectory() async {
  final localAppData = Platform.environment['LOCALAPPDATA'];
  final dataDir = localAppData != null
      ? Directory('$localAppData${Platform.pathSeparator}ProCheck')
      : await getApplicationSupportDirectory();
  if (!dataDir.existsSync()) {
    dataDir.createSync(recursive: true);
  }

  final legacyDir = await getApplicationDocumentsDirectory();
  for (final name in _boxFileNames) {
    final newHiveFile = File(
      '${dataDir.path}${Platform.pathSeparator}$name.hive',
    );
    if (newHiveFile.existsSync()) continue;

    for (final suffix in ['.hive', '.lock']) {
      final legacyFile = File(
        '${legacyDir.path}${Platform.pathSeparator}$name$suffix',
      );
      if (legacyFile.existsSync()) {
        legacyFile.copySync(
          '${dataDir.path}${Platform.pathSeparator}$name$suffix',
        );
      }
    }
  }

  return dataDir;
}

/// Re-running [setUpHive] (e.g. once per widget test) must not re-register
/// an adapter for a typeId that's already registered.
void _registerAdapter<T>(TypeAdapter<T> adapter) {
  if (!Hive.isAdapterRegistered(adapter.typeId)) {
    Hive.registerAdapter(adapter);
  }
}
