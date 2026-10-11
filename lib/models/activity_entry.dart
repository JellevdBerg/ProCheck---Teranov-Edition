import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'activity_entry.g.dart';

/// What kind of event a project's [ActivityEntry] records — drives which
/// icon/color the Activity panel renders it with.
enum ActivityKind {
  projectCreated,
  taskAdded,
  taskCompleted,
  taskEdited;

  static ActivityKind fromIndex(int? index) {
    if (index == null || index < 0 || index >= ActivityKind.values.length) {
      return ActivityKind.taskEdited;
    }
    return ActivityKind.values[index];
  }
}

/// A single entry in a project's Activity log (see [Project.activityLog]).
/// [description] is pre-rendered text (e.g. `You completed "Buy milk"`)
/// rather than being reconstructed from structured fields — simpler, and
/// the log is display-only.
@HiveType(typeId: 6)
class ActivityEntry extends HiveObject {
  ActivityEntry({
    String? id,
    required this.kindIndex,
    required this.description,
    required this.timestamp,
  }) : id = id ?? const Uuid().v4();

  /// Lets `append_project_activity` (see
  /// `20261009100000_atomic_appends_and_profile_directory.sql`) recognize
  /// an entry it's already stored — an outbox replay (see
  /// [SyncableNotifier]) can call it again for the same entry, and without
  /// this it would append a duplicate instead of being a no-op.
  @HiveField(3, defaultValue: '')
  String id;

  @HiveField(0)
  int kindIndex;

  @HiveField(1)
  String description;

  @HiveField(2)
  DateTime timestamp;

  ActivityKind get kind => ActivityKind.fromIndex(kindIndex);

  @override
  bool operator ==(Object other) =>
      other is ActivityEntry &&
      other.id == id &&
      other.kindIndex == kindIndex &&
      other.description == description &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(id, kindIndex, description, timestamp);

  Map<String, dynamic> toJson() => {
    'id': id,
    'kindIndex': kindIndex,
    'description': description,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ActivityEntry.fromJson(Map<String, dynamic> json) => ActivityEntry(
    id: json['id'] as String?,
    kindIndex: json['kindIndex'] as int? ?? ActivityKind.taskEdited.index,
    description: json['description'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}
