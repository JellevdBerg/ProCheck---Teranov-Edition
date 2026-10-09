import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/supabase_config.dart';
import '../../models/project.dart';
import '../../models/task.dart';
import '../../providers/auth_provider.dart';
import '../../providers/departments_provider.dart';
import '../../providers/projects_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_templates_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../screens/app_screen.dart';
import '../../screens/dashboard_screen.dart';
import '../../screens/login_screen.dart';
import '../../theme/nocturne_theme.dart';
import '../app_logo.dart';
import '../blurred_dialog.dart';
import '../panel/panel.dart';
import '../project_name_lookup.dart';
import 'mini_calendar.dart';

/// The persistent left navigation column: a sign-out row (once Supabase is
/// configured and signed in), smart views (Today/Upcoming), Favorites, the
/// Projects/Templates/Archived library, a mini calendar, and Settings —
/// collapsible to an icon-only rail.
class AppSidebar extends ConsumerWidget {
  const AppSidebar({
    super.key,
    required this.currentScreen,
    required this.onScreenSelected,
    required this.onFavoriteProjectTap,
    required this.onDaySelected,
    required this.onOpenTask,
    required this.calendarMonth,
    required this.selectedDay,
  });

  final AppScreen currentScreen;
  final ValueChanged<AppScreen> onScreenSelected;
  final ValueChanged<Project> onFavoriteProjectTap;
  final ValueChanged<DateTime> onDaySelected;

  /// Opens a task picked from the inline search field — its project,
  /// scrolled to and highlighting it, or the Projects screen's unfiled
  /// list when it has no project.
  final void Function(String? projectId, String taskId) onOpenTask;
  final DateTime calendarMonth;
  final DateTime? selectedDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final projects = ref.watch(projectsProvider);
    final tasks = ref.watch(tasksProvider);
    final templates = ref.watch(taskTemplatesProvider);
    final tokens = context.nocturne;
    final accent = context.nocturneAccent;
    final expanded = settings.sidebarExpanded;
    final signedIn = isSupabaseConfigured && supabase.auth.currentUser != null;
    final profile = signedIn
        ? ref.watch(currentProfileProvider).valueOrNull
        : null;
    final isAdmin = signedIn
        ? ref.watch(isAdminProvider).valueOrNull ?? false
        : false;

    final now = DateTime.now();
    final todayCount = tasks
        .where(
          (t) =>
              !t.isChecked && t.dueDate != null && _isSameDay(t.dueDate!, now),
        )
        .length;
    final upcomingCount = tasks
        .where(
          (t) =>
              !t.isChecked &&
              t.dueDate != null &&
              t.dueDate!.isAfter(
                DateTime(now.year, now.month, now.day, 23, 59),
              ),
        )
        .length;
    final activeProjects = projects.where((p) => !p.archived).toList();
    final favorites = activeProjects.where((p) => p.favorite).toList();
    final archivedCount = projects.where((p) => p.archived).length;

