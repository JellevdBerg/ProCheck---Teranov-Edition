import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activity_entry.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../models/task_priority.dart';
import '../providers/projects_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/nocturne/nocturne_widgets.dart';
import '../widgets/panel/panel.dart';

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

/// The Dashboard: a header, then the shared [ProjectsOverview] scoped to
/// every active (non-archived) project and unfiled tasks.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({
    super.key,
    required this.onOpenProject,
    required this.onOpenTask,
  });

  final void Function(String projectId, BuildContext rowContext) onOpenProject;

  /// Like [onOpenProject], but for navigating in from a specific task (the
  /// Today & Needs Attention list) rather than the project itself. Null
  /// projectId means an unfiled task.
  final void Function(String? projectId, String taskId, BuildContext rowContext)
  onOpenTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    final tasks = ref.watch(tasksProvider);
    final now = DateTime.now();

    final activeProjects = projects.where((p) => !p.archived).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final activeProjectIds = activeProjects.map((p) => p.id).toSet();
    final relevantTasks = tasks
        .where(
          (t) => t.projectId == null || activeProjectIds.contains(t.projectId),
        )
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DashboardHeader(title: 'Dashboard'),
          const SizedBox(height: 16.8),
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
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.title});

  final String title;

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
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final now = DateTime.now();
    final dateLabel =
        '${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 2),
        Text(
          dateLabel,
          style: TextStyle(fontSize: 13, color: tokens.neutral400),
        ),
      ],
    );
  }
}

/// Text-weight version of a lamp/status hue: on the light finish the pale
/// hues are pulled toward the text colour so they stay readable.
Color _legible(BuildContext context, Color color) {
  final t = context.nocturne;
  return t.isDark ? color : Color.lerp(color, t.text, 0.5)!;
}

/// A small in-card header — icon plus a short label — used instead of a
/// separate section title sitting above the card, so each pane says what
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
        Icon(icon, size: 14, color: tokens.neutral500),
        const SizedBox(width: 6),
        Flexible(
          // Engraved like StampLabel but keeps the label's own casing.
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: kPanelFont,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: tokens.neutral500,
              shadows: [
                Shadow(
                  color: tokens.hi.withValues(alpha: 0.6),
                  offset: const Offset(0, 1),
                ),
              ],
            ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatRow(
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
        ),
        const SizedBox(height: 22.4),
        _AttentionCard(
          key: attentionKey,
          tasks: attentionTasks,
          projectById: projectById,
          now: now,
          onOpenTask: onOpenTask,
        ),
        const SizedBox(height: 22.4),
        ProjectsTableCard(
          summaries: summaries,
          emptyMessage: emptyProjectsMessage,
          onOpenProject: onOpenProject,
        ),
        const SizedBox(height: 22.4),
        _RecentActivityCard(items: activityFeed),
      ],
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

