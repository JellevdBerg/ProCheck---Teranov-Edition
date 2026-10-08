import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/task.dart';
import '../providers/projects_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/undo_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/create_task_sheet.dart';
import '../widgets/industrial/industrial_panel.dart';
import '../widgets/nocturne/nocturne_widgets.dart';
import '../widgets/pop_out_removal.dart';
import '../widgets/project_card.dart';
import '../widgets/task_tile.dart';
import '../widgets/text_prompt_dialog.dart';
import 'app_shell.dart';

/// The default/home screen: a search bar, the project grid (each card opens
/// via the card-morph overlay), and a bordered list of unfiled tasks below
/// it.
class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({
    super.key,
    required this.onShowUndo,
    required this.onOpenProject,
    this.highlightTaskId,
  });

  final ShowUndo onShowUndo;
  final void Function(String projectId, BuildContext cardContext) onOpenProject;

  /// When set, the matching unfiled task is scrolled into view and briefly
  /// highlighted — used when navigating in from an unfiled task elsewhere
  /// in the app (Today, Upcoming, Calendar, the sidebar search, …), which
  /// have no project of their own to open.
  final String? highlightTaskId;

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  static const _featuredCardHeight = 280.0;
  static const _featuredCardMinWidth = 240.0;

  final _searchController = TextEditingController();
  final _gridScrollController = ScrollController();
  String _query = '';

  final Map<String, GlobalKey> _unfiledTaskKeys = {};
  String? _highlightedTaskId;
  Timer? _highlightTimer;
  bool _scrolledToHighlight = false;

  String? _expandedTaskId;
  Timer? _expandTimer;

  /// How long after this screen opens with a [ProjectsScreen.highlightTaskId]
  /// before that task auto-expands — mirrors [ProjectDetailOverlay]'s own
  /// delay, giving the scroll-into-view a moment to settle first rather than
  /// the task popping open instantly underneath it.
  static const _autoExpandDelay = Duration(milliseconds: 450);

  @override
  void initState() {
    super.initState();
    _highlightedTaskId = widget.highlightTaskId;
    _armHighlightTimer();
    _armExpandTimer();
  }

  @override
  void didUpdateWidget(covariant ProjectsScreen oldWidget) {
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

  void _armHighlightTimer() {
    _highlightTimer?.cancel();
    if (_highlightedTaskId == null) return;
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedTaskId = null);
    });
  }

  void _armExpandTimer() {
    _expandTimer?.cancel();
    final taskId = widget.highlightTaskId;
    if (taskId == null) return;
    _expandTimer = Timer(_autoExpandDelay, () {
      if (mounted) setState(() => _expandedTaskId = taskId);
    });
  }

  void _scrollToHighlightIfNeeded() {
    if (_scrolledToHighlight || widget.highlightTaskId == null) return;
    // The lookup has to happen *inside* the callback, not before it's
    // scheduled: on a freshly-created state the unfiled list's itemBuilder
    // (which populates _unfiledTaskKeys) hasn't run yet at this point in
    // build(), so capturing the key now would always capture null.
    final highlightTaskId = widget.highlightTaskId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final taskContext = _unfiledTaskKeys[highlightTaskId]?.currentContext;
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
  void dispose() {
    _searchController.dispose();
    _gridScrollController.dispose();
    _highlightTimer?.cancel();
    _expandTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allProjects = ref
        .watch(projectsProvider)
        .where((p) => !p.archived)
        .toList();
    final tasks = ref.watch(tasksProvider);
    final reduceMotion = ref.watch(settingsProvider).reduceMotion;
    final unfiledTasks = tasks.where((t) => t.projectId == null).toList();
    _scrollToHighlightIfNeeded();

    final query = _query.trim().toLowerCase();
    final projects = query.isEmpty
        ? allProjects
        : allProjects
              .where((p) => p.name.toLowerCase().contains(query))
              .toList();

    // Grouped once per build rather than once per card — each card
    // re-scanning the full task list itself turns the grid into an
    // O(projects × tasks) rebuild as either side grows into the
    // hundreds/thousands.
    final tasksByProject = <String, List<Task>>{};
    for (final task in tasks) {
      final projectId = task.projectId;
      if (projectId == null) continue;
      (tasksByProject[projectId] ??= []).add(task);
    }

    return ListView(
      key: const Key('projects-scroll'),
      padding: const EdgeInsets.fromLTRB(16.8, 16.8, 16.8, 22.4),
      children: [
        Row(
          children: [
            // A single Expanded — rather than a Flexible competing for flex
            // space with a separate Spacer — is what keeps the trailing
            // controls flush against the right edge as the window widens;
            // two same-priority flexible children split the leftover space
            // between them instead of handing it all to the Spacer.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: 'Search projects',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            NocturneButton(
              label: 'New project',
              icon: Icons.add,
              variant: NocturneButtonVariant.primary,
              onPressed: () => _createProject(context),
            ),
          ],
        ),
        const SizedBox(height: 16.8),
        if (allProjects.isNotEmpty) ...[
          const NocturneSectionLabel('PROJECTS'),
          if (projects.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No projects match "${_query.trim()}".',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            _buildGrid(context, projects, tasksByProject, reduceMotion),
          const SizedBox(height: 16.8),
        ],
        Row(
          children: [
            const Expanded(child: NocturneSectionLabel('TASKS')),
            NocturneButton(
              label: 'New task',
              icon: Icons.add,
              variant: NocturneButtonVariant.primary,
              onPressed: () => showCreateTaskSheet(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (unfiledTasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No unfiled tasks. Use "New task" above, or "New project" to '
              'get organized.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          IndustrialPanel(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11.2),
              // A real ReorderableListView, not a plain Column — the drag
              // handle TaskTile shows for a non-null reorderIndex needs an
              // enclosing SliverReorderableList to actually respond to
              // (previously there wasn't one here, so the handle appeared
              // but silently did nothing). shrinkWrap + NeverScrollable:
              // this sits inside the page's own vertical ListView, so it
              // sizes to its content and leaves scrolling to that parent
              // rather than fighting it for the same axis.
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: unfiledTasks.length,
                onReorderItem: (oldIndex, newIndex) {
                  final reordered = [...unfiledTasks];
                  final moved = reordered.removeAt(oldIndex);
                  reordered.insert(newIndex, moved);
                  ref
                      .read(tasksProvider.notifier)
                      .reorderTasks(reordered.map((t) => t.id).toList());
                },
                itemBuilder: (context, i) {
                  final task = unfiledTasks[i];
                  final highlighted = task.id == _highlightedTaskId;
                  return PopOutRemoval(
                    key: _unfiledTaskKeys.putIfAbsent(task.id, () => GlobalKey()),
                    reduceMotion: reduceMotion,
                    shrinkWidth: false,
                    onRemoved: () =>
                        ref.read(tasksProvider.notifier).deleteTask(task.id),
                    builder: (context, triggerRemoval) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        color: highlighted
                            ? context.nocturneAccent.withValues(alpha: 0.16)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(NocturneRadius.md),
                      ),
                      child: TaskTile(
                        task: task,
                        onDelete: triggerRemoval,
                        // deleteTask (triggered by triggerRemoval, just
                        // above) already pushed this onto the undo stack —
                        // routing the button through the same stack, rather
                        // than a direct restoreTask call, keeps this in
                        // sync with Ctrl+Z instead of risking a stale
                        // second restore of a task Ctrl+Z already brought
                        // back.
                        onExplicitDelete: () => widget.onShowUndo(
                          label: '"${task.title}" deleted',
                          onUndo: () =>
                              ref.read(undoStackProvider.notifier).undoLast(),
                        ),
                        autoRemoveWhenChecked: true,
                        reorderIndex: i,
                        expanded: task.id == _expandedTaskId,
                        onExpandedChanged: (value) => setState(() {
                          _expandedTaskId = value ? task.id : null;
                        }),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  /// The grid never grows past this many rows — beyond it, projects flow
  /// into a new horizontally-scrollable page instead (see [_buildGrid]).
  static const _maxGridRows = 2;

  Widget _buildGrid(
    BuildContext context,
    List<Project> projects,
    Map<String, List<Task>> tasksByProject,
    bool reduceMotion,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCapacity = (constraints.maxWidth / _featuredCardMinWidth)
            .floor()
            .clamp(1, 1 << 30);
        final spacing = 11.2 * (columnCapacity - 1);
        final cardWidth = (constraints.maxWidth - spacing) / columnCapacity;
        // Only as tall as the current projects actually need, capped at
        // _maxGridRows — one row of projects shouldn't reserve a whole
        // second row's worth of dead space below it.
        final rowsNeeded = (projects.length / columnCapacity).ceil().clamp(
          1,
          _maxGridRows,
        );
        final gridHeight =
            _featuredCardHeight * rowsNeeded + 11.2 * (rowsNeeded - 1);

        // Each "page" is a full-width Wrap that fills left-to-right,
        // top-to-bottom exactly like before, just capped to the number of
        // cards that fit in _maxGridRows rows — extra projects start a new
        // page instead of a 3rd row, and those pages sit side by side in a
        // horizontally scrolling Row.
        final perPage = columnCapacity * _maxGridRows;
        final pages = <List<Project>>[];
        for (var i = 0; i < projects.length; i += perPage) {
          final end = (i + perPage < projects.length)
              ? i + perPage
              : projects.length;
          pages.add(projects.sublist(i, end));
        }

        Widget buildCard(Project project) => PopOutRemoval(
          key: ValueKey(project.id),
          reduceMotion: reduceMotion,
          onRemoved: () =>
              ref.read(projectsProvider.notifier).deleteProject(project.id),
          builder: (context, triggerRemoval) => SizedBox(
            width: cardWidth,
            height: _featuredCardHeight,
            child: Builder(
              builder: (cardContext) => ProjectCard(
                project: project,
                featured: true,
                reduceMotion: reduceMotion,
                tasks: tasksByProject[project.id] ?? const [],
                onTap: () => widget.onOpenProject(project.id, cardContext),
                onDelete: triggerRemoval,
                onArchive: () => _archiveProject(project),
                onToggleFavorite: () => ref
                    .read(projectsProvider.notifier)
                    .toggleFavorite(project.id),
              ),
            ),
          ),
        );

        return SizedBox(
          height: gridHeight,
          // A plain mouse wheel only ever reports a vertical delta, which a
          // purely-horizontal Scrollable otherwise ignores outright — remap
          // it onto this scrollable's own axis so the wheel (not just
          // click-and-drag, or a trackpad's native horizontal swipe) can
          // reach the pages beyond the first.
          child: Listener(
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent ||
                  !_gridScrollController.hasClients) {
                return;
              }
              final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
                  ? event.scrollDelta.dx
                  : event.scrollDelta.dy;
              _gridScrollController.position.pointerScroll(delta);
            },
            child: SingleChildScrollView(
              controller: _gridScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var p = 0; p < pages.length; p++) ...[
                    if (p > 0) const SizedBox(width: 11.2),
                    SizedBox(
                      width: constraints.maxWidth,
                      child: Wrap(
                        spacing: 11.2,
                        runSpacing: 11.2,
                        children: [
                          for (final project in pages[p]) buildCard(project),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _archiveProject(Project project) {
    ref.read(projectsProvider.notifier).archiveProject(project.id);
    widget.onShowUndo(
      label: '"${project.name}" archived',
      onUndo: () =>
          ref.read(projectsProvider.notifier).unarchiveProject(project.id),
    );
  }

  Future<void> _createProject(BuildContext context) async {
    final result = await showProjectPromptDialog(
      context,
      title: 'New project',
      confirmLabel: 'Create',
    );
    if (result == null) return;
    final (name, colorIndex) = result;
    ref.read(projectsProvider.notifier).addProject(name, colorIndex: colorIndex);
  }
}
