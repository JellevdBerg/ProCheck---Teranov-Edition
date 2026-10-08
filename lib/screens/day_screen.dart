import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/projects_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/industrial_shadows.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/create_task_sheet.dart';
import '../widgets/industrial/industrial_panel.dart';
import '../widgets/nocturne/nocturne_widgets.dart';
import '../widgets/project_name_lookup.dart';
import '../widgets/smart_view_task_row.dart';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Tasks due on [date] — reached by clicking a day in the sidebar's mini
/// calendar.
class DayScreen extends ConsumerWidget {
  const DayScreen({super.key, required this.date, required this.onOpenTask});

  final DateTime date;

  /// Opens a tapped task's home — its project, scrolled to and
  /// highlighting it, or the Projects screen's unfiled list when it has
  /// no project.
  final void Function(String? projectId, String taskId, BuildContext rowContext)
  onOpenTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    final projects = ref.watch(projectsProvider);
    final reduceMotion = ref.watch(settingsProvider).reduceMotion;

    final dayTasks = tasks
        .where(
          (t) =>
              t.dueDate != null &&
              t.dueDate!.year == date.year &&
              t.dueDate!.month == date.month &&
              t.dueDate!.day == date.day,
        )
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

    final projectNames = buildProjectNameLookup(projects);
    final label = '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
    final tokens = context.nocturne;

    // See today_screen.dart's build method for why the task list is a
    // DecoratedSliver/SliverList rather than a Column-in-a-Card — a single
    // day is naturally bounded, but the same lazy-building treatment keeps
    // every smart view consistent.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16.8, 16.8, 16.8, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Tasks for $label',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                NocturneButton(
                  label: 'New task',
                  icon: Icons.add,
                  dense: true,
                  onPressed: () => showCreateTaskSheet(context),
                ),
              ],
            ),
          ),
        ),
        if (dayTasks.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16.8, 16.8, 16.8, 16.8),
            sliver: SliverToBoxAdapter(
              child: IndustrialPanel(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(22.4),
                  child: Center(
                    child: Text(
                      'No tasks due this day.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16.8, 16.8, 16.8, 16.8),
            sliver: DecoratedSliver(
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(NocturneRadius.md),
                boxShadow: panelShadow(tokens),
              ),
              sliver: SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 11.2),
                sliver: SliverList.builder(
                  itemCount: dayTasks.length,
                  itemBuilder: (context, index) {
                    final task = dayTasks[index];
                    return SmartViewTaskRow(
                      task: task,
                      reduceMotion: reduceMotion,
                      projectName: projectNameFor(projectNames, task.projectId),
                      onOpenTask: onOpenTask,
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}
