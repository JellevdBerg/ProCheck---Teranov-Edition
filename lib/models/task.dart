import 'package:collection/collection.dart';
import 'package:hive/hive.dart';

import 'attachment.dart';
import 'subtask.dart';
import 'task_priority.dart';

part 'task.g.dart';

/// Distinguishes "leave this field as-is" from "set it to null" in
/// [Task.copyWith], since a bare `= null` default can't tell the two apart.
const _unset = Object();

/// Still a local Hive object — the on-device cache/UI driver, unchanged in
/// spirit from the local app. What's new for the Teranov edition: when
/// Supabase is configured and signed in (see [isSupabaseConfigured] in
/// supabase_config.dart), [TasksNotifier] additionally mirrors every write
/// to the `tasks` table and pulls remote rows in on launch — see
/// [Task.toSupabase]/[Task.fromSupabase]. Without Supabase configured, this
/// behaves exactly like the local-only app always has.
@HiveType(typeId: 1)
class Task extends HiveObject {
  Task({
    required this.id,
    required this.title,
    required this.createdAt,
    this.isChecked = false,
    this.notes,
    List<Subtask>? subtasks,
    this.projectId,
    this.templateId,
    this.dueDate,
    this.dueDateEnd,
    double? sortOrder,
    this.priorityIndex = 0,
    List<Attachment>? attachments,
    this.recurrenceIndex = 0,
    this.completedAt,
    this.ownerId = '',
    this.assigneeId,
    this.departmentId = '',
    this.estimatedMinutes,
    this.completedBy,
  }) : subtasks = subtasks ?? [],
       attachments = attachments ?? [],
       sortOrder = sortOrder ?? createdAt.millisecondsSinceEpoch.toDouble();

  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  bool isChecked;

  @HiveField(3)
  String? notes;

  @HiveField(4)
  List<Subtask> subtasks;

  /// Null when the task isn't filed under any project — only a manager can
  /// set this once Supabase is configured (see `tasks_insert_own`/
  /// `tasks_update` RLS policies).
  @HiveField(5)
  String? projectId;

  @HiveField(6)
  DateTime createdAt;

  /// The template this task was instantiated from, if any.
  @HiveField(7)
  String? templateId;

  /// When set, a local notification is scheduled for this moment (see
  /// NotificationService) — cancelled/rescheduled whenever this changes,
  /// and cancelled outright once the task is checked off or deleted.
  @HiveField(8)
  DateTime? dueDate;

  /// End of a due-date range, when this task's due date spans more than one
  /// day (e.g. "due Sep 20 - Sep 25") rather than a single moment. Null for
  /// an ordinary single-day due date.
  @HiveField(13)
  DateTime? dueDateEnd;

  /// Controls this task's position within whichever list it's shown in —
  /// higher sorts first. Defaults to its creation time so new tasks land at
  /// the top; dragging a task to reorder it re-assigns this to a small
  /// integer instead (see TasksNotifier.reorderTasks).
  @HiveField(9, defaultValue: 0.0)
  double sortOrder;

  /// [TaskPriority.index] — stored as a plain int rather than a Hive enum
  /// type, since it's just a small fixed set of values.
  @HiveField(10, defaultValue: 0)
  int priorityIndex;

  @HiveField(11, defaultValue: [])
  List<Attachment> attachments;

  /// Field 12 used to be a local "workspace" id — the Teranov edition
  /// replaces that whole concept with department (see [departmentId]), so
  /// this index is retired rather than reused, same as [14]/recurrenceIndex
  /// below.

  /// Leftover from a removed recurring-tasks feature. Kept (unused) so
  /// existing Hive field 14 slots and previously-saved data still read
  /// cleanly.
  @HiveField(14, defaultValue: 0)
  int recurrenceIndex;

  /// When this task was last checked off — null while open, and cleared
  /// back to null if unchecked. Drives the Dashboard's "completed today"
  /// count; unrelated to [dueDate]/notifications.
  @HiveField(15)
  DateTime? completedAt;

  /// Who created this task — the signed-in user's id once Supabase is
  /// configured, blank in pure local/offline use.
  @HiveField(16, defaultValue: '')
  String ownerId;

  /// Who this task is for — null until a manager assigns it to someone.
  @HiveField(17)
  String? assigneeId;

  /// The department this task is scoped to (see
  /// `supabase/migrations/0004_department_scoping.sql`) — blank in pure
  /// local/offline use.
  @HiveField(18, defaultValue: '')
  String departmentId;

