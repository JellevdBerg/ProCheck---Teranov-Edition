import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_config.dart';
import '../models/activity_entry.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../models/task_priority.dart';
import '../providers/projects_provider.dart';
import '../providers/roles_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/nocturne/nocturne_widgets.dart';
import '../widgets/panel/panel.dart';
import '../widgets/task_filter_bar.dart';

/// True for an unchecked task with no due date, or one overdue — it needs
/// attention now rather than being scheduled for later. Also used by the
/// sidebar's own "unresolved tasks" badge.
bool isOpenTask(Task task, DateTime now) =>
    !task.isChecked && (task.dueDate == null || !task.dueDate!.isAfter(now));

/// True for an unchecked task with a due date still ahead of it — scheduled,
/// but not due yet. Also used by the sidebar's own "unresolved tasks" badge.
bool isPendingTask(Task task, DateTime now) =>
    !task.isChecked && task.dueDate != null && task.dueDate!.isAfter(now);

/// True for an unchecked task due sometime in the next 7 days (not overdue,
/// not today — those have their own buckets already).
bool isDueThisWeek(Task task, DateTime now) {
  final due = task.dueDate;
  return !task.isChecked &&
      due != null &&
      due.isAfter(now) &&
      due.isBefore(now.add(const Duration(days: 7)));
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// One project's task counts for the Projects table — [open] is simply
/// "not yet done", regardless of due date; [hasOverdue] drives the
/// OVERDUE status badge taking priority over the plain open count.
class ProjectSummary {
  const ProjectSummary({
    required this.project,
    required this.total,
    required this.done,
    required this.hasOverdue,
  });

  final Project project;
  final int total;
  final int done;
  final bool hasOverdue;

  int get open => total - done;

  /// Null for a project with no tasks yet — there's nothing to divide, so
  /// the table shows "No tasks" instead of a misleading 0%/100% bar.
  double? get progress => total == 0 ? null : done / total;
}

/// Builds one [ProjectSummary] per project in [projects] from [tasks],
/// ranked the same way the table itself is meant to read: a project with an
/// overdue task first, then by how much open work is left, then by name.
///
/// Groups [tasks] by project once up front rather than re-scanning the
/// whole list per project (as a naive `tasks.where((t) => t.projectId ==
/// project.id)` per project would) — this is O(tasks + projects) instead of
/// O(projects × tasks), which matters once either list gets large.
List<ProjectSummary> computeProjectSummaries(
  List<Project> projects,
  List<Task> tasks,
  DateTime now,
) {
  final tasksByProject = <String, List<Task>>{};
  for (final task in tasks) {
    final projectId = task.projectId;
    if (projectId == null) continue;
    (tasksByProject[projectId] ??= []).add(task);
  }

  final summaries = [
    for (final project in projects)
      _summaryFor(project, tasksByProject[project.id] ?? const [], now),
  ];

  summaries.sort((a, b) {
    if (a.hasOverdue != b.hasOverdue) return a.hasOverdue ? -1 : 1;
    final byOpen = b.open.compareTo(a.open);
    if (byOpen != 0) return byOpen;
    return a.project.name.toLowerCase().compareTo(b.project.name.toLowerCase());
  });
  return summaries;
}

ProjectSummary _summaryFor(
  Project project,
  List<Task> projectTasks,
  DateTime now,
) {
  var done = 0;
  var hasOverdue = false;
  for (final task in projectTasks) {
    if (task.isChecked) {
      done++;
    } else if (task.dueDate != null && !task.dueDate!.isAfter(now)) {
      hasOverdue = true;
    }
  }
  return ProjectSummary(
    project: project,
    total: projectTasks.length,
    done: done,
    hasOverdue: hasOverdue,
  );
}

const _kDashboardMaxWidth = double.infinity;

/// The Dashboard: a header, then the shared [ProjectsOverview] scoped to
/// every active (non-archived) project and unfiled tasks.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onOpenProject,
    required this.onOpenTask,
    required this.onOpenOrgChart,
  });

  final void Function(String projectId, BuildContext rowContext) onOpenProject;

  /// Like [onOpenProject], but for navigating in from a specific task (the
  /// Today & Needs Attention list) rather than the project itself. Null
  /// projectId means an unfiled task.
  final void Function(String? projectId, String taskId, BuildContext rowContext)
  onOpenTask;

  /// Switches the app shell to the Org Chart destination — kept in the
  /// persistent sidebar shell (see [AppScreen.orgChart]) rather than a
  /// separate full-screen route.
  final VoidCallback onOpenOrgChart;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  TaskFilter _filter = const TaskFilter();

  @override
  Widget build(BuildContext context) {
    final onOpenProject = widget.onOpenProject;
    final onOpenTask = widget.onOpenTask;
    final projects = ref.watch(projectsProvider);
    final userId = ref.watch(taskFilterOptionsProvider).userId;
    final tasks = _filter.apply(ref.watch(tasksProvider), userId);
    final now = DateTime.now();

    final activeProjects = projects.where((p) => !p.archived).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final activeProjectIds = activeProjects.map((p) => p.id).toSet();
    final relevantTasks = tasks
        .where(
          (t) => t.projectId == null || activeProjectIds.contains(t.projectId),
        )
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = constraints.maxWidth < NocturneBreakpoints.compact
            ? NocturneSpace.s4
            : NocturneSpace.s6;
        // Wide windows get more panes (see [ProjectsOverview]), but the
        // content is capped rather than stretched edge to edge.
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kDashboardMaxWidth),
            child: Padding(
              padding: EdgeInsets.all(gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DashboardHeader(
                    title: 'Dashboard',
                    onOpenOrgChart: widget.onOpenOrgChart,
                  ),
                  TaskFilterBar(
                    filter: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                    padding: const EdgeInsets.only(top: NocturneSpace.s3),
                  ),
                  const SizedBox(height: NocturneSpace.s4),
                  Expanded(
                    child: SingleChildScrollView(
                      child: ProjectsOverview(
                        projects: activeProjects,
                        tasks: relevantTasks,
                        now: now,
                        emptyProjectsMessage: 'No active projects yet.',
                        onOpenProject: onOpenProject,
                        onOpenTask: onOpenTask,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader({required this.title, required this.onOpenOrgChart});

  final String title;
  final VoidCallback onOpenOrgChart;

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final dateLabel =
        '${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}';
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: NocturneSpace.s1),
        Text(dateLabel, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    // IT and the Operator get the organization chart (departments, managers
    // and members at a glance).
    final admin = isSupabaseConfigured &&
        supabase.auth.currentUser != null &&
        ref.watch(permissionsProvider).isAdmin;
    if (!admin) return heading;
    return Row(
      children: [
        Expanded(child: heading),
        NocturneButton(
          label: 'Organization',
          icon: Icons.account_tree_outlined,
          onPressed: onOpenOrgChart,
        ),
      ],
    );
  }
}

/// A small in-card header: icon plus a short label, so each pane says what
/// it is on its own.
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    return Row(
      children: [
        Icon(icon, size: 16, color: tokens.neutral600),
        const SizedBox(width: NocturneSpace.s2),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ],
    );
  }
}

/// Everything below the page's own title: the stat row, Today & Needs
/// Attention, the Projects table, and Recent Activity — shared between
/// the Dashboard (active projects) and the
/// Archive screen's mini-dashboard (archived projects), so [projects] and
/// [tasks] are whatever scope the caller wants ([tasks] should already be
/// filtered down to those projects' tasks, plus unfiled ones if relevant).
class ProjectsOverview extends StatelessWidget {
  const ProjectsOverview({
    super.key,
    required this.projects,
    required this.tasks,
    required this.now,
    required this.emptyProjectsMessage,
    required this.onOpenProject,
    required this.onOpenTask,
  });

  final List<Project> projects;
  final List<Task> tasks;
  final DateTime now;

  final String emptyProjectsMessage;
  final void Function(String projectId, BuildContext rowContext) onOpenProject;
  final void Function(String? projectId, String taskId, BuildContext rowContext)
  onOpenTask;

  @override
  Widget build(BuildContext context) {
    final completedCount = tasks.where((t) => t.isChecked).length;

    final overdueTasks =
        tasks
            .where(
              (t) =>
                  !t.isChecked && t.dueDate != null && !t.dueDate!.isAfter(now),
            )
            .toList()
          ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    final dueTodayTasks =
        tasks
            .where(
              (t) =>
                  !t.isChecked &&
                  t.dueDate != null &&
                  t.dueDate!.isAfter(now) &&
                  _isSameDay(t.dueDate!, now),
            )
            .toList()
          ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    final attentionTasks = [...overdueTasks, ...dueTodayTasks];

    final dueThisWeekTasks = tasks.where((t) => isDueThisWeek(t, now)).toList();
    final highPriorityDueThisWeek = dueThisWeekTasks
        .where((t) => t.priority == TaskPriority.high)
        .length;

    final overdueBucket = overdueTasks.length;

    final completedToday = tasks
        .where(
          (t) =>
              t.isChecked &&
              t.completedAt != null &&
              _isSameDay(t.completedAt!, now),
        )
        .length;

    final overallProgress = tasks.isEmpty
        ? 0.0
        : completedCount / tasks.length * 100;

    final projectById = {for (final project in projects) project.id: project};
    final summaries = computeProjectSummaries(projects, tasks, now);
    final activityFeed = _buildActivityFeed(projects);
    final attentionKey = GlobalKey<_AttentionCardState>();

    final stats = _StatRow(
      overdueCount: overdueBucket,
      dueThisWeekCount: dueThisWeekTasks.length,
      highPriorityDueThisWeek: highPriorityDueThisWeek,
      overallProgress: overallProgress,
      completedToday: completedToday,
      onOverdueTap: overdueBucket == 0
          ? null
          : () {
              attentionKey.currentState?.flash();
              Scrollable.ensureVisible(
                attentionKey.currentContext!,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            },
    );
    final attention = _AttentionCard(
      key: attentionKey,
      tasks: attentionTasks,
      projectById: projectById,
      now: now,
      onOpenTask: onOpenTask,
    );
    final table = ProjectsTableCard(
      summaries: summaries,
      emptyMessage: emptyProjectsMessage,
      onOpenProject: onOpenProject,
    );
    final activity = _RecentActivityCard(items: activityFeed);
    const gap = SizedBox(height: NocturneSpace.s3);

    // A card grid that reflows with the width it is given: one column when
    // compact, two under medium (attention | activity, projects full width),
    // two panes at standard (work on the left, activity on the right) and
    // three at wide.
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final Widget panes;
        if (w < NocturneBreakpoints.compact) {
          panes = Column(children: [attention, gap, table, gap, activity]);
        } else if (w < NocturneBreakpoints.medium) {
          panes = Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: attention),
                  const SizedBox(width: NocturneSpace.s3),
                  Expanded(flex: 2, child: activity),
                ],
              ),
              gap,
              table,
            ],
          );
        } else if (w < NocturneBreakpoints.wide) {
          panes = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(children: [attention, gap, table]),
              ),
              const SizedBox(width: NocturneSpace.s3),
              Expanded(child: activity),
            ],
          );
        } else {
          panes = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: attention),
              const SizedBox(width: NocturneSpace.s3),
              Expanded(flex: 5, child: table),
              const SizedBox(width: NocturneSpace.s3),
              Expanded(flex: 3, child: activity),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [stats, gap, panes],
        );
      },
    );
  }
}

