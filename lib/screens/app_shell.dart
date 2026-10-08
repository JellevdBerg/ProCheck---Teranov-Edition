import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project.dart';
import '../models/shortcut_binding.dart';
import '../providers/projects_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/undo_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/create_task_sheet.dart';
import '../widgets/sidebar/app_sidebar.dart';
import '../widgets/text_prompt_dialog.dart';
import 'admin_screen.dart';
import 'app_screen.dart';
import 'archived_screen.dart';
import 'calendar_screen.dart';
import 'dashboard_screen.dart';
import 'day_screen.dart';
import 'project_detail_overlay.dart';
import 'projects_screen.dart';
import 'settings_screen.dart';
import 'team_screen.dart';
import 'templates_screen.dart';
import 'today_screen.dart';
import 'upcoming_screen.dart';

/// Requests the bottom-right undo button, replacing whatever it was
/// currently offering to undo.
typedef ShowUndo = void Function({required String label, required VoidCallback onUndo});

/// Requests the project-detail overlay open on top of whatever screen is
/// currently showing — [originRect] is the tapped card's rect (in the main
/// content area's own coordinate space) for the card-morph animation, or
/// null to just fade in (e.g. opened from a sidebar favorite, with no card
/// to morph from).
typedef OpenProjectDetail = void Function(String projectId, {Rect? originRect});