/// The top-line stat cards: how many were completed today, overdue (tap to
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
    final cards = [
      _StatCard(
        value: '$completedToday',
        label: 'Completed today',
        valueColor: NocturneStatus.done,
      ),
      _StatCard(
        value: '$overdueCount',
        label: 'Overdue',
        valueColor: NocturnePriority.high,
        labelColor: NocturnePriority.high,
        onTap: onOverdueTap,
      ),
      _StatCard(
        value: '$dueThisWeekCount',
        label: 'Due this week · $highPriorityDueThisWeek high priority',
        valueColor: NocturnePriority.med,
        labelColor: NocturnePriority.med,
      ),
      _StatCard(
        value: '${overallProgress.round()}%',
        label: 'Overall progress',
        valueColor: context.nocturneAccent,
        gauge: GaugeBar(value: overallProgress / 100, height: 8),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 11.2;
        final columns = (constraints.maxWidth / 180).floor().clamp(1, 4);
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
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
  });

  final String value;
  final String label;
  final Color? valueColor;

  /// Optional segmented gauge shown under the readout.
  final Widget? gauge;

  /// Tints the label itself, not just the number above it — left null for
  /// the neutral default.
  final Color? labelColor;

  /// When set, this card jumps to the relevant section of the Dashboard
  /// instead of being purely informational.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    // Only a card with a semantic label color (Overdue, Due this week) gets
    // a matching background wash — a plain neutral stat stays plain.
    final tint = labelColor == null
        ? null
        : Color.alphaBlend(labelColor!.withValues(alpha: 0.10), tokens.surface);
    final content = Padding(
      padding: const EdgeInsets.all(16.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The big readout, set into a recessed window.
          DecoratedBox(
            decoration: panelDecoration(
              context,
              depth: PanelDepth.recessed,
              radius: NocturneRadius.sm,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontFamily: kPanelFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 34,
                      height: 1.1,
                      letterSpacing: 1,
                      color: valueColor == null
                          ? null
                          : _legible(context, valueColor!),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Cards without a gauge reserve its height so the row stays even.
          const SizedBox(height: 8),
          gauge ?? const SizedBox(height: 12),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: labelColor == null
                  ? tokens.neutral400
                  : _legible(context, labelColor!),
            ),
          ),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      color: tint,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardHeader(
              icon: Icons.notifications_none,
              label: 'Today & Needs Attention',
            ),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Nothing needs your attention right now.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
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
    final statusColor = _isOverdue
        ? NocturnePriority.high
        : NocturnePriority.med;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Row(
        children: [
          IndicatorLamp(on: true, color: statusColor, size: 9),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              task.title,
              style: const TextStyle(fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              project?.name ?? 'Unfiled',
              style: TextStyle(fontSize: 12, color: tokens.neutral400),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _statusLabel,
            style: TextStyle(
              fontSize: 12,
              color: _legible(context, statusColor),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    return Builder(
      builder: (rowContext) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(NocturneRadius.md),
          mouseCursor: SystemMouseCursors.click,
          hoverColor: context.nocturneHoverColor,
          splashColor: context.nocturneSplashColor,
          highlightColor: context.nocturneSplashColor,
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardHeader(icon: Icons.folder_outlined, label: 'Projects'),
            const SizedBox(height: 14),
            if (summaries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  widget.emptyMessage,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _SortableHeaderCell(
                        label: 'PROJECT',
                        active: _sortColumn == _ProjectSortColumn.name,
                        ascending: _ascending,
                        onTap: () => _tapColumn(_ProjectSortColumn.name),
                      ),
                    ),
                    Expanded(
                      child: _SortableHeaderCell(
                        label: 'TASKS',
                        active: _sortColumn == _ProjectSortColumn.tasks,
                        ascending: _ascending,
                        onTap: () => _tapColumn(_ProjectSortColumn.tasks),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: _SortableHeaderCell(
                        label: 'PROGRESS',
                        active: _sortColumn == _ProjectSortColumn.progress,
                        ascending: _ascending,
                        onTap: () => _tapColumn(_ProjectSortColumn.progress),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: _SortableHeaderCell(
                        label: 'STATUS',
                        active: _sortColumn == _ProjectSortColumn.status,
                        ascending: _ascending,
                        onTap: () => _tapColumn(_ProjectSortColumn.status),
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
              for (var i = 0; i < summaries.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _ProjectsTableRow(
                  summary: summaries[i],
                  onOpenProject: widget.onOpenProject,
                  trailing: widget.trailing,
                ),
              ],
            ],
          ],
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
          fontFamily: kPanelFont,
          fontSize: 12,
          color: color,
          letterSpacing: 1.2,
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
        borderRadius: BorderRadius.circular(NocturneRadius.md),
        mouseCursor: SystemMouseCursors.click,
        hoverColor: context.nocturneHoverColor,
        splashColor: context.nocturneSplashColor,
        highlightColor: context.nocturneSplashColor,
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
    this.trailing,
  });

  final ProjectSummary summary;
  final void Function(String projectId, BuildContext rowContext) onOpenProject;
  final Widget Function(ProjectSummary summary)? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final project = summary.project;
    final color = accentPalette[project.colorIndex];
    final progress = summary.progress;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(Icons.folder, size: 14, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    project.name,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              '${summary.open}/${summary.total}',
              style: TextStyle(fontSize: 12, color: tokens.neutral400),
            ),
          ),
          Expanded(
            flex: 3,
            child: progress == null
                ? Text(
                    '–',
                    style: TextStyle(fontSize: 12, color: tokens.neutral500),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: GaugeBar(
                          value: progress,
                          color: color,
                          segments: 12,
                          height: 6,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 38,
                        child: Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                            fontFamily: kPanelFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: _statusTag(tokens),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!(summary),
          ],
        ],
      ),
    );

    return Builder(
      builder: (rowContext) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(NocturneRadius.md),
          mouseCursor: SystemMouseCursors.click,
          hoverColor: context.nocturneHoverColor,
          splashColor: context.nocturneSplashColor,
          highlightColor: context.nocturneSplashColor,
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
      return const NocturneTag(label: 'OVERDUE', color: NocturnePriority.high);
    }
    if (summary.open > 0) {
      return NocturneTag(label: '${summary.open} open');
    }
    return Text(
      'No tasks',
      style: TextStyle(fontSize: 12, color: tokens.neutral500),
    );
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
        padding: const EdgeInsets.all(16.8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardHeader(icon: Icons.history, label: 'Recent Activity'),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No recent activity yet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              DecoratedBox(
                decoration: panelDecoration(
                  context,
                  depth: PanelDepth.recessed,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
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
  static const double height = 32;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final accent = context.nocturneAccent;
    final entry = item.entry;
    final (icon, color) = switch (entry.kind) {
      ActivityKind.projectCreated => (Icons.create_new_folder_outlined, accent),
      ActivityKind.taskAdded => (Icons.add_circle_outline, accent),
      ActivityKind.taskCompleted => (Icons.check_circle, NocturneStatus.done),
      ActivityKind.taskEdited => (Icons.edit_outlined, accent),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              entry.description,
              style: TextStyle(fontSize: 13, color: tokens.neutral200),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.project.name,
            style: TextStyle(fontSize: 11, color: tokens.neutral500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(width: 6),
          Text('·', style: TextStyle(fontSize: 11, color: tokens.neutral500)),
          const SizedBox(width: 6),
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
