import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_template.dart';
import '../providers/task_templates_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/create_task_sheet.dart';
import '../widgets/nocturne/nocturne_widgets.dart';
import '../widgets/panel/panel.dart';
import 'empty_state.dart';
import 'task_template_editor_screen.dart';

/// A reusable pattern's list: each row rolls down an "Edit template"/"Use
/// template" menu on its overflow icon, replacing what were previously two
/// always-visible buttons.
class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(taskTemplatesProvider);

    return Padding(
      padding: const EdgeInsets.all(16.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Templates',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              NocturneButton(
                label: 'New template',
                icon: Icons.add,
                variant: NocturneButtonVariant.primary,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TaskTemplateEditorScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16.8),
          if (templates.isEmpty)
            const Expanded(
              child: EmptyState(
                icon: Icons.copy_all_outlined,
                message: 'No templates yet.\nA template sets up a main task with its subtasks, ready to reuse.',
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: templates.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8.4),
                itemBuilder: (context, index) =>
                    _TemplateRow(template: templates[index]),
              ),
            ),
        ],
      ),
    );
  }
}

class _TemplateRow extends StatefulWidget {
  const _TemplateRow({required this.template});

  final TaskTemplate template;

  @override
  State<_TemplateRow> createState() => _TemplateRowState();
}

class _TemplateRowState extends State<_TemplateRow> {
  bool _hovering = false;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: PanelCard(
        padding: const EdgeInsets.all(11.2),
        child: Row(
          children: [
            Icon(
              Icons.copy_all_outlined,
              size: 20,
              color: context.nocturneAccent.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.template.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFamily: kPanelFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                    ),
                  ),
                  Text(
                    '${widget.template.subtasks.length} subtask(s)',
                    style: TextStyle(fontSize: 13, color: tokens.neutral400),
                  ),
                ],
              ),
            ),
            if (_hovering || _menuOpen)
              IconButton(
                icon: Icon(Icons.more_vert, size: 18),
                onPressed: () => _openMenu(context),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context) async {
    setState(() => _menuOpen = true);
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: const Text('Edit template'),
          ),
        ),
        PopupMenuItem(
          value: 'use',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.copy_all_outlined),
            title: const Text('Use template'),
          ),
        ),
      ],
    );
    if (!context.mounted) return;
    setState(() => _menuOpen = false);

    switch (action) {
      case 'edit':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                TaskTemplateEditorScreen(templateId: widget.template.id),
          ),
        );
      case 'use':
        showCreateTaskSheet(context, initialTemplate: widget.template);
    }
  }
}
