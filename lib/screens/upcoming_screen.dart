import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/projects_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/project_name_lookup.dart';
import '../widgets/smart_view_task_row.dart';
import 'empty_state.dart';

/// Every unchecked task with a due date strictly after today, soonest
/// first.
class UpcomingScreen extends ConsumerWidget {
  const UpcomingScreen({super.key, required this.onOpenTask});

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
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final upcomingTasks =
        tasks
            .where(
              (t) =>
                  !t.isChecked &&
                  t.dueDate != null &&
                  t.dueDate!.isAfter(endOfToday),
            )
            .toList()
          ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

    if (upcomingTasks.isEmpty) {
      return const EmptyState(
        icon: Icons.calendar_month_outlined,
        message: 'Nothing coming up.',
      );
    }

    final projectNames = buildProjectNameLookup(projects);
    final tokens = context.nocturne;

    // See today_screen.dart's build method for why this is a
    // CustomScrollView/SliverList rather than a Column-in-a-Card: Upcoming
    // is the smart view most likely to hold most of the user's open
    // tasks, so lazily building only the visible rows matters most here.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16.8, 16.8, 16.8, 0),
          sliver: SliverToBoxAdapter(
            child: Text('Upcoming', style: Theme.of(context).textTheme.headlineSmall),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16.8, 16.8, 16.8, 16.8),
          sliver: DecoratedSliver(
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(NocturneRadius.md),
              border: Border.all(color: tokens.neutral800),
            ),
            sliver: SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 11.2),
              sliver: SliverList.builder(
                itemCount: upcomingTasks.length,
                itemBuilder: (context, index) {
                  final task = upcomingTasks[index];
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