List<_ActivityFeedItem> _buildActivityFeed(List<Project> projects) {
  final items = [
    for (final project in projects)
      for (final entry in project.activityLog)
        _ActivityFeedItem(entry: entry, project: project),
  ]..sort((a, b) => b.entry.timestamp.compareTo(a.entry.timestamp));
  return items.take(30).toList();
}

class _ActivityFeedItem {
  const _ActivityFeedItem({required this.entry, required this.project});

  final ActivityEntry entry;
  final Project project;
}

/// The top-line stat tiles: how many were completed today, overdue (tap to
/// jump to Today & Needs Attention), due this week (+ how many of those are
/// high priority), and overall completion.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.overdueCount,
    required this.dueThisWeekCount,
    required this.highPriorityDueThisWeek,
    required this.overallProgress,
    required this.completedToday,
    required this.onOverdueTap,
  });

  final int overdueCount;
  final int dueThisWeekCount;
  final int highPriorityDueThisWeek;
  final double overallProgress;
  final int completedToday;
  final VoidCallback? onOverdueTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final cards = [
      _StatCard(
        value: '$completedToday',
        label: 'Completed today',
        valueColor: tokens.done,
      ),
      _StatCard(
        value: '$overdueCount',
        label: 'Overdue',
        valueColor: tokens.danger,
        labelColor: tokens.danger,
        glyph: Icons.error_outline,
        onTap: onOverdueTap,
      ),
      _StatCard(
        value: '$dueThisWeekCount',
        label: 'Due this week · $highPriorityDueThisWeek high priority',
        valueColor: tokens.warn,
        labelColor: tokens.warn,
      ),
      _StatCard(
        value: '${overallProgress.round()}%',
        label: 'Overall progress',
        gauge: GaugeBar(value: overallProgress / 100),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = NocturneSpace.s3;
        // 2x2 when compact, one row of four from there up.
        final columns = constraints.maxWidth < NocturneBreakpoints.compact
            ? 2
            : 4;
        return Column(
          children: [
            for (var i = 0; i < cards.length; i += columns) ...[
              if (i > 0) const SizedBox(height: spacing),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = i; j < i + columns; j++) ...[
                      if (j > i) const SizedBox(width: spacing),
                      Expanded(
                        child: j < cards.length ? cards[j] : const SizedBox(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    this.valueColor,
    this.labelColor,
    this.onTap,
    this.gauge,
    this.glyph,
  });

  final String value;
  final String label;
  final Color? valueColor;

  /// Optional progress bar shown under the number.
  final Widget? gauge;

  /// A glyph shown beside the number, so state never rests on colour alone.
  final IconData? glyph;

  /// Tints the label itself, not just the number above it; left null for
  /// the neutral default.
  final Color? labelColor;

  /// When set, this card jumps to the relevant section of the Dashboard
  /// instead of being purely informational.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final content = Padding(
      padding: const EdgeInsets.all(NocturneSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (glyph != null) ...[
                Icon(glyph, size: 20, color: valueColor),
                const SizedBox(width: NocturneSpace.s1),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 28,
                      height: 36 / 28,
                      color: valueColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NocturneSpace.s1),
          Text(
            label,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 16 / 12,
              color: labelColor ?? tokens.neutral400,
            ),
          ),
          const SizedBox(height: NocturneSpace.s2),
          // Tiles without a bar keep its height so a row stays even.
          gauge ?? const SizedBox(height: 6),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(NocturneRadius.lg),
              child: content,
            ),
    );
  }
}

/// The merged overdue + due-today list, each row opening straight to that
/// task (scrolled to and highlighted) via [onOpenTask]. The card itself can
/// be flashed via [flash] — called from the Overdue stat tile, since
/// scrolling alone is invisible when this card is already on screen.
class _AttentionCard extends StatefulWidget {
  const _AttentionCard({
    super.key,
    required this.tasks,
    required this.projectById,
    required this.now,
    required this.onOpenTask,
  });

  final List<Task> tasks;
  final Map<String, Project> projectById;
  final DateTime now;
  final void Function(String? projectId, String taskId, BuildContext rowContext)
  onOpenTask;

  /// This card summarizes what needs attention rather than being a full
  /// task list — at most this many rows render, newest/most-urgent first
  /// (callers already sort [tasks] that way), with the rest folded into a
  /// trailing "+N more" note. Keeps the card's height sane and avoids
  /// building hundreds of rows inline in the Dashboard's scroll view if a
  /// user ever accumulates that many overdue/due-today tasks at once.
  static const _maxVisibleRows = 20;

  @override
  State<_AttentionCard> createState() => _AttentionCardState();
}

class _AttentionCardState extends State<_AttentionCard> {
  bool _flashing = false;
  Timer? _timer;

  /// Briefly tints the card so a tap that scrolls here still reads as
  /// having done something, even when the card was already on screen.
  void flash() {
    _timer?.cancel();
    setState(() => _flashing = true);
    _timer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _flashing = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.tasks;
    final projectById = widget.projectById;
    final now = widget.now;
    final onOpenTask = widget.onOpenTask;
    final visibleTasks = tasks.length > _AttentionCard._maxVisibleRows
        ? tasks.sublist(0, _AttentionCard._maxVisibleRows)
        : tasks;
    final hiddenCount = tasks.length - visibleTasks.length;
    final tokens = context.nocturne;
    final tint = _flashing
        ? Color.alphaBlend(
            context.nocturneAccent.withValues(alpha: 0.18),
            tokens.surface,
          )
        : null;

    return Card(
      margin: EdgeInsets.zero,
      color: tint,
      child: Padding(
        padding: const EdgeInsets.all(NocturneSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardHeader(
              icon: Icons.notifications_none,
              label: 'Today & Needs Attention',
            ),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: NocturneSpace.s3),
                child: Text(
                  'Nothing needs your attention right now.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: NocturneSpace.s2),
                child: Column(
                  children: [
                    for (var i = 0; i < visibleTasks.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _AttentionRow(
                        task: visibleTasks[i],
                        project: projectById[visibleTasks[i].projectId],
                        now: now,
                        onOpenTask: onOpenTask,
                      ),
                    ],
                    if (hiddenCount > 0) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '+$hiddenCount more',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.task,
    required this.project,
    required this.now,
    required this.onOpenTask,
  });

  final Task task;
  final Project? project;
  final DateTime now;
  final void Function(String? projectId, String taskId, BuildContext rowContext)
  onOpenTask;

  bool get _isOverdue => !task.dueDate!.isAfter(now);

  String get _statusLabel {
    final due = task.dueDate!;
    if (_isOverdue) {
      final days = DateTime(
        now.year,
        now.month,
        now.day,
      ).difference(DateTime(due.year, due.month, due.day)).inDays;
      return days <= 0 ? 'Overdue' : 'Overdue · ${days}d';
    }
    final hour12 = due.hour % 12 == 0 ? 12 : due.hour % 12;
    final minute = due.minute.toString().padLeft(2, '0');
    final period = due.hour < 12 ? 'AM' : 'PM';
    return 'Due today · $hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final project = this.project;
    final statusColor = _isOverdue ? tokens.danger : tokens.warn;
    final glyph = Icon(
      _isOverdue ? Icons.error_outline : Icons.schedule,
      size: 16,
      color: statusColor,
    );
    final title = Text(
      task.title,
      style: const TextStyle(fontSize: 13, height: 20 / 13),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final projectText = Text(
      project?.name ?? 'Unfiled',
      style: TextStyle(fontSize: 12, color: tokens.neutral400),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final status = Text(
      _statusLabel,
      style: TextStyle(
        fontSize: 12,
        color: statusColor,
        fontWeight: FontWeight.w500,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final content = LayoutBuilder(
      builder: (context, constraints) {
        // Narrow pane: title on its own line, project and status beneath.
        final stacked = constraints.maxWidth < 420;
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NocturneSpace.s2,
            vertical: NocturneSpace.s2,
          ),
          child: stacked
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: glyph,
                    ),
                    const SizedBox(width: NocturneSpace.s2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          Row(
                            children: [
                              Flexible(child: projectText),
                              const SizedBox(width: NocturneSpace.s2),
                              Flexible(flex: 2, child: status),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    glyph,
                    const SizedBox(width: NocturneSpace.s2),
                    Expanded(child: title),
                    const SizedBox(width: NocturneSpace.s2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: projectText,
                    ),
                    const SizedBox(width: NocturneSpace.s3),
                    Flexible(child: status),
                  ],
                ),
        );
      },
    );

    return Builder(
      builder: (rowContext) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(NocturneRadius.sm),
          mouseCursor: SystemMouseCursors.click,
          hoverColor: context.nocturneHoverColor,
          onTap: () => onOpenTask(project?.id, task.id, rowContext),
          child: content,
        ),
      ),
    );
  }
}

/// Which column [ProjectsTableCard] is sorted by — null means the
/// caller's own default order (overdue-first, then most open work first).
enum _ProjectSortColumn { name, tasks, progress, status }

/// How urgently a project's [_statusTag] reads, for sorting STATUS the way
/// it visually ranks: OVERDUE first, then any other open work, then
/// "No tasks" (covers both no tasks at all and everything already done).
int _statusRank(ProjectSummary s) {
  if (s.hasOverdue) return 0;
  if (s.open > 0) return 1;
  return 2;
}

/// The per-project table: how much work is open, the completion bar, and a
/// status badge — ranked overdue-first, then by how much is left open by
/// default, or by tapping any column header to sort some other way.
class ProjectsTableCard extends StatefulWidget {
  const ProjectsTableCard({
    super.key,
    required this.summaries,
    required this.emptyMessage,
    required this.onOpenProject,
    this.trailing,
  });

  final List<ProjectSummary> summaries;
  final String emptyMessage;
  final void Function(String projectId, BuildContext rowContext) onOpenProject;

  /// An optional extra action rendered at the end of each row (e.g. an
  /// "Unarchive" button on the Archive screen).
  final Widget Function(ProjectSummary summary)? trailing;

  @override
  State<ProjectsTableCard> createState() => _ProjectsTableCardState();
}

class _ProjectsTableCardState extends State<ProjectsTableCard> {
  _ProjectSortColumn? _sortColumn;
  bool _ascending = true;

  /// Tapping an unsorted column sorts it ascending; tapping the already-
  /// active column flips direction; tapping it again drops back to the
  /// caller's default order instead of cycling forever.
  void _tapColumn(_ProjectSortColumn column) {
    setState(() {
      if (_sortColumn != column) {
        _sortColumn = column;
        _ascending = true;
      } else if (_ascending) {
        _ascending = false;
      } else {
        _sortColumn = null;
      }
    });
  }

  List<ProjectSummary> get _sortedSummaries {
    final column = _sortColumn;
    if (column == null) return widget.summaries;
    final sorted = [...widget.summaries]
      ..sort(
        (a, b) => switch (column) {
          _ProjectSortColumn.name => a.project.name.toLowerCase().compareTo(
            b.project.name.toLowerCase(),
          ),
          _ProjectSortColumn.tasks => a.open.compareTo(b.open),
          _ProjectSortColumn.progress => (a.progress ?? -1).compareTo(
            b.progress ?? -1,
          ),
          _ProjectSortColumn.status => _statusRank(a).compareTo(_statusRank(b)),
        },
      );
    return _ascending ? sorted : sorted.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final summaries = _sortedSummaries;
    final tokens = context.nocturne;
    _SortableHeaderCell header(
      String label,
      _ProjectSortColumn column, {
      bool alignEnd = false,
    }) => _SortableHeaderCell(
      label: label,
      active: _sortColumn == column,
      ascending: _ascending,
      onTap: () => _tapColumn(column),
      alignEnd: alignEnd,
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(NocturneSpace.s3),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Below this width the columns can't all fit: rows stack
            // (name + status, then tasks + progress) and the sortable
            // headers wrap above them. Every column stays reachable.
            final stacked = constraints.maxWidth < 560;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardHeader(
                  icon: Icons.folder_outlined,
                  label: 'Projects',
                ),
                const SizedBox(height: NocturneSpace.s3),
                if (summaries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      widget.emptyMessage,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else ...[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.raised,
                      borderRadius: BorderRadius.circular(NocturneRadius.sm),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NocturneSpace.s2,
                        vertical: NocturneSpace.s1,
                      ),
                      child: stacked
                          ? Wrap(
                              spacing: NocturneSpace.s2,
                              children: [
                                header('PROJECT', _ProjectSortColumn.name),
                                header('OPEN', _ProjectSortColumn.tasks),
                                header('PROGRESS', _ProjectSortColumn.progress),
                                header('STATUS', _ProjectSortColumn.status),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: header(
                                    'PROJECT',
                                    _ProjectSortColumn.name,
                                  ),
                                ),
                                Expanded(
                                  child: header(
                                    'OPEN',
                                    _ProjectSortColumn.tasks,
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: header(
                                    'PROGRESS',
                                    _ProjectSortColumn.progress,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: header(
                                    'STATUS',
                                    _ProjectSortColumn.status,
                                    alignEnd: true,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  for (var i = 0; i < summaries.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _ProjectsTableRow(
                      summary: summaries[i],
                      onOpenProject: widget.onOpenProject,
                      trailing: widget.trailing,
                      stacked: stacked,
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A column header in [ProjectsTableCard] that sorts the table when tapped,
/// showing a direction arrow once it's the active sort column.
class _SortableHeaderCell extends StatelessWidget {
  const _SortableHeaderCell({
    required this.label,
    required this.active,
    required this.ascending,
    required this.onTap,
    this.alignEnd = false,
  });

  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;

  /// True for the right-aligned STATUS column, so the label+icon hug the
  /// right edge like the plain text it replaced.
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final color = active ? context.nocturneAccent : tokens.neutral500;
    // Flexible + ellipsis (rather than Align wrapping a min-size Row) so a
    // narrow column shrinks the label instead of overflowing the row.
    final labelText = Flexible(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          height: 16 / 11,
          color: color,
          letterSpacing: 0.7,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final icon = Icon(
      active
          ? (ascending ? Icons.arrow_upward : Icons.arrow_downward)
          : Icons.unfold_more,
      size: 13,
      color: color,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(NocturneRadius.sm),
        mouseCursor: SystemMouseCursors.click,
        hoverColor: context.nocturneHoverColor,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: alignEnd
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [labelText, const SizedBox(width: 3), icon],
          ),
        ),
      ),
    );
  }
}

class _ProjectsTableRow extends StatelessWidget {
  const _ProjectsTableRow({
    required this.summary,
    required this.onOpenProject,
    required this.stacked,
    this.trailing,
  });

  final ProjectSummary summary;
  final void Function(String projectId, BuildContext rowContext) onOpenProject;
  final Widget Function(ProjectSummary summary)? trailing;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final project = summary.project;
    final color = context.projectColor(project.colorIndex);
    final progress = summary.progress;

    final name = Row(
      children: [
        Icon(Icons.folder, size: 16, color: color),
        const SizedBox(width: NocturneSpace.s2),
        Expanded(
          child: Text(
            project.name,
            style: const TextStyle(fontSize: 13, height: 20 / 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final tasks = Text(
      '${summary.open}/${summary.total}',
      style: TextStyle(fontSize: 12, color: tokens.neutral400),
    );
    final bar = progress == null
        ? Text('–', style: TextStyle(fontSize: 12, color: tokens.neutral500))
        : Row(
            children: [
              Expanded(
                child: GaugeBar(value: progress, color: color),
              ),
              const SizedBox(width: NocturneSpace.s2),
              SizedBox(
                width: 36,
                child: Text(
                  '${(progress * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          );

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NocturneSpace.s2,
        vertical: NocturneSpace.s2,
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: name),
                    const SizedBox(width: NocturneSpace.s2),
                    _statusTag(tokens),
                    if (trailing != null) ...[
                      const SizedBox(width: NocturneSpace.s2),
                      trailing!(summary),
                    ],
                  ],
                ),
                const SizedBox(height: NocturneSpace.s1),
                Row(
                  children: [
                    Text(
                      'Open ',
                      style: TextStyle(fontSize: 12, color: tokens.neutral500),
                    ),
                    tasks,
                    const SizedBox(width: NocturneSpace.s3),
                    Expanded(child: bar),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 3, child: name),
                Expanded(child: tasks),
                Expanded(flex: 3, child: bar),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _statusTag(tokens),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: NocturneSpace.s2),
                  trailing!(summary),
                ],
              ],
            ),
    );

    return Builder(
      builder: (rowContext) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(NocturneRadius.sm),
          mouseCursor: SystemMouseCursors.click,
          hoverColor: context.nocturneHoverColor,
          onTap: () => onOpenProject(project.id, rowContext),
          child: content,
        ),
      ),
    );
  }

  Widget _statusTag(NocturneColors tokens) {
    if (summary.total == 0) {
      return Text(
        'No tasks',
        style: TextStyle(fontSize: 12, color: tokens.neutral500),
      );
    }
    if (summary.hasOverdue) {
      return NocturneTag(
        label: 'Overdue',
        color: NocturnePriority.high,
        icon: Icons.error_outline,
      );
    }
    if (summary.open > 0) {
      return NocturneTag(label: '${summary.open} open');
    }
    // total > 0 and open == 0: every task is done, not "no tasks" — a
    // distinct status from a project that never had any (see
    // ProjectSummary docs).
    return NocturneTag(label: 'Complete', color: NocturnePriority.low);
  }
}

/// A cross-project feed of the most recent Activity entries (see
/// [Project.activityLog]) — capped to a handful of the newest, since it's
/// meant to answer "what just happened," not be a full audit log.
class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.items});

  final List<_ActivityFeedItem> items;

  /// Beyond this many entries the card scrolls instead of growing — keeps
  /// it from pushing the rest of the Dashboard down as activity piles up.
  static const _visibleRows = 5;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(NocturneSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardHeader(icon: Icons.history, label: 'Recent activity'),
            const SizedBox(height: NocturneSpace.s2),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No recent activity yet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NocturneSpace.s2,
                ),
                child: SizedBox(
                  height: (_visibleRows * _ActivityFeedRow.height).clamp(
                    0,
                    items.length * _ActivityFeedRow.height,
                  ),
                  child: Scrollbar(
                    child: ListView.builder(
                      itemCount: items.length,
                      itemExtent: _ActivityFeedRow.height,
                      itemBuilder: (context, index) =>
                          _ActivityFeedRow(item: items[index]),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityFeedRow extends StatelessWidget {
  const _ActivityFeedRow({required this.item});

  final _ActivityFeedItem item;

  /// Fixed so [_RecentActivityCard] can size its scroll viewport to an
  /// exact number of rows via `ListView.builder`'s `itemExtent`.
  static const double height = 36;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final accent = context.nocturneAccent;
    final entry = item.entry;
    final (icon, color) = switch (entry.kind) {
      ActivityKind.projectCreated => (Icons.create_new_folder_outlined, accent),
      ActivityKind.taskAdded => (Icons.add_circle_outline, accent),
      ActivityKind.taskCompleted => (Icons.check_circle, tokens.done),
      ActivityKind.taskEdited => (Icons.edit_outlined, accent),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NocturneSpace.s2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: NocturneSpace.s2),
          Expanded(
            child: Text(
              entry.description,
              style: TextStyle(fontSize: 13, color: tokens.neutral200),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: NocturneSpace.s2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              item.project.name,
              style: TextStyle(fontSize: 11, color: tokens.neutral500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: NocturneSpace.s1),
          Text('·', style: TextStyle(fontSize: 11, color: tokens.neutral500)),
          const SizedBox(width: NocturneSpace.s1),
          Text(
            _relativeTime(entry.timestamp),
            style: TextStyle(fontSize: 11, color: tokens.neutral500),
          ),
        ],
      ),
    );
  }
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${(diff.inDays / 7).floor()}w ago';
}