  /// How long this task is expected to take, in minutes — used by the team
  /// dashboard's occupancy view to total up a teammate's remaining
  /// workload. Null when no estimate has been given.
  @HiveField(19)
  int? estimatedMinutes;

  /// Who checked this task off — set by the database (never the client), so
  /// blank for local use and for tasks checked off before it existed.
  @HiveField(20)
  String? completedBy;

  TaskPriority get priority => TaskPriority.fromIndex(priorityIndex);
  set priority(TaskPriority value) => priorityIndex = value.index;

  bool get hasSubtasks => subtasks.isNotEmpty;

  int get completedSubtaskCount =>
      subtasks.where((subtask) => subtask.isChecked).length;

  double get subtaskProgress =>
      subtasks.isEmpty ? 0 : completedSubtaskCount / subtasks.length;

  /// Builds a new [Task] with the given fields replaced — used instead of
  /// mutating this instance's fields so that value-equality-based Riverpod
  /// selectors (see [operator ==]) can tell an edited task apart from the
  /// unedited one still referenced by whatever watched it before the edit.
  /// Pass `null` explicitly for [notes]/[projectId]/[templateId]/[dueDate]/
  /// [dueDateEnd]/[completedAt]/[assigneeId] to clear them; omit to leave
  /// them as-is.
  Task copyWith({
    String? title,
    bool? isChecked,
    Object? notes = _unset,
    List<Subtask>? subtasks,
    Object? projectId = _unset,
    Object? templateId = _unset,
    Object? dueDate = _unset,
    Object? dueDateEnd = _unset,
    double? sortOrder,
    int? priorityIndex,
    List<Attachment>? attachments,
    int? recurrenceIndex,
    Object? completedAt = _unset,
    String? ownerId,
    Object? assigneeId = _unset,
    String? departmentId,
    Object? estimatedMinutes = _unset,
    Object? completedBy = _unset,
  }) => Task(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    isChecked: isChecked ?? this.isChecked,
    notes: identical(notes, _unset) ? this.notes : notes as String?,
    subtasks: subtasks ?? [...this.subtasks],
    projectId: identical(projectId, _unset)
        ? this.projectId
        : projectId as String?,
    templateId: identical(templateId, _unset)
        ? this.templateId
        : templateId as String?,
    dueDate: identical(dueDate, _unset) ? this.dueDate : dueDate as DateTime?,
    dueDateEnd: identical(dueDateEnd, _unset)
        ? this.dueDateEnd
        : dueDateEnd as DateTime?,
    sortOrder: sortOrder ?? this.sortOrder,
    priorityIndex: priorityIndex ?? this.priorityIndex,
    attachments: attachments ?? [...this.attachments],
    recurrenceIndex: recurrenceIndex ?? this.recurrenceIndex,
    completedAt: identical(completedAt, _unset)
        ? this.completedAt
        : completedAt as DateTime?,
    ownerId: ownerId ?? this.ownerId,
    assigneeId: identical(assigneeId, _unset)
        ? this.assigneeId
        : assigneeId as String?,
    departmentId: departmentId ?? this.departmentId,
    estimatedMinutes: identical(estimatedMinutes, _unset)
        ? this.estimatedMinutes
        : estimatedMinutes as int?,
    completedBy: identical(completedBy, _unset)
        ? this.completedBy
        : completedBy as String?,
  );

  static const _subtaskListEquality = ListEquality<Subtask>();
  static const _attachmentListEquality = ListEquality<Attachment>();

  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.title == title &&
      other.isChecked == isChecked &&
      other.notes == notes &&
      other.projectId == projectId &&
      other.createdAt == createdAt &&
      other.templateId == templateId &&
      other.dueDate == dueDate &&
      other.dueDateEnd == dueDateEnd &&
      other.sortOrder == sortOrder &&
      other.priorityIndex == priorityIndex &&
      other.completedAt == completedAt &&
      other.ownerId == ownerId &&
      other.assigneeId == assigneeId &&
      other.departmentId == departmentId &&
      other.estimatedMinutes == estimatedMinutes &&
      other.completedBy == completedBy &&
      _subtaskListEquality.equals(other.subtasks, subtasks) &&
      _attachmentListEquality.equals(other.attachments, attachments);

