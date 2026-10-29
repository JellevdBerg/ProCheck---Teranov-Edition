import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/department.dart';
import '../models/profile.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../providers/department_members_provider.dart';
import '../providers/departments_provider.dart';
import '../providers/projects_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/undo_provider.dart';
import '../providers/roles_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/create_task_sheet.dart';
import '../widgets/motion_widgets.dart';
import '../widgets/nocturne/nocturne_widgets.dart';
import '../widgets/panel/panel.dart';
import '../widgets/people_plates.dart';
import '../widgets/pop_out_removal.dart';
import '../widgets/project_card.dart';
import '../widgets/task_filter_bar.dart';
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
  static const _featuredCardMinWidth = 280.0;
  static const _featuredCardMaxWidth = 400.0;

  final _searchController = TextEditingController();
  String _query = '';

  /// Department filter, offered to Operator/IT only; null = all.
  String? _departmentId;

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
    // Operator/IT see every department, so they get a department filter.
    final filterDepartments = ref.watch(taskFilterOptionsProvider).departments;
    final departmentId =
        filterDepartments.any((d) => d.id == _departmentId) ? _departmentId : null;
    final projects = allProjects
        .where((p) => departmentId == null || p.departmentId == departmentId)
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = constraints.maxWidth < NocturneBreakpoints.compact
            ? NocturneSpace.s4
            : NocturneSpace.s6;
        return ListView(
          key: const Key('projects-scroll'),
          padding: EdgeInsets.fromLTRB(
            gutter,
            gutter,
            gutter,
            NocturneSpace.s6,
          ),
          children: [
            // Title left, search and "New project" right; they drop under the
            // title when the window is too narrow for one line.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: NocturneSpace.s3,
              runSpacing: NocturneSpace.s3,
              children: [
                Text(
                  'Projects',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth - 2 * gutter,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: SizedBox(
                          width: 280,
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) => setState(() => _query = value),
                            decoration: const InputDecoration(
                              hintText: 'Search projects',
                              prefixIcon: Icon(Icons.search, size: 18),
                            ),
                          ),
                        ),
                      ),
                      // Only people the database lets create projects see the button.
                      if (ref.watch(permissionsProvider).createProjects) ...[
                        const SizedBox(width: NocturneSpace.s2),
                        NocturneButton(
                          label: 'New project',
                          minWidth: 132,
                          icon: Icons.add,
                          variant: NocturneButtonVariant.primary,
                          onPressed: () => _createProject(context),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: NocturneSpace.s6),
            if (allProjects.isNotEmpty) ...[
              if (filterDepartments.isEmpty)
                const NocturneSectionLabel('PROJECTS')
              else
                ..._departmentFilter(context, allProjects, filterDepartments, departmentId),
              if (projects.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    query.isEmpty
                        ? 'No projects in this department.'
                        : 'No projects match "${_query.trim()}".',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                _buildGrid(context, projects, tasksByProject, reduceMotion),
              const SizedBox(height: NocturneSpace.s6),
            ],
            // Same cap as the task list below, so the button sits at the
            // list's right edge instead of the window's on wide screens.
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: double.infinity),
                child: Row(
                  children: [
                    const StampLabel('PERSONAL'),
                    const SizedBox(width: NocturneSpace.s2),
                    // Clarifies this pool's scope now that the company edition
                    // also has project-filed tasks — these are personal errands
                    // with no project, not "every task", muted to read as a
                    // secondary grouping rather than the main list.
                    Expanded(
                      child: Text(
                        'Not tied to any project — everyone has their own.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.nocturne.neutral400,
                        ),
                      ),
                    ),
                    const SizedBox(width: NocturneSpace.s2),
                    NocturneButton(
                      label: 'New task',
                      icon: Icons.add,
                      onPressed: () => showCreateTaskSheet(context),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: NocturneSpace.s3),
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
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: double.infinity),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.zero,
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
                              .reorderTasks(
                                reordered.map((t) => t.id).toList(),
                              );
                        },
                        itemBuilder: (context, i) {
                          final task = unfiledTasks[i];
                          final highlighted = task.id == _highlightedTaskId;
                          // The list item key moves to StaggerIn, the outermost widget.
                          return StaggerIn(
                            key: _unfiledTaskKeys.putIfAbsent(
                              task.id,
                              () => GlobalKey(),
                            ),
                            index: i,
                            isNew: isJustAdded(task.createdAt),
                            child: PopOutRemoval(
                            reduceMotion: reduceMotion,
                            shrinkWidth: false,
                            onRemoved: () => ref
                                .read(tasksProvider.notifier)
                                .deleteTask(task.id),
                            builder: (context, triggerRemoval) =>
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  decoration: BoxDecoration(
                                    color: highlighted
                                        ? context.nocturneAccent.withValues(
                                            alpha: 0.16,
                                          )
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(
                                      NocturneRadius.md,
                                    ),
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
                                      onUndo: () => ref
                                          .read(undoStackProvider.notifier)
                                          .undoLast(),
                                    ),
                                    autoRemoveWhenChecked: true,
                                    reorderIndex: i,
                                    expanded: task.id == _expandedTaskId,
                                    onExpandedChanged: (value) => setState(() {
                                      _expandedTaskId = value ? task.id : null;
                                    }),
                                  ),
                                ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// All projects flow into a plain wrapping grid: as many columns as fit
  /// the width the page is given, then more rows (the page scrolls
  /// vertically; there is no horizontal paging).
  Widget _buildGrid(
    BuildContext context,
    List<Project> projects,
    Map<String, List<Task>> tasksByProject,
    bool reduceMotion,
  ) {
    final departments = ref.watch(departmentsProvider).valueOrNull ?? const <Department>[];
    final members = ref.watch(departmentMembersProvider).valueOrNull ?? const <Profile>[];
    final directory = ref.watch(profileDirectoryProvider).valueOrNull ??
        const <String, DirectoryEntry>{};
    final dateFormat = ref.watch(settingsProvider).dateFormat;
    final tokens = context.nocturne;

    Widget? plateFor(Project project) {
      final d = departments.where((d) => d.id == project.departmentId).firstOrNull;
      return d == null
          ? null
          : DepartmentPlate(name: d.name, isOperator: d.isOperator, isIt: d.isIt);
    }

    List<String> assigneesFor(List<Task>? tasks) => {
      for (final t in tasks ?? const <Task>[])
        if (t.assigneeId != null)
          members.where((m) => m.id == t.assigneeId).firstOrNull?.displayName ??
              directory[t.assigneeId]?.displayName,
    }.nonNulls.toList();

    // The soonest due date among the project's open tasks.
    Widget? dueTagFor(List<Task>? tasks) {
      final open = (tasks ?? const <Task>[])
          .where((t) => !t.isChecked && t.dueDate != null)
          .toList()
        ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
      if (open.isEmpty) return null;
      final tone = dueTone(open.first, tokens);
      return NocturneTag(
        label: formatDueLabel(open.first, dateFormat),
        icon: Icons.access_time,
        color: tone,
        outline: tone == null,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = NocturneSpace.s4;
        // As many columns as fit at the minimum width; cards then share the
        // row but never grow past the maximum, so a few projects keep a card
        // shape instead of stretching across a wide window.
        final columns = math.max(
          1,
          ((constraints.maxWidth + gap) / (_featuredCardMinWidth + gap)).floor(),
        );
        final cardWidth = math.min(
          _featuredCardMaxWidth,
          (constraints.maxWidth - gap * (columns - 1)) / columns,
        );

        Widget buildCard(Project project) => PopOutRemoval(
          key: ValueKey(project.id),
          reduceMotion: reduceMotion,
          onRemoved: () =>
              ref.read(projectsProvider.notifier).deleteProject(project.id),
          builder: (context, triggerRemoval) => SizedBox(
            width: cardWidth,
            child: Builder(
              builder: (cardContext) => ProjectCard(
                project: project,
                featured: true,
                reduceMotion: reduceMotion,
                tasks: tasksByProject[project.id] ?? const [],
                departmentPlate: plateFor(project),
                assigneeNames: assigneesFor(tasksByProject[project.id]),
                dueTag: dueTagFor(tasksByProject[project.id]),
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

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            for (var i = 0; i < projects.length; i++)
              StaggerIn(
                key: ValueKey(projects[i].id),
                index: i,
                child: buildCard(projects[i]),
              ),
          ],
        );
      },
    );
  }

  /// The "All departments" heading and the Operator/IT department filter,
  /// one segment per department that owns a project, with counts.
  List<Widget> _departmentFilter(
    BuildContext context,
    List<Project> projects,
    List<Department> departments,
    String? selectedId,
  ) {
    int count(String? id) =>
        projects.where((p) => id == null || p.departmentId == id).length;
    final options = <String?>[
      null,
      for (final d in departments)
        if (count(d.id) > 0) d.id,
    ];
    final selected = departments.where((d) => d.id == selectedId).firstOrNull;
    return [
      Wrap(
        spacing: NocturneSpace.s2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StampLabel(selected == null ? 'ALL DEPARTMENTS' : selected.name.toUpperCase()),
          Text(
            "You can see every department's projects.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.nocturne.neutral400,
            ),
          ),
        ],
      ),
      const SizedBox(height: NocturneSpace.s3),
      Align(
        alignment: Alignment.centerLeft,
        child: NocturneSegmented<String?>(
          options: options,
          value: selectedId,
          labelBuilder: (id) =>
              '${id == null ? 'All' : departments.firstWhere((d) => d.id == id).name}  ${count(id)}',
          onChanged: (id) => setState(() => _departmentId = id),
        ),
      ),
      const SizedBox(height: NocturneSpace.s3),
    ];
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
    ref
        .read(projectsProvider.notifier)
        .addProject(name, colorIndex: colorIndex);
  }
}
