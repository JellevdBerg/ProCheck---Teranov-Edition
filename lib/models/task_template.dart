import 'package:hive/hive.dart';

import 'attachment.dart';
import 'template_subtask.dart';

part 'task_template.g.dart';

/// A reusable pattern for a single main task and its subtasks.
@HiveType(typeId: 4)
class TaskTemplate extends HiveObject {
  TaskTemplate({
    required this.id,
    required this.name,
    required this.subtasks,
    required this.createdAt,
    this.notes,
    List<Attachment>? attachments,
  }) : attachments = attachments ?? [];

  @HiveField(0)
  String id;

  /// The main task's title.
  @HiveField(1)
  String name;

  @HiveField(2)
  List<TemplateSubtask> subtasks;

  @HiveField(3)
  DateTime createdAt;

  /// Carried over onto every task created from this template.
  @HiveField(4)
  String? notes;

  /// Carried over (as fresh copies) onto every task created from this
  /// template — see TasksNotifier.addFromTemplate.
  @HiveField(5, defaultValue: [])
  List<Attachment> attachments;

  /// Field 6 used to be a local "workspace" id — retired along with the
  /// whole concept (see Task's field 12 note); not reused.

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'subtasks': subtasks.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'notes': notes,
    'attachments': attachments.map((a) => a.toJson()).toList(),
  };

  factory TaskTemplate.fromJson(Map<String, dynamic> json) => TaskTemplate(
    id: json['id'] as String,
    name: json['name'] as String,
    subtasks: (json['subtasks'] as List<dynamic>? ?? [])
        .map((s) => TemplateSubtask.fromJson(s as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    notes: json['notes'] as String?,
    attachments: (json['attachments'] as List<dynamic>? ?? [])
        .map((a) => Attachment.fromJson(a as Map<String, dynamic>))
        .toList(),
  );
}
