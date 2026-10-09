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

/// A reusable pattern's list: each card rolls down an "Edit template"/"Use
/// template" menu on its overflow icon, replacing what were previously two
/// always-visible buttons.
class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(taskTemplatesProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gutter = width < NocturneBreakpoints.compact
            ? NocturneSpace.s4
            : NocturneSpace.s6;
        // 1 column compact, 2 medium, 3 standard, 4 wide.
        final columns = width < NocturneBreakpoints.compact
            ? 1
            : width < NocturneBreakpoints.medium
            ? 2
            : width < NocturneBreakpoints.wide
            ? 3
            : 4;
        final cardWidth =
            (width - gutter * 2 - NocturneSpace.s3 * (columns - 1)) / columns;

        return Padding(
          padding: EdgeInsets.all(gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Templates',
                      style: Theme.of(context).textTheme.displaySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: NocturneSpace.s2),
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
              const SizedBox(height: NocturneSpace.s4),
              if (templates.isEmpty)
                const Expanded(
                  child: EmptyState(
                    icon: Icons.copy_all_outlined,
                    message:
                        'No templates yet.\nA template sets up a main task with its subtasks, ready to reuse.',
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: NocturneSpace.s3,
                      runSpacing: NocturneSpace.s3,
                      children: [
                        for (final template in templates)
                          SizedBox(
                            width: cardWidth,
                            child: _TemplateRow(
                              template: template,
                              // No hover on touch / narrow windows.
                              alwaysShowMenu:
                                  width < NocturneBreakpoints.compact,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TemplateRow extends StatefulWidget {
  const _TemplateRow({required this.template, required this.alwaysShowMenu});

  final TaskTemplate template;
  final bool alwaysShowMenu;

  @override
  State<_TemplateRow> createState() => _TemplateRowState();
}

class _TemplateRowState extends State<_TemplateRow> {
  bool _hovering = false;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final count = widget.template.subtasks.length;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: PanelCard(
        padding: const EdgeInsets.fromLTRB(
          NocturneSpace.s4,
          NocturneSpace.s3,
          NocturneSpace.s2,
          NocturneSpace.s3,
        ),
        child: Row(
          children: [
            Icon(
              Icons.copy_all_outlined,
              size: 20,
              color: context.nocturneAccent,
            ),
            const SizedBox(width: NocturneSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.template.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '$count subtask(s)',
                    style: TextStyle(fontSize: 12, color: tokens.neutral500),
                  ),
                ],
              ),
            ),
            // Fixed slot so the card does not jump when the button appears.
            SizedBox(
              width: 40,
              height: 40,
              child: (_hovering || _menuOpen || widget.alwaysShowMenu)
                  ? IconButton(
                      icon: const Icon(Icons.more_vert, size: 18),
                      onPressed: () => _openMenu(context),
                    )
                  : null,
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
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit template'),
          ),
        ),
        const PopupMenuItem(
          value: 'use',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.copy_all_outlined),
            title: Text('Use template'),
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
