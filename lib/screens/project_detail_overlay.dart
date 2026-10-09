import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/activity_entry.dart';
import '../models/project.dart';
import '../providers/projects_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/create_task_sheet.dart';
import '../widgets/nocturne/nocturne_widgets.dart';
import '../widgets/panel/panel.dart';
import '../widgets/pop_out_removal.dart';
import '../widgets/task_tile.dart';
import '../widgets/text_prompt_dialog.dart';

/// The content shown inside the card-morph overlay [AppShell] animates
/// open — header (back/edit/archive/delete/new-task), a task list, and an
/// Activity + Comments side panel. Not a route: the sidebar stays visible
/// because this is just a widget stacked over the main content area.
class ProjectDetailOverlay extends ConsumerStatefulWidget {
  const ProjectDetailOverlay({
    super.key,
    required this.projectId,
    required this.onClose,
    this.highlightTaskId,
  });

  final String projectId;
  final VoidCallback onClose;

  /// When set, the matching task is scrolled into view and briefly
  /// highlighted once this overlay is showing — used when navigating in
  /// from a specific task (e.g. the Dashboard's overdue list) rather than
  /// the project itself.
  final String? highlightTaskId;

  @override
  ConsumerState<ProjectDetailOverlay> createState() =>
      _ProjectDetailOverlayState();
}

class _ProjectDetailOverlayState extends ConsumerState<ProjectDetailOverlay> {
  final Map<String, GlobalKey> _taskKeys = {};
  String? _highlightedTaskId;
  Timer? _highlightTimer;
  bool _scrolledToHighlight = false;

  /// At most one task is expanded at a time in this project's list —
  /// opening one collapses whichever other task was open.
  String? _expandedTaskId;
  Timer? _expandTimer;

  /// How long after this overlay opens with a [highlightTaskId] before that
  /// task auto-expands — gives the card-morph animation (320ms, see
  /// [AppShell]) and the scroll-into-view a moment to settle first, rather
  /// than the task popping open instantly underneath them.
  static const _autoExpandDelay = Duration(milliseconds: 450);

  @override
  void initState() {
    super.initState();
    _highlightedTaskId = widget.highlightTaskId;
    _armHighlightTimer();
    _armExpandTimer();
  }

  @override
  void didUpdateWidget(covariant ProjectDetailOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightTaskId != oldWidget.highlightTaskId) {
      setState(() {
        _highlightedTaskId = widget.highlightTaskId;
        _scrolledToHighlight = false;
      });
      _armHighlightTimer();
      _armExpandTimer();
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _expandTimer?.cancel();
    super.dispose();
  }

  void _armExpandTimer() {
    _expandTimer?.cancel();
    final taskId = widget.highlightTaskId;
    if (taskId == null) return;
    _expandTimer = Timer(_autoExpandDelay, () {
      if (mounted) setState(() => _expandedTaskId = taskId);
    });
  }