  @override
  int get hashCode => Object.hash(
    id,
    title,
    isChecked,
    notes,
    projectId,
    createdAt,
    templateId,
    dueDate,
    dueDateEnd,
    sortOrder,
    priorityIndex,
    completedAt,
    ownerId,
    assigneeId,
    departmentId,
    estimatedMinutes,
    completedBy,
    _subtaskListEquality.hash(subtasks),
    _attachmentListEquality.hash(attachments),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isChecked': isChecked,
    'notes': notes,
    'subtasks': subtasks.map((s) => s.toJson()).toList(),
    'projectId': projectId,
    'createdAt': createdAt.toIso8601String(),
    'templateId': templateId,
    'dueDate': dueDate?.toIso8601String(),
    'dueDateEnd': dueDateEnd?.toIso8601String(),
    'sortOrder': sortOrder,
    'priorityIndex': priorityIndex,
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'completedAt': completedAt?.toIso8601String(),
    'ownerId': ownerId,
    'assigneeId': assigneeId,
    'departmentId': departmentId,
    'estimatedMinutes': estimatedMinutes,
    'completedBy': completedBy,
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    title: json['title'] as String,
    isChecked: json['isChecked'] as bool? ?? false,
    notes: json['notes'] as String?,
    subtasks: (json['subtasks'] as List<dynamic>? ?? [])
        .map((s) => Subtask.fromJson(s as Map<String, dynamic>))
        .toList(),
    projectId: json['projectId'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    templateId: json['templateId'] as String?,
    dueDate: json['dueDate'] == null
        ? null
        : DateTime.parse(json['dueDate'] as String),
    dueDateEnd: json['dueDateEnd'] == null
        ? null
        : DateTime.parse(json['dueDateEnd'] as String),
    sortOrder: (json['sortOrder'] as num?)?.toDouble(),
    priorityIndex: json['priorityIndex'] as int? ?? 0,
    attachments: (json['attachments'] as List<dynamic>? ?? [])
        .map((a) => Attachment.fromJson(a as Map<String, dynamic>))
        .toList(),
    completedAt: json['completedAt'] == null
        ? null
        : DateTime.parse(json['completedAt'] as String),
    ownerId: json['ownerId'] as String? ?? '',
    assigneeId: json['assigneeId'] as String?,
    departmentId: json['departmentId'] as String? ?? '',
    estimatedMinutes: json['estimatedMinutes'] as int?,
    completedBy: json['completedBy'] as String?,
  );

  /// Maps a `tasks` table row (snake_case Postgres columns) to a [Task].
  factory Task.fromSupabase(Map<String, dynamic> row) => Task(
    id: row['id'] as String,
    title: row['title'] as String,
    isChecked: row['is_checked'] as bool? ?? false,
    notes: row['notes'] as String?,
    subtasks: ((row['subtasks'] as List<dynamic>?) ?? [])
        .map((s) => Subtask.fromJson(s as Map<String, dynamic>))
        .toList(),
    projectId: row['project_id'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    templateId: row['template_id'] as String?,
    dueDate: row['due_date'] == null
        ? null
        : DateTime.parse(row['due_date'] as String),
    dueDateEnd: row['due_date_end'] == null
        ? null
        : DateTime.parse(row['due_date_end'] as String),
    sortOrder: (row['sort_order'] as num?)?.toDouble() ?? 0,
    priorityIndex: row['priority_index'] as int? ?? 0,
    attachments: ((row['attachments'] as List<dynamic>?) ?? [])
        .map((a) => Attachment.fromJson(a as Map<String, dynamic>))
        .toList(),
    completedAt: row['completed_at'] == null
        ? null
        : DateTime.parse(row['completed_at'] as String),
    ownerId: row['owner_id'] as String? ?? '',
    assigneeId: row['assignee_id'] as String?,
    departmentId: row['department_id'] as String,
    estimatedMinutes: row['estimated_minutes'] as int?,
    completedBy: row['completed_by'] as String?,
  );

  /// Maps this [Task] to a `tasks` table row for insert/update. Omits `id`
  /// and `created_at`, which the database owns.
  Map<String, dynamic> toSupabase() => {
    'id': id,
    'title': title,
    'is_checked': isChecked,
    'notes': notes,
    'subtasks': subtasks.map((s) => s.toJson()).toList(),
    'project_id': projectId,
    'template_id': templateId,
    'due_date': dueDate?.toIso8601String(),
    'due_date_end': dueDateEnd?.toIso8601String(),
    'sort_order': sortOrder,
    'priority_index': priorityIndex,
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'completed_at': completedAt?.toIso8601String(),
    'owner_id': ownerId,
    'assignee_id': assigneeId,
    'department_id': departmentId,
    'estimated_minutes': estimatedMinutes,
  };
}
