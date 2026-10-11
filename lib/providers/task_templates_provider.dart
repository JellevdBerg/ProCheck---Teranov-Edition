import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../data/hive_setup.dart';
import '../models/attachment.dart';
import '../models/task_template.dart';
import '../models/template_subtask.dart';

final taskTemplatesProvider =
    StateNotifierProvider<TaskTemplatesNotifier, List<TaskTemplate>>((ref) {
      return TaskTemplatesNotifier();
    });

/// Persistence to Hive is fire-and-forget: [state] is the source of truth
/// for the UI and is updated synchronously, while the on-disk copy catches
/// up in the background. Templates stay purely local — they're not part of
/// the department-visibility feature, so there's no Supabase mirroring
/// here (unlike [TasksNotifier]/[ProjectsNotifier]).
class TaskTemplatesNotifier extends StateNotifier<List<TaskTemplate>> {
  TaskTemplatesNotifier() : super(_box.values.toList()) {
    _sortState();
  }

  static Box<TaskTemplate> get _box =>
      Hive.box<TaskTemplate>(taskTemplateBoxName);

  /// Every template — used where that's explicitly correct (backup export,
  /// Settings > Wipe All Data already clearing the whole box).
  List<TaskTemplate> get allValues => _box.values.toList();

  void _sortState() {
    final sorted = [...state]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    state = sorted;
  }

  TaskTemplate addTemplate(
    String name,
    List<String> subtaskTitles, {
    String? notes,
    List<Attachment>? attachments,
  }) {
    final template = TaskTemplate(
      id: const Uuid().v4(),
      name: name,
      subtasks: subtaskTitles
          .map((title) => TemplateSubtask(id: const Uuid().v4(), title: title))
          .toList(),
      createdAt: DateTime.now(),
      notes: notes,
      attachments: attachments,
    );
    unawaited(_box.put(template.id, template));
    state = [...state, template];
    _sortState();
    return template;
  }

  void updateTemplate(
    String id,
    String name,
    List<TemplateSubtask> subtasks, {
    String? notes,
    List<Attachment>? attachments,
  }) {
    final template = _box.get(id);
    if (template == null) return;
    // A fresh instance, never the same object already in the box/state —
    // matches the copy-on-write convention TasksNotifier/ProjectsNotifier
    // use (see TasksNotifier._persist), instead of mutating the Hive
    // object in place.
    final updated = TaskTemplate(
      id: template.id,
      name: name,
      subtasks: subtasks,
      createdAt: template.createdAt,
      notes: notes,
      attachments: attachments ?? [],
    );
    unawaited(_box.put(id, updated));
    state = [
      for (final t in state)
        if (t.id == id) updated else t,
    ];
    _sortState();
  }

  void deleteTemplate(String id) {
    unawaited(_box.delete(id));
    state = state.where((t) => t.id != id).toList();
  }

  /// Wipes every template. Used by Settings > Wipe All Data.
  void clearAll() {
    unawaited(_box.clear());
    state = [];
  }

  /// Replaces every template with [templates]. Used when restoring from a
  /// backup — anything currently stored is discarded first.
  void restoreAll(List<TaskTemplate> templates) {
    unawaited(_replaceBoxContents(templates));
    state = [...templates];
    _sortState();
  }

  /// Replaces [_box]'s entire contents with [templates] — used by
  /// [restoreAll]. `clear()` and `putAll()` are each async with no
  /// synchronous fast path, so `clear()` must be awaited before `putAll()`
  /// starts — firing both off unawaited in sequence lets them race, and a
  /// `clear()` that lands after `putAll()` wipes the just-restored data
  /// back out of the box.
  Future<void> _replaceBoxContents(List<TaskTemplate> templates) async {
    await _box.clear();
    await _box.putAll({for (final t in templates) t.id: t});
  }
}
