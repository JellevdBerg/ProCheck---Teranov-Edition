import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/attachment.dart';
import '../models/task_template.dart';
import '../models/template_subtask.dart';
import '../providers/task_templates_provider.dart';
import '../widgets/attachments_editor.dart';
import '../widgets/notes_field.dart';
import '../widgets/panel/panel.dart';
import '../widgets/text_prompt_dialog.dart';

class TaskTemplateEditorScreen extends ConsumerStatefulWidget {
  const TaskTemplateEditorScreen({super.key, this.templateId});

  /// Null when creating a brand new template.
  final String? templateId;

  @override
  ConsumerState<TaskTemplateEditorScreen> createState() =>
      _TaskTemplateEditorScreenState();
}

class _TaskTemplateEditorScreenState
    extends ConsumerState<TaskTemplateEditorScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  final _newSubtaskController = TextEditingController();
  late List<TemplateSubtask> _subtasks;
  late List<Attachment> _attachments;

  @override
  void initState() {
    super.initState();
    final template = _findTemplate();
    _nameController = TextEditingController(text: template?.name ?? '');
    _notesController = TextEditingController(text: template?.notes ?? '');
    _subtasks = template == null
        ? []
        : template.subtasks
              .map((s) => TemplateSubtask(id: s.id, title: s.title))
              .toList();
    _attachments = template == null
        ? []
        : template.attachments
              .map((a) => Attachment(name: a.name, size: a.size, path: a.path))
              .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _newSubtaskController.dispose();
    super.dispose();
  }

  TaskTemplate? _findTemplate() {
    if (widget.templateId == null) return null;
    final templates = ref.read(taskTemplatesProvider);
    final matches = templates.where((t) => t.id == widget.templateId);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.templateId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit template' : 'New template'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete template',
              onPressed: () async {
                final confirmed = await showConfirmDialog(
                  context,
                  title: 'Delete template?',
                  message: 'Existing tasks created from it are unaffected.',
                );
                if (confirmed) {
                  ref
                      .read(taskTemplatesProvider.notifier)
                      .deleteTemplate(widget.templateId!);
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Main task name'),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NotesField(controller: _notesController),
                  const SizedBox(height: 12),
                  AttachmentsEditor(
                    attachments: _attachments,
                    onAdd: (picked) =>
                        setState(() => _attachments.addAll(picked)),
                    onRemoveAt: (index) =>
                        setState(() => _attachments.removeAt(index)),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newSubtaskController,
                    decoration: const InputDecoration(
                      hintText: 'Add a subtask',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addSubtask(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.add),
                  onPressed: _addSubtask,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const StampLabel('Subtasks'),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: DecoratedBox(
                decoration: panelDecoration(
                  context,
                  depth: PanelDepth.recessed,
                ),
                child: _subtasks.isEmpty
                    ? Center(
                        child: Text(
                          'No subtasks yet. Add one above.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      )
                    : ReorderableListView.builder(
                        // Without this, Flutter also auto-appends its own
                        // drag handle after the trailing delete button —
                        // leaving two handle-looking icons per row where only
                        // the second one actually did anything. Wiring the
                        // existing leading icon as the real (only) handle
                        // instead matches where a drag handle sits everywhere
                        // else in the app (TaskTile's reorderIndex).
                        buildDefaultDragHandles: false,
                        itemCount: _subtasks.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setState(() {
                            final subtask = _subtasks.removeAt(oldIndex);
                            _subtasks.insert(newIndex, subtask);
                          });
                        },
                        itemBuilder: (context, index) {
                          final subtask = _subtasks[index];
                          return ListTile(
                            key: ValueKey(subtask.id),
                            leading: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                            title: Text(subtask.title),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  setState(() => _subtasks.removeAt(index)),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addSubtask() {
    final title = _newSubtaskController.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _subtasks.add(TemplateSubtask(id: const Uuid().v4(), title: title));
      _newSubtaskController.clear();
    });
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final notes = _notesController.text.trim();

    final notifier = ref.read(taskTemplatesProvider.notifier);
    if (widget.templateId == null) {
      notifier.addTemplate(
        name,
        _subtasks.map((s) => s.title).toList(),
        notes: notes.isEmpty ? null : notes,
        attachments: _attachments,
      );
    } else {
      notifier.updateTemplate(
        widget.templateId!,
        name,
        _subtasks,
        notes: notes.isEmpty ? null : notes,
        attachments: _attachments,
      );
    }
    Navigator.of(context).pop();
  }
}
