import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/projects_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/industrial_shadows.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/project_name_lookup.dart';
import '../widgets/smart_view_task_row.dart';
import 'empty_state.dart';

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Every unchecked task due today, across every project (and unfiled).
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key, required this.onOpenTask});

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
    final now = DateTime.now();

    final todayTasks = tasks
        .where((t) => t.dueDate != null && _isSameDay(t.dueDate!, now))
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

    if (todayTasks.isEmpty) {
      return const EmptyState(
        icon: Icons.wb_sunny_outlined,
        message: 'Nothing due today.',
      );
    }

    final projectNames = buildProjectNameLookup(projects);
    final tokens = context.nocturne;

    // A CustomScrollView + SliverList, not the Column-in-a-Panel used
    // elsewhere in the app, so that with thousands of tasks due today only
    // the rows actually on screen get built — the DecoratedSliver
    // replicates IndustrialPanel's look (same radius + dual shadow) so this
    // reads identically to one.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16.8, 16.8, 16.8, 0),
          sliver: SliverToBoxAdapter(
            child: Text('Today', style: Theme.of(context).textTheme.headlineSmall),
          ),
        ),
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
                itemCount: todayTasks.length,
                itemBuilder: (context, index) {
                  final task = todayTasks[index];
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
