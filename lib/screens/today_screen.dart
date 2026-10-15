import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/projects_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/panel/panel.dart';
import '../widgets/project_name_lookup.dart';
import '../widgets/smart_view_task_row.dart';
import '../widgets/task_filter_bar.dart';

/// Page gutter: 16 compact, 24 wider, and the content is centred in a column
/// of at most [maxWidth] (unbounded by default: lists fill the window).
double screenGutter(double width, {double maxWidth = double.infinity}) {
  final g = width < NocturneBreakpoints.compact
      ? NocturneSpace.s4
      : NocturneSpace.s6;
  return width - 2 * g > maxWidth ? (width - maxWidth) / 2 : g;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Every unchecked task due today, across every project (and unfiled).
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key, required this.onOpenTask});

  /// Opens a tapped task's home — its project, scrolled to and
  /// highlighting it, or the Projects screen's unfiled list when it has
  /// no project.
  final void Function(String? projectId, String taskId, BuildContext rowContext)
  onOpenTask;

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> with CheckedLinger {
  TaskFilter _filter = const TaskFilter();

  @override
  Widget build(BuildContext context) {
    final onOpenTask = widget.onOpenTask;
    final userId = ref.watch(taskFilterOptionsProvider).userId;
    final tasks = _filter.apply(ref.watch(tasksProvider), userId);
    final projects = ref.watch(projectsProvider);
    final reduceMotion = ref.watch(settingsProvider).reduceMotion;
    final now = DateTime.now();

    // Due today, or overdue — previously this screen showed only tasks due
    // exactly today, so an overdue task (and Upcoming, which starts the day
    // after today) never surfaced it anywhere except the Dashboard's own
    // "Needs Attention" panel. Sorting by due date puts overdue ones first.
    final todayTasks =
        tasks
            .where(
              (t) =>
                  (!t.isChecked || lingers(t.id)) &&
                  t.dueDate != null &&
                  (_isSameDay(t.dueDate!, now) || t.dueDate!.isBefore(now)),
            )
            .toList()
          ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));

    if (todayTasks.isEmpty) {
      return LayoutBuilder(
        builder: (context, c) => FilteredEmptyState(
          icon: Icons.wb_sunny_outlined,
          message: 'Nothing due today.',
          filter: _filter,
          onChanged: (f) => setState(() => _filter = f),
          gutter: screenGutter(c.maxWidth),
        ),
      );
    }

    final projectNames = buildProjectNameLookup(projects);

    // A CustomScrollView + SliverList, not the Column-in-a-Card used
    // elsewhere in the app, so that with thousands of tasks due today only
    // the rows actually on screen get built — the DecoratedSliver
    // replicates the app's flat (elevation: 0) CardThemeData so this looks
    // identical to a real Card.
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = screenGutter(constraints.maxWidth);
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                NocturneSpace.s4,
                gutter,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      'Due today, or overdue — see Upcoming for what\'s further out.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 0),
              sliver: SliverToBoxAdapter(
                child: TaskFilterBar(
                  padding: const EdgeInsets.only(top: NocturneSpace.s3),
                  filter: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                NocturneSpace.s3,
                gutter,
                NocturneSpace.s4,
              ),
              sliver: DecoratedSliver(
                decoration: panelDecoration(context),
                sliver: SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NocturneSpace.s2,
                  ),
                  sliver: SliverList.builder(
                    itemCount: todayTasks.length,
                    itemBuilder: (context, index) {
                      final task = todayTasks[index];
                      return SmartViewTaskRow(
                        key: ValueKey(task.id),
                        task: task,
                        reduceMotion: reduceMotion,
                        onChecked: lingerChecked,
                        projectName: projectNameFor(
                          projectNames,
                          task.projectId,
                        ),
                        onOpenTask: onOpenTask,
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
