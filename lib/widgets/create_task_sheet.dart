import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/task.dart';
import '../models/task_template.dart';
import '../providers/projects_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_templates_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/nocturne_theme.dart';
import 'blurred_dialog.dart';
import 'nocturne/nocturne_widgets.dart';
import 'task_tile.dart';

Future<Task?> showCreateTaskSheet(
  BuildContext context, {
  String? initialProjectId,
  TaskTemplate? initialTemplate,
  DateTime? initialDueDate,
  DateTime? initialDueDateEnd,
}) {
  return showBlurredDialog<Task>(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.lg),
        side: BorderSide(color: context.nocturne.edge),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: _CreateTaskSheet(
          initialProjectId: initialProjectId,
          initialTemplate: initialTemplate,
          initialDueDate: initialDueDate,
          initialDueDateEnd: initialDueDateEnd,
        ),
      ),
    ),
  );
}

class _CreateTaskSheet extends ConsumerStatefulWidget {
  const _CreateTaskSheet({
    this.initialProjectId,
    this.initialTemplate,
    this.initialDueDate,
    this.initialDueDateEnd,
  });

  final String? initialProjectId;
  final TaskTemplate? initialTemplate;
  final DateTime? initialDueDate;
  final DateTime? initialDueDateEnd;

  @override
  ConsumerState<_CreateTaskSheet> createState() => _CreateTaskSheetState();
}

class _CreateTaskSheetState extends ConsumerState<_CreateTaskSheet> {
  final _nameController = TextEditingController();
  TaskTemplate? _selectedTemplate;
  String? _selectedProjectId;
  bool _nameEditedByUser = false;

  /// Set once the task is created, switching the sheet to stage 2 (detail
  /// editing) in place rather than closing the dialog.
  String? _createdTaskId;

  @override
  void initState() {
    super.initState();
    _selectedProjectId = widget.initialProjectId;
    _selectedTemplate = widget.initialTemplate;
    if (_selectedTemplate != null) {
      _nameController.text = _selectedTemplate!.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final createdTaskId = _createdTaskId;
    if (createdTaskId != null) {
      return _buildDetailStage(context, createdTaskId);
    }

    final templates = ref.watch(taskTemplatesProvider);
    final projects = ref.watch(projectsProvider);

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New task', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Task name'),
            onChanged: (_) => _nameEditedByUser = true,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<TaskTemplate?>(
            initialValue: _selectedTemplate,
            decoration: const InputDecoration(labelText: 'Start from'),
            items: [
              const DropdownMenuItem<TaskTemplate?>(
                value: null,
                child: Text('Blank task'),
              ),
              ...templates.map(
                (template) => DropdownMenuItem<TaskTemplate?>(
                  value: template,
                  child: Text(template.name),
                ),
              ),
            ],
            onChanged: (template) {
              setState(() {
                _selectedTemplate = template;
                if (!_nameEditedByUser) {
                  _nameController.text = template?.name ?? '';
                }
              });
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _selectedProjectId,
            decoration: const InputDecoration(labelText: 'Project'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('No project'),
              ),
              ...projects.map(
                (Project project) => DropdownMenuItem<String?>(
                  value: project.id,
                  child: Text(project.name),
                ),
              ),
            ],
            onChanged: (projectId) =>
                setState(() => _selectedProjectId = projectId),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: NocturneButton(
              label: 'Continue',
              variant: NocturneButtonVariant.primary,
              onPressed: _createAndContinue,
            ),
          ),
        ],
      ),
    );
  }

  void _createAndContinue() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final notifier = ref.read(tasksProvider.notifier);
    final defaultPriority = ref.read(settingsProvider).defaultPriority;
    final Task task;
    if (_selectedTemplate != null) {
      task = notifier.addFromTemplate(
        template: _selectedTemplate!,
        projectId: _selectedProjectId,
        title: name,
        priority: defaultPriority,
        dueDate: widget.initialDueDate,
        dueDateEnd: widget.initialDueDateEnd,
      );
    } else {
      task = notifier.addBlankTask(
        title: name,
        projectId: _selectedProjectId,
        priority: defaultPriority,
        dueDate: widget.initialDueDate,
        dueDateEnd: widget.initialDueDateEnd,
      );
    }

    setState(() => _createdTaskId = task.id);
  }

  /// Stage 2: the task now exists, so this re-reads it live from
  /// [tasksProvider] (like [TaskTile]'s own ancestors do) and reuses
  /// [TaskDetailEditor] to fill in priority/due date/subtasks/notes/
  /// attachments — the same editing UI/logic as an existing task's detail
  /// view, rather than a separate implementation.
  Widget _buildDetailStage(BuildContext context, String taskId) {
    // Scoped to just this one task: Task now has value equality and every
    // TasksNotifier mutator builds a fresh Task instance via copyWith
    // rather than mutating the box's cached one in place, so `select` sees
    // a genuinely different value on every edit and rebuilds correctly.
    final task = ref.watch(
      tasksProvider.select((tasks) => tasks.firstWhere((t) => t.id == taskId)),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TaskDetailEditor(task: task, padding: EdgeInsets.zero),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: NocturneButton(
              label: 'Done',
              variant: NocturneButtonVariant.primary,
              onPressed: () => Navigator.of(context).pop(task),
            ),
          ),
        ],
      ),
    );
  }
}