    final activeProjectIds = activeProjects.map((p) => p.id).toSet();
    final dashboardCount = tasks
        .where(
          (t) =>
              (t.projectId == null || activeProjectIds.contains(t.projectId)) &&
              (isOpenTask(t, now) || isPendingTask(t, now)),
        )
        .length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: expanded ? 232 : 68,
      // Brushed-metal rail: a faint left-to-right sheen over the chassis.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.lerp(tokens.bg, tokens.hi, tokens.isDark ? 0.18 : 0.5)!,
            tokens.bg,
          ],
        ),
        border: Border(right: BorderSide(color: tokens.edge)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          _Header(
            expanded: expanded,
            onToggle: () => ref
                .read(settingsProvider.notifier)
                .setSidebarExpanded(!expanded),
          ),
          if (signedIn) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _NavRow(
                icon: Icons.logout,
                label: profile?.displayName ?? 'Sign out',
                expanded: expanded,
                keycap: true,
                trailing: expanded && profile != null
                    ? _RolePlate(manager: profile.isManager)
                    : null,
                // Showing the user's own name next to a logout icon reads
                // to some people as a profile/account button rather than
                // a sign-out one — confirm first so a curious tap doesn't
                // silently sign them out.
                onTap: () => _confirmSignOut(context, ref),
              ),
            ),
          ],
          const SizedBox(height: 10),
          // The nav sections scroll independently of the calendar/Settings
          // pinned below: enough favorited/archived/templated content would
          // otherwise overflow a short window, since this is the one
          // variable-height part of an otherwise fixed sidebar.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        _SidebarSearch(
                          expanded: expanded,
                          onOpenTask: onOpenTask,
                          onOpenProject: onFavoriteProjectTap,
                        ),
                        const SizedBox(height: 2),
                        _NavRow(
                          icon: Icons.dashboard_outlined,
                          label: 'Dashboard',
                          count: dashboardCount,
                          expanded: expanded,
                          active: currentScreen == AppScreen.dashboard,
                          accent: accent,
                          onTap: () => onScreenSelected(AppScreen.dashboard),
                        ),
                        if (profile?.isManager ?? false) ...[
                          const SizedBox(height: 2),
                          _NavRow(
                            icon: Icons.groups_outlined,
                            label: 'Team',
                            expanded: expanded,
                            active: currentScreen == AppScreen.team,
                            accent: accent,
                            onTap: () => onScreenSelected(AppScreen.team),
                          ),
                        ],
                        if (isAdmin) ...[
                          const SizedBox(height: 2),
                          _NavRow(
                            icon: Icons.admin_panel_settings_outlined,
                            label: 'Admin',
                            expanded: expanded,
                            active: currentScreen == AppScreen.admin,
                            accent: accent,
                            onTap: () => onScreenSelected(AppScreen.admin),
                          ),
                        ],
                        const SizedBox(height: 2),
                        _NavRow(
                          icon: Icons.calendar_month_outlined,
                          label: 'Calendar',
                          expanded: expanded,
                          active: currentScreen == AppScreen.calendar,
                          accent: accent,
                          onTap: () => onScreenSelected(AppScreen.calendar),
                        ),
                        const SizedBox(height: 2),
                        _NavRow(
                          icon: Icons.wb_sunny_outlined,
                          label: 'Today',
                          count: todayCount,
                          expanded: expanded,
                          active: currentScreen == AppScreen.today,
                          accent: accent,
                          onTap: () => onScreenSelected(AppScreen.today),
                        ),
                        const SizedBox(height: 2),
                        _NavRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'Upcoming',
                          count: upcomingCount,
                          expanded: expanded,
                          active: currentScreen == AppScreen.upcoming,
                          accent: accent,
                          onTap: () => onScreenSelected(AppScreen.upcoming),
                        ),
                      ],
                    ),
                  ),
                  if (expanded && favorites.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 16, 14, 8),
                      child: _SmallSectionLabel('Favorites'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        children: [
                          for (final project in favorites)
                            _NavRow(
                              icon: Icons.folder,
                              label: project.name,
                              expanded: expanded,
                              iconColor: accentPalette[project.colorIndex],
                              onTap: () => onFavoriteProjectTap(project),
                              onSecondaryTapDown: (details) =>
                                  _showFavoriteContextMenu(
                                    context,
                                    ref,
                                    project,
                                    details.globalPosition,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                    child: expanded
                        ? const _SmallSectionLabel('Library')
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        _NavRow(
                          icon: Icons.folder,
                          label: 'Projects',
                          count: activeProjects.length,
                          expanded: expanded,
                          active: currentScreen == AppScreen.projects,
                          accent: accent,
                          onTap: () => onScreenSelected(AppScreen.projects),
                        ),
                        const SizedBox(height: 2),
                        _NavRow(
                          icon: Icons.copy_all_outlined,
                          label: 'Templates',
                          count: templates.length,
                          expanded: expanded,
                          active: currentScreen == AppScreen.templates,
                          accent: accent,
                          onTap: () => onScreenSelected(AppScreen.templates),
                        ),
                        const SizedBox(height: 2),
                        _NavRow(
                          icon: Icons.archive_outlined,
                          label: 'Archived',
                          count: archivedCount,
                          expanded: expanded,
                          active: currentScreen == AppScreen.archived,
                          accent: accent,
                          onTap: () => onScreenSelected(AppScreen.archived),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            MiniCalendar(
              month: calendarMonth,
              selectedDay: selectedDay,
              onDayTap: onDaySelected,
            ),
            const SizedBox(height: 16),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _NavRow(
              icon: Icons.settings_outlined,
              label: 'Settings',
              expanded: expanded,
              active: currentScreen == AppScreen.settings,
              accent: accent,
              onTap: () => onScreenSelected(AppScreen.settings),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showBlurredDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(authControllerProvider).signOut();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  static Future<void> _showFavoriteContextMenu(
    BuildContext context,
    WidgetRef ref,
    Project project,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<_FavoriteAction>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem(
          value: _FavoriteAction.unfavorite,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.star_border),
            title: Text('Unfavorite'),
          ),
        ),
      ],
    );
    if (selected == _FavoriteAction.unfavorite) {
      ref.read(projectsProvider.notifier).toggleFavorite(project.id);
    }
  }
}

enum _FavoriteAction { unfavorite }

class _Header extends StatelessWidget {
  const _Header({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    if (!expanded) {
      return Column(
        children: [
          const AppLogo(size: 24),
          const SizedBox(height: 12),
          IconButton(
            icon: Icon(
              Icons.view_sidebar_outlined,
              size: 17,
              color: tokens.neutral400,
            ),
            onPressed: onToggle,
            visualDensity: VisualDensity.compact,
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const AppLogo(size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'ProCheck',
              style: TextStyle(
                fontFamily: kPanelFont,
                fontWeight: FontWeight.w600,
                fontSize: 19,
                letterSpacing: 1.2,
                color: tokens.text,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.view_sidebar_outlined,
              size: 17,
              color: tokens.neutral400,
            ),
            onPressed: onToggle,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// The sidebar's inline search: a type-ahead field that matches tasks by
/// title or notes (same matching PR #35's dedicated Search page used)
/// without ever leaving the current screen. Collapsed (icon-only) rail
/// shows a plain nav row instead — tapping it expands the sidebar so the
/// field can be used.
class _SidebarSearch extends ConsumerWidget {
  const _SidebarSearch({
    required this.expanded,
    required this.onOpenTask,
    required this.onOpenProject,
  });

  final bool expanded;
  final void Function(String? projectId, String taskId) onOpenTask;

  /// Opens a project picked from the inline search field — same "jump to
  /// this project" behavior as tapping it under Favorites.
  final ValueChanged<Project> onOpenProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.nocturne;

    if (!expanded) {
      return _NavRow(
        icon: Icons.search,
        label: 'Search',
        expanded: expanded,
        onTap: () =>
            ref.read(settingsProvider.notifier).setSidebarExpanded(true),
      );
    }

    final tasks = ref.watch(tasksProvider);
    final projects = ref.watch(projectsProvider);
    final activeProjects = projects.where((p) => !p.archived).toList();
    final projectNames = buildProjectNameLookup(projects);

    return Autocomplete<_SearchResult>(
      optionsBuilder: (TextEditingValue value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return const Iterable<_SearchResult>.empty();
        final matchingProjects = activeProjects
            .where((p) => p.name.toLowerCase().contains(query))
            .map(_ProjectResult.new);
        final matchingTasks = tasks
            .where(
              (t) =>
                  t.title.toLowerCase().contains(query) ||
                  (t.notes?.toLowerCase().contains(query) ?? false),
            )
            .map(_TaskResult.new);
        // Projects first — there are usually far fewer of them, and
        // jumping to a project is the coarser, more likely-intended match
        // for a short query (e.g. the project's own name).
        return [...matchingProjects, ...matchingTasks];
      },
      displayStringForOption: (result) => switch (result) {
        _ProjectResult(:final project) => project.name,
        _TaskResult(:final task) => task.title,
      },
      onSelected: (result) => switch (result) {
        _ProjectResult(:final project) => onOpenProject(project),
        _TaskResult(:final task) => onOpenTask(task.projectId, task.id),
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: TextStyle(fontSize: 14, color: tokens.text),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search',
            hintStyle: TextStyle(fontSize: 14, color: tokens.neutral500),
            prefixIcon: Icon(Icons.search, size: 17, color: tokens.neutral400),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final results = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            color: tokens.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NocturneRadius.md),
              side: BorderSide(color: tokens.edge),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 212),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final result = results[index];
                  return switch (result) {
                    _ProjectResult(:final project) => ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.folder,
                        size: 16,
                        color: accentPalette[project.colorIndex],
                      ),
                      title: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: tokens.text),
                      ),
                      onTap: () => onSelected(result),
                    ),
                    _TaskResult(:final task) => ListTile(
                      dense: true,
                      title: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: tokens.text),
                      ),
                      subtitle: Text(
                        projectNameFor(projectNames, task.projectId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.neutral500,
                        ),
                      ),
                      onTap: () => onSelected(result),
                    ),
                  };
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One matched item in the sidebar search — a project (matched by name) or
/// a task (matched by title/notes), so a single [Autocomplete] can offer
/// both kinds of result together.
sealed class _SearchResult {}

class _ProjectResult extends _SearchResult {
  _ProjectResult(this.project);
  final Project project;
}

class _TaskResult extends _SearchResult {
  _TaskResult(this.task);
  final Task task;
}

class _SmallSectionLabel extends StatelessWidget {
  const _SmallSectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => StampLabel(text, size: 12);
}

/// Engraved MEMBER / MANAGER plate. A manager's carries a double rule so the
/// distinction doesn't rest on text alone.
class _RolePlate extends StatelessWidget {
  const _RolePlate({required this.manager});
  final bool manager;

  @override
  Widget build(BuildContext context) {
    final edge = context.nocturne.edge;
    Widget plate = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: edge),
        borderRadius: BorderRadius.circular(NocturneRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: StampLabel(manager ? 'Manager' : 'Member', size: 10.5),
      ),
    );
    if (manager) {
      plate = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: edge),
          borderRadius: BorderRadius.circular(NocturneRadius.sm + 1),
        ),
        child: Padding(padding: const EdgeInsets.all(1.5), child: plate),
      );
    }
    return plate;
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.expanded,
    this.count,
    this.active = false,
    this.accent,
    this.iconColor,
    this.keycap = false,
    this.trailing,
    required this.onTap,
    this.onSecondaryTapDown,
  });

  final IconData icon;
  final String label;
  final bool expanded;
  final int? count;
  final bool active;
  final Color? accent;
  final Color? iconColor;

  /// Draws the row as a raised keycap (the sign-out row).
  final bool keycap;
  final Widget? trailing;
  final VoidCallback onTap;
  final void Function(TapDownDetails details)? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final lit = active && accent != null;
    final radius = BorderRadius.circular(NocturneRadius.md);
    // Active = a key pressed into the rail and lit with the accent.
    final decoration = lit
        ? panelDecoration(
            context,
            depth: PanelDepth.recessed,
            fill: Color.lerp(tokens.well, accent, tokens.isDark ? 0.22 : 0.3),
          ).copyWith(border: Border.all(color: accent!.withValues(alpha: 0.7)))
        : keycap
        ? panelDecoration(context)
        : null;

    return GestureDetector(
      onSecondaryTapDown: onSecondaryTapDown,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: DecoratedBox(
          decoration: decoration ?? const BoxDecoration(),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              hoverColor: context.nocturneHoverColor,
              splashColor: context.nocturneSplashColor,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                child: Row(
                  mainAxisAlignment: expanded
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    if (lit && expanded) ...[
                      IndicatorLamp(on: true, color: accent!, size: 7),
                      const SizedBox(width: 7),
                    ],
                    Icon(
                      icon,
                      size: 18,
                      color: iconColor ?? (lit ? accent : tokens.neutral300),
                    ),
                    if (expanded) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: lit ? FontWeight.w500 : null,
                            color: lit ? tokens.text : tokens.neutral200,
                          ),
                        ),
                      ),
                      ?trailing,
                      if (count != null && count! > 0)
                        DecoratedBox(
                          decoration: panelDecoration(
                            context,
                            depth: PanelDepth.recessed,
                            radius: NocturneRadius.sm,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontFamily: kPanelFont,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                letterSpacing: 0.6,
                                color: tokens.text,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
