import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';
import '../models/task_priority.dart';
import '../providers/tasks_provider.dart';
import '../theme/nocturne_theme.dart';
import '../providers/settings_provider.dart';
import 'task_tile.dart' show TaskMeta, TaskRowFocus;
import 'wobble_checkbox.dart';

/// A read-mostly task row for the Today/Upcoming/Day smart views: checkbox,
/// title, its project's name, priority tag, due tag. No expand/subtasks —
/// those live on the task's actual home (a project, or Unfiled Tasks).
/// Tapping the title/project area opens that home — same "open this task"
/// behavior as the Calendar and the sidebar search.
class SmartViewTaskRow extends ConsumerWidget {
  const SmartViewTaskRow({
    super.key,
    required this.task,
    required this.projectName,
    required this.onOpenTask,
    this.reduceMotion = false,
  });

  final Task task;
  final String projectName;
  final bool reduceMotion;
  final void Function(String? projectId, String taskId, BuildContext rowContext)
  onOpenTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.nocturne;
    final compact = ref.watch(settingsProvider).compactRows;
    final hasMeta =
        task.dueDate != null ||
        task.priority != TaskPriority.none ||
        task.hasSubtasks ||
        task.assigneeId != null;
    final titleText = Text(
      task.title,
      maxLines: compact ? 1 : null,
      overflow: compact ? TextOverflow.ellipsis : null,
      style: TextStyle(
        fontSize: 13,
        height: 20 / 13,
        color: task.isChecked ? tokens.neutral500 : tokens.text,
        decoration: task.isChecked ? TextDecoration.lineThrough : null,
      ),
    );
    final projectText = Text(
      projectName,
      maxLines: compact ? 1 : null,
      overflow: compact ? TextOverflow.ellipsis : null,
      style: TextStyle(fontSize: 12, height: 16 / 12, color: tokens.neutral400),
    );
    // Compact rows put the project beside the title to stay ~32px tall.
    final titleAndProject = compact
        ? Row(
            children: [
              Flexible(child: titleText),
              const SizedBox(width: NocturneSpace.s2),
              Flexible(child: projectText),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [titleText, projectText],
          );
    // The hover/press highlight wraps the whole row — checkbox, title,
    // project, priority tag and due tag together — so it spans the entire
    // available width of the task rather than stopping short at the
    // checkbox or the tags. The checkbox keeps its own tap target for
    // toggling; only taps elsewhere on the row open the task.
    return TaskRowFocus(
      onToggle: () => ref.read(tasksProvider.notifier).toggleTask(task.id),
      child: Builder(
        builder: (rowContext) => Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(NocturneRadius.sm),
            mouseCursor: SystemMouseCursors.click,
            hoverColor: context.nocturneHoverColor,
            splashColor: context.nocturneSplashColor,
            highlightColor: context.nocturneSplashColor,
            onTap: () => onOpenTask(task.projectId, task.id, rowContext),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? NocturneSpace.s2 : NocturneSpace.s3,
                vertical: compact ? 0 : NocturneSpace.s1,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final checkbox = WobbleCheckbox(
                    value: task.isChecked,
                    reduceMotion: reduceMotion,
                    onChanged: (_) =>
                        ref.read(tasksProvider.notifier).toggleTask(task.id),
                  );
                  // Meta sits at the right when there is room; otherwise it
                  // drops under the title so nothing is squeezed or clipped.
                  final inline = constraints.maxWidth >= 480;
                  return Row(
                    children: [
                      checkbox,
                      const SizedBox(width: NocturneSpace.s2),
                      Expanded(
                        child: inline || !hasMeta
                            ? titleAndProject
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  titleAndProject,
                                  const SizedBox(height: NocturneSpace.s1),
                                  TaskMeta(task: task),
                                ],
                              ),
                      ),
                      if (inline && hasMeta) ...[
                        const SizedBox(width: NocturneSpace.s2),
                        // Not a Flexible: that would split the free space 50/50 with the
                        // title and leave the meta floating mid-row.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.6,
                          ),
                          child: TaskMeta(task: task),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