  void _armHighlightTimer() {
    _highlightTimer?.cancel();
    if (_highlightedTaskId == null) return;
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedTaskId = null);
    });
  }

  void _scrollToHighlightIfNeeded() {
    if (_scrolledToHighlight || widget.highlightTaskId == null) return;
    final key = _taskKeys[widget.highlightTaskId];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final taskContext = key?.currentContext;
      if (taskContext == null || !mounted) return;
      Scrollable.ensureVisible(
        taskContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    });
    _scrolledToHighlight = true;
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider);
    final matches = projects.where((p) => p.id == widget.projectId);
    final project = matches.isEmpty ? null : matches.first;

    if (project == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClose());
      return const SizedBox.shrink();
    }

    final tasks = ref
        .watch(tasksProvider)
        .where((t) => t.projectId == widget.projectId)
        .toList();
    final reduceMotion = ref.watch(settingsProvider).reduceMotion;
    final accentColor = accentPalette[project.colorIndex];
    final doneCount = tasks.where((t) => t.isChecked).length;
    final progress = tasks.isEmpty ? 0.0 : doneCount / tasks.length;
    _scrollToHighlightIfNeeded();

    return Column(
      children: [
        _Header(
          project: project,
          accentColor: accentColor,
          doneCount: doneCount,
          totalCount: tasks.length,
          progress: progress,
          onClose: widget.onClose,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final twoPane =
                  constraints.maxWidth >= NocturneBreakpoints.medium;
              final gutter = constraints.maxWidth < NocturneBreakpoints.compact
                  ? NocturneSpace.s4
                  : NocturneSpace.s6;

              Widget taskList({required bool scrolls}) => tasks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: NocturneSpace.s6,
                        ),
                        child: Text(
                          'No tasks in this project yet.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1040),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: ReorderableListView.builder(
                            buildDefaultDragHandles: false,
                            shrinkWrap: true,
                            physics: scrolls
                                ? null
                                : const NeverScrollableScrollPhysics(),
                            itemCount: tasks.length,
                            onReorderItem: (oldIndex, newIndex) {
                              final reordered = [...tasks];
                              final moved = reordered.removeAt(oldIndex);
                              reordered.insert(newIndex, moved);
                              ref
                                  .read(tasksProvider.notifier)
                                  .reorderTasks(
                                    reordered.map((t) => t.id).toList(),
                                  );
                            },
                            itemBuilder: (context, index) {
                              final task = tasks[index];
                              final highlighted = task.id == _highlightedTaskId;
                              return PopOutRemoval(
                                key: _taskKeys.putIfAbsent(
                                  task.id,
                                  () => GlobalKey(),
                                ),
                                reduceMotion: reduceMotion,
                                shrinkWidth: false,
                                onRemoved: () => ref
                                    .read(tasksProvider.notifier)
                                    .deleteTask(task.id),
                                builder: (context, triggerRemoval) =>
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      decoration: BoxDecoration(
                                        color: highlighted
                                            ? accentColor.withValues(
                                                alpha: 0.16,
                                              )
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                          NocturneRadius.sm,
                                        ),
                                      ),
                                      child: TaskTile(
                                        task: task,
                                        onDelete: triggerRemoval,
                                        reorderIndex: index,
                                        expanded: task.id == _expandedTaskId,
                                        onExpandedChanged: (value) =>
                                            setState(() {
                                              _expandedTaskId = value
                                                  ? task.id
                                                  : null;
                                            }),
                                      ),
                                    ),
                              );
                            },
                          ),
                        ),
                      ),
                    );

              final sideCards = <Widget>[
                _ActivityCard(project: project),
                const SizedBox(height: NocturneSpace.s4),
                _CommentsCard(project: project),
              ];

              // Wide: tasks on the left, activity + comments on the right.
              if (twoPane) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(gutter),
                        child: taskList(scrolls: true),
                      ),
                    ),
                    Container(
                      width: 360,
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: context.nocturne.edge),
                        ),
                      ),
                      child: ListView(
                        padding: EdgeInsets.all(gutter),
                        children: sideCards,
                      ),
                    ),
                  ],
                );
              }

              // Narrower: one column — tasks, then activity, then comments.
              return ListView(
                padding: EdgeInsets.all(gutter),
                children: [
                  taskList(scrolls: false),
                  const SizedBox(height: NocturneSpace.s4),
                  ...sideCards,
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.project,
    required this.accentColor,
    required this.doneCount,
    required this.totalCount,
    required this.progress,
    required this.onClose,
  });

  final Project project;
  final Color accentColor;
  final int doneCount;
  final int totalCount;
  final double progress;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.nocturne;

    final identity = Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: onClose,
        ),
        Icon(Icons.folder, size: 24, color: accentColor),
        const SizedBox(width: NocturneSpace.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '$doneCount/$totalCount tasks done',
                style: TextStyle(fontSize: 12, color: tokens.neutral400),
              ),
              const SizedBox(height: NocturneSpace.s1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: GaugeBar(value: progress, color: accentColor, height: 4),
              ),
            ],
          ),
        ),
      ],
    );

    final actions = Wrap(
      spacing: NocturneSpace.s1,
      runSpacing: NocturneSpace.s1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Edit project',
          onPressed: () async {
            final result = await showProjectPromptDialog(
              context,
              title: 'Edit project',
              initialValue: project.name,
              initialColorIndex: project.colorIndex,
            );
            if (result != null) {
              final (name, colorIndex) = result;
              final notifier = ref.read(projectsProvider.notifier);
              notifier.renameProject(project.id, name);
              notifier.setProjectColor(project.id, colorIndex);
            }
          },
        ),
        IconButton(
          icon: Icon(project.archived ? Icons.restore : Icons.archive_outlined),
          tooltip: project.archived ? 'Unarchive project' : 'Archive project',
          onPressed: () {
            final notifier = ref.read(projectsProvider.notifier);
            if (project.archived) {
              notifier.unarchiveProject(project.id);
            } else {
              notifier.archiveProject(project.id);
              onClose();
            }
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete project',
          onPressed: () async {
            final confirmed = await showConfirmDialog(
              context,
              title: 'Delete project?',
              message:
                  'Tasks and subtasks inside "${project.name}" will be deleted too. This cannot be undone.',
            );
            if (confirmed) {
              ref.read(projectsProvider.notifier).deleteProject(project.id);
              onClose();
            }
          },
        ),
        const SizedBox(width: NocturneSpace.s1),
        NocturneButton(
          label: 'New task',
          icon: Icons.add,
          variant: NocturneButtonVariant.primary,
          color: accentColor,
          onPressed: () =>
              showCreateTaskSheet(context, initialProjectId: project.id),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NocturneSpace.s4,
        vertical: NocturneSpace.s2,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.edge)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Wide: identity and actions share one row. Narrow: the actions
          // drop to their own row (same buttons, nothing hidden).
          if (constraints.maxWidth >= NocturneBreakpoints.compact) {
            return Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: NocturneSpace.s3),
                actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final entries = project.activityLog.reversed.toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(NocturneSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const NocturneSectionLabel('Activity'),
            if (entries.isEmpty)
              Text(
                'No activity yet.',
                style: TextStyle(fontSize: 12, color: tokens.neutral500),
              )
            else
              for (final entry in entries.take(20)) _ActivityRow(entry: entry),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final accent = context.nocturneAccent;
    final (icon, color) = switch (entry.kind) {
      ActivityKind.projectCreated => (Icons.create_new_folder_outlined, accent),
      ActivityKind.taskAdded => (Icons.add_circle_outline, accent),
      ActivityKind.taskCompleted => (Icons.check_circle, tokens.done),
      ActivityKind.taskEdited => (Icons.edit_outlined, accent),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NocturneSpace.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: NocturneSpace.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.description,
                  style: TextStyle(fontSize: 13, color: tokens.neutral200),
                ),
                Text(
                  _relativeTime(entry.timestamp),
                  style: TextStyle(fontSize: 11, color: tokens.neutral500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentsCard extends ConsumerStatefulWidget {
  const _CommentsCard({required this.project});

  final Project project;

  @override
  ConsumerState<_CommentsCard> createState() => _CommentsCardState();
}

class _CommentsCardState extends ConsumerState<_CommentsCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final comments = widget.project.comments;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(NocturneSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const NocturneSectionLabel('Comments'),
            if (comments.isEmpty)
              Text(
                'No comments yet.',
                style: TextStyle(fontSize: 12, color: tokens.neutral500),
              )
            else
              for (final comment in comments)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: NocturneSpace.s1,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.text,
                        style: TextStyle(
                          fontSize: 13,
                          color: tokens.neutral200,
                        ),
                      ),
                      Text(
                        '${comment.author} · ${_relativeTime(comment.timestamp)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.neutral500,
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: NocturneSpace.s2),
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Add a comment'),
            ),
            const SizedBox(height: NocturneSpace.s2),
            Align(
              alignment: Alignment.centerLeft,
              child: NocturneButton(
                label: 'Post',
                dense: true,
                onPressed: _post,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _post() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final projects = ref.read(projectsProvider.notifier);
    projects.addComment(widget.project.id, projects.authorName, text);
    _controller.clear();
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
