import 'package:collection/collection.dart';
import 'package:hive/hive.dart';

import 'activity_entry.dart';
import 'project_comment.dart';

part 'project.g.dart';

/// Distinguishes "leave this field as-is" from "set it to null" in
/// [Project.copyWith], since a bare `= null` default can't tell the two
/// apart.
const _unset = Object();

/// Still a local Hive object — see the note on [Task] in task.dart for how
/// this mirrors to Supabase once configured.
@HiveType(typeId: 2)
class Project extends HiveObject {
  Project({
    required this.id,
    required this.name,
    required this.createdAt,
    this.lastOpenedAt,
    this.colorIndex = 0,
    this.archived = false,
    this.favorite = false,
    List<ActivityEntry>? activityLog,
    List<ProjectComment>? comments,
    this.ownerId = '',
    this.departmentId = '',
  }) : activityLog = activityLog ?? [],
       comments = comments ?? [];

  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  DateTime createdAt;

  /// Null until the project has been opened at least once.
  @HiveField(3)
  DateTime? lastOpenedAt;

  /// Index into [accentPalette] (see settings_provider.dart). Projects saved
  /// before this field existed have no value for it on disk, so a
  /// [defaultValue] is required — without it, the generated adapter casts
  /// the missing field straight to `int` and crashes on startup.
  @HiveField(4, defaultValue: 0)
  int colorIndex;

  /// Archived projects drop out of the main grid (and its search) without
  /// being destroyed — their tasks, color, and history are untouched, and
  /// they're still browsable/searchable from the Archived tab.
  @HiveField(5, defaultValue: false)
  bool archived;

  /// Shown, pinned, in the sidebar's Favorites section.
  @HiveField(6, defaultValue: false)
  bool favorite;

  /// A chronological log of notable events for this project (created, task
  /// added/completed/edited), newest last — shown in the project detail
  /// screen's Activity panel.
  @HiveField(7, defaultValue: [])
  List<ActivityEntry> activityLog;

  @HiveField(8, defaultValue: [])
  List<ProjectComment> comments;

  /// Field 9 used to be a local "workspace" id — retired along with the
  /// whole concept (see [Task]'s field 12 note); not reused.

  /// Who created this project — the signed-in user's id once Supabase is
  /// configured, blank in pure local/offline use.
  @HiveField(10, defaultValue: '')
  String ownerId;

  /// The department this project is scoped to (see
  /// `supabase/migrations/0004_department_scoping.sql`) — blank in pure
  /// local/offline use.
  @HiveField(11, defaultValue: '')
  String departmentId;

  /// Builds a new [Project] with the given fields replaced — used instead
  /// of mutating this instance's fields so that value-equality-based
  /// Riverpod selectors (see [operator ==]) can tell an edited project
  /// apart from the unedited one still referenced by whatever watched it
  /// before the edit. Pass `null` explicitly for [lastOpenedAt] to clear
  /// it; omit to leave it as-is.
  Project copyWith({
    String? name,
    Object? lastOpenedAt = _unset,
    int? colorIndex,
    bool? archived,
    bool? favorite,
    List<ActivityEntry>? activityLog,
    List<ProjectComment>? comments,
    String? ownerId,
    String? departmentId,
  }) => Project(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    lastOpenedAt: identical(lastOpenedAt, _unset)
        ? this.lastOpenedAt
        : lastOpenedAt as DateTime?,
    colorIndex: colorIndex ?? this.colorIndex,
    archived: archived ?? this.archived,
    favorite: favorite ?? this.favorite,
    activityLog: activityLog ?? [...this.activityLog],
    comments: comments ?? [...this.comments],
    ownerId: ownerId ?? this.ownerId,
    departmentId: departmentId ?? this.departmentId,
  );

  static const _activityLogEquality = ListEquality<ActivityEntry>();
  static const _commentsEquality = ListEquality<ProjectComment>();

  @override
  bool operator ==(Object other) =>
      other is Project &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt &&
      other.lastOpenedAt == lastOpenedAt &&
      other.colorIndex == colorIndex &&
      other.archived == archived &&
      other.favorite == favorite &&
      other.ownerId == ownerId &&
      other.departmentId == departmentId &&
      _activityLogEquality.equals(other.activityLog, activityLog) &&
      _commentsEquality.equals(other.comments, comments);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    createdAt,
    lastOpenedAt,
    colorIndex,
    archived,
    favorite,
    ownerId,
    departmentId,
    _activityLogEquality.hash(activityLog),
    _commentsEquality.hash(comments),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'lastOpenedAt': lastOpenedAt?.toIso8601String(),
    'colorIndex': colorIndex,
    'archived': archived,
    'favorite': favorite,
    'activityLog': activityLog.map((a) => a.toJson()).toList(),
    'comments': comments.map((c) => c.toJson()).toList(),
    'ownerId': ownerId,
    'departmentId': departmentId,
  };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    lastOpenedAt: json['lastOpenedAt'] == null
        ? null
        : DateTime.parse(json['lastOpenedAt'] as String),
    colorIndex: json['colorIndex'] as int? ?? 0,
    archived: json['archived'] as bool? ?? false,
    favorite: json['favorite'] as bool? ?? false,
    activityLog: (json['activityLog'] as List<dynamic>? ?? [])
        .map((a) => ActivityEntry.fromJson(a as Map<String, dynamic>))
        .toList(),
    comments: (json['comments'] as List<dynamic>? ?? [])
        .map((c) => ProjectComment.fromJson(c as Map<String, dynamic>))
        .toList(),
    ownerId: json['ownerId'] as String? ?? '',
    departmentId: json['departmentId'] as String? ?? '',
  );

  /// Maps a `projects` table row (snake_case Postgres columns) to a
  /// [Project].
  factory Project.fromSupabase(Map<String, dynamic> row) => Project(
    id: row['id'] as String,
    name: row['name'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    lastOpenedAt: row['last_opened_at'] == null
        ? null
        : DateTime.parse(row['last_opened_at'] as String),
    colorIndex: row['color_index'] as int? ?? 0,
    archived: row['archived'] as bool? ?? false,
    favorite: row['favorite'] as bool? ?? false,
    activityLog: ((row['activity_log'] as List<dynamic>?) ?? [])
        .map((a) => ActivityEntry.fromJson(a as Map<String, dynamic>))
        .toList(),
    comments: ((row['comments'] as List<dynamic>?) ?? [])
        .map((c) => ProjectComment.fromJson(c as Map<String, dynamic>))
        .toList(),
    ownerId: row['owner_id'] as String? ?? '',
    departmentId: row['department_id'] as String,
  );

  /// Maps this [Project] to a `projects` table row for insert/update. Omits
  /// `created_at`, which the database owns.
  Map<String, dynamic> toSupabase() => {
    'id': id,
    'name': name,
    'last_opened_at': lastOpenedAt?.toIso8601String(),
    'color_index': colorIndex,
    'archived': archived,
    'favorite': favorite,
    'activity_log': activityLog.map((a) => a.toJson()).toList(),
    'comments': comments.map((c) => c.toJson()).toList(),
    'owner_id': ownerId,
    'department_id': departmentId,
  };
}