/// The app's root shell once past the splash screen: a persistent sidebar
/// plus a main content area that swaps between screens without the sidebar
/// ever leaving. Project detail is a card-morph overlay drawn on top of the
/// main content area (see [ProjectDetailOverlay]), not a separate route —
/// that's what lets the sidebar stay visible while it's open.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with TickerProviderStateMixin {
  late AppScreen _screen;
  DateTime? _selectedDay;
  DateTime _calendarMonth = DateTime.now();

  String? _toastMessage;
  Timer? _toastTimer;

  _PendingUndo? _pendingUndo;
  Timer? _undoTimer;

  String? _detailProjectId;
  Rect? _originRect;
  String? _highlightTaskId;
  String? _highlightUnfiledTaskId;
  late final AnimationController _morphController = AnimationController(
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 260),
    vsync: this,
  );

  final GlobalKey _mainAreaKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _screen = switch (settings.defaultLanding) {
      LandingScreenOption.projects => AppScreen.projects,
      LandingScreenOption.templates => AppScreen.templates,
      LandingScreenOption.dashboard => AppScreen.dashboard,
      LandingScreenOption.lastViewed =>
        AppScreen.values[settings.lastViewedScreenIndex.clamp(
          0,
          AppScreen.values.length - 1,
        )],
    };
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _undoTimer?.cancel();
    _morphController.dispose();
    super.dispose();
  }

  void _switchScreen(AppScreen screen) {
    setState(() {
      _screen = screen;
      _highlightUnfiledTaskId = null;
    });
    ref.read(settingsProvider.notifier).recordLastViewedScreen(screen.index);
    if (_detailProjectId != null) _closeProjectDetail();
  }

  void _showToast(String message) {
    setState(() => _toastMessage = message);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  void _showUndo({required String label, required VoidCallback onUndo}) {
    _undoTimer?.cancel();
    setState(() => _pendingUndo = _PendingUndo(label: label, onUndo: onUndo));
    _undoTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _pendingUndo = null);
    });
  }

  void _resolveUndo() {
    _undoTimer?.cancel();
    _pendingUndo?.onUndo();
    setState(() => _pendingUndo = null);
  }

  void _openProjectDetail(
    String projectId, {
    Rect? originRect,
    String? highlightTaskId,
  }) {
    final reduceMotion = ref.read(settingsProvider).reduceMotion;
    setState(() {
      _detailProjectId = projectId;
      _originRect = originRect;
      _highlightTaskId = highlightTaskId;
    });
    if (reduceMotion) {
      _morphController.value = 1;
    } else {
      _morphController.forward(from: 0);
    }
  }

  void _closeProjectDetail() {
    final reduceMotion = ref.read(settingsProvider).reduceMotion;
    if (reduceMotion) {
      _morphController.value = 0;
      setState(() => _detailProjectId = null);
      return;
    }
    _morphController.reverse().whenComplete(() {
      if (mounted) setState(() => _detailProjectId = null);
    });
  }

  /// Opens [projectId]'s detail overlay, card-morphing from [cardContext]'s
  /// rect. Passing [taskId] additionally scrolls to and briefly highlights
  /// that task once the overlay is open — used when navigating in from a
  /// specific task (e.g. the Dashboard's overdue list) rather than the
  /// project itself.
  void _openProjectFromCard(
    String projectId,
    BuildContext cardContext, {
    String? taskId,
  }) {
    final cardBox = cardContext.findRenderObject() as RenderBox?;
    final mainBox =
        _mainAreaKey.currentContext?.findRenderObject() as RenderBox?;
    Rect? rect;
    if (cardBox != null && mainBox != null) {
      final origin = cardBox.localToGlobal(Offset.zero, ancestor: mainBox);
      rect = origin & cardBox.size;
    }
    ref.read(projectsProvider.notifier).touchProject(projectId);
    _openProjectDetail(projectId, originRect: rect, highlightTaskId: taskId);
  }

  /// The one "open this task" behavior used everywhere a task can be
  /// tapped outside its own project (Today, Upcoming, Calendar, the
  /// sidebar search, …): a filed task opens its project, scrolled to and
  /// highlighting it — card-morphing from [cardContext]'s rect when one is
  /// given, else just fading in (e.g. from the sidebar, where there's no
  /// card to morph from). An unfiled task has no project to open, so it
  /// opens the Projects screen instead, scrolled to and highlighting it in
  /// the unfiled list there.
  void _openTask(String? projectId, String taskId, [BuildContext? cardContext]) {
    if (projectId == null) {
      _openUnfiledTask(taskId);
      return;
    }
    if (cardContext != null) {
      _openProjectFromCard(projectId, cardContext, taskId: taskId);
    } else {
      ref.read(projectsProvider.notifier).touchProject(projectId);
      _openProjectDetail(projectId, highlightTaskId: taskId);
    }
  }

  void _openUnfiledTask(String taskId) {
    setState(() {
      _screen = AppScreen.projects;
      _highlightUnfiledTaskId = taskId;
    });
    if (_detailProjectId != null) _closeProjectDetail();
  }

  /// Jumps into the Day view for [day] — used by both the sidebar's mini
  /// calendar and the full Calendar screen, so clicking a date behaves the
  /// same no matter where it was clicked from.
  void _onDaySelected(DateTime day) {
    setState(() {
      _selectedDay = day;
      _calendarMonth = day;
      _screen = AppScreen.day;
    });
    if (_detailProjectId != null) _closeProjectDetail();
  }

  void _openFavoriteProject(Project project) {
    ref.read(projectsProvider.notifier).touchProject(project.id);
    setState(() => _screen = AppScreen.projects);
    _openProjectDetail(project.id);
  }

  Future<void> _newProjectShortcut() async {
    _showToast('New project');
    final result = await showProjectPromptDialog(
      context,
      title: 'New project',
      confirmLabel: 'Create',
    );
    if (result != null) {
      final (name, colorIndex) = result;
      ref.read(projectsProvider.notifier).addProject(name, colorIndex: colorIndex);
    }
  }

  Future<void> _newTaskShortcut() async {
    _showToast('New task');
    await showCreateTaskSheet(context);
  }

  /// Pops the most recent deletion off the undo stack (project or task —
  /// see undo_provider.dart), restoring it fully. Repeated Ctrl+Z walks
  /// back through consecutive deletions, unlike the floating "Undo" button
  /// below, which only ever offers the single most recent one before it
  /// expires.
  void _undoShortcut() {
    final message = ref.read(undoStackProvider.notifier).undoLast();
    if (message != null) _showToast(message);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final settings = ref.watch(settingsProvider);

    final bindings = <ShortcutActivator, VoidCallback>{};
    for (final activator
        in settings.shortcutFor(ShortcutAction.newProject).toActivators()) {
      bindings[activator] = _newProjectShortcut;
    }
    for (final activator
        in settings.shortcutFor(ShortcutAction.newTask).toActivators()) {
      bindings[activator] = _newTaskShortcut;
    }
    for (final activator
        in settings.shortcutFor(ShortcutAction.undo).toActivators()) {
      bindings[activator] = _undoShortcut;
    }

    // CallbackShortcuts' own internal Focus node has canRequestFocus: false
    // (see the framework source) — it's a pass-through that only sees key
    // events bubbling up from a descendant that actually holds focus. An
    // autofocused Focus node has to sit *inside* it (wrapping the Scaffold)
    // for that bubbling to ever reach it; putting the autofocus outside, as
    // this used to, gives primary focus to a node CallbackShortcuts can
    // never see key events from, since propagation only walks upward
    // through ancestors, never down into children.
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: tokens.bg,
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSidebar(
                currentScreen: _screen,
                onScreenSelected: _switchScreen,
                onFavoriteProjectTap: _openFavoriteProject,
                onDaySelected: _onDaySelected,
                onOpenTask: (projectId, taskId) => _openTask(projectId, taskId),
                calendarMonth: _calendarMonth,
                selectedDay: _selectedDay,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      key: _mainAreaKey,
                      children: [
                        // A quiet neutral vignette (never accent-tinted —
                        // see NocturneColors doc comment) behind every
                        // screen, so the main content area reads as a
                        // designed surface rather than one flat fill color.
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(0, -1),
                                radius: 1.6,
                                colors: [tokens.surface, tokens.bg],
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(child: _buildScreen()),
                        if (_detailProjectId != null)
                          _buildDetailOverlay(constraints),
                        if (_pendingUndo != null)
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: _UndoButton(
                              label: _pendingUndo!.label,
                              onPressed: _resolveUndo,
                            ),
                          ),
                        if (_toastMessage != null)
                          Positioned(
                            bottom: 20,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: _Toast(message: _toastMessage!),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailOverlay(BoxConstraints constraints) {
    const margin = 16.8;
    final expanded = Rect.fromLTWH(
      margin,
      margin,
      (constraints.maxWidth - margin * 2).clamp(0, double.infinity),
      (constraints.maxHeight - margin * 2).clamp(0, double.infinity),
    );
    final origin = _originRect ?? expanded;

    return AnimatedBuilder(
      animation: _morphController,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_morphController.value);
        final rect = Rect.lerp(origin, expanded, t)!;
        final contentOpacity = ((_morphController.value - 0.35) / 0.65).clamp(
          0.0,
          1.0,
        );
        return Positioned.fromRect(
          rect: rect,
          child: Material(
            color: context.nocturne.bg,
            elevation: 8,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(NocturneRadius.md),
            child: Opacity(
              opacity: contentOpacity,
              child: child,
            ),
          ),
        );
      },
      child: ProjectDetailOverlay(
        projectId: _detailProjectId!,
        onClose: _closeProjectDetail,
        highlightTaskId: _highlightTaskId,
      ),
    );
  }

  Widget _buildScreen() {
    return switch (_screen) {
      AppScreen.projects => ProjectsScreen(
        onShowUndo: _showUndo,
        onOpenProject: _openProjectFromCard,
        highlightTaskId: _highlightUnfiledTaskId,
      ),
      AppScreen.today => TodayScreen(onOpenTask: _openTask),
      AppScreen.upcoming => UpcomingScreen(onOpenTask: _openTask),
      AppScreen.calendar => CalendarScreen(
        onDaySelected: _onDaySelected,
        onOpenTask: _openTask,
      ),
      AppScreen.day => DayScreen(
        date: _selectedDay ?? DateTime.now(),
        onOpenTask: _openTask,
      ),
      AppScreen.templates => const TemplatesScreen(),
      AppScreen.archived => ArchivedScreen(
        onOpenProject: _openProjectFromCard,
        onOpenTask: _openTask,
      ),
      AppScreen.settings => const SettingsScreen(),
      AppScreen.dashboard => DashboardScreen(
        onOpenProject: _openProjectFromCard,
        onOpenTask: _openTask,
      ),
      AppScreen.team => const TeamScreen(),
      AppScreen.admin => const AdminScreen(),
    };
  }
}

/// What's currently offered for undo — at most one at a time.
class _PendingUndo {
  _PendingUndo({required this.label, required this.onUndo});
  final String label;
  final VoidCallback onUndo;
}

/// A small floating "Undo" button pinned to the bottom-right: it doesn't
/// queue behind earlier removals (a new one replaces it) and expires on its
/// own after a few seconds instead of lingering.
class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'undo-button',
      onPressed: onPressed,
      tooltip: label,
      icon: const Icon(Icons.undo),
      label: const Text('Undo'),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.neutral800,
        borderRadius: BorderRadius.circular(NocturneRadius.md),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Text(
          '$message (shortcut)',
          style: TextStyle(fontSize: 13, color: tokens.text),
        ),
      ),
    );
  }
}
