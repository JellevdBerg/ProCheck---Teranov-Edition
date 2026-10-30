import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../data/app_messenger.dart';
import '../../data/hive_setup.dart';
import '../../models/department.dart';
import '../../models/outbox_entry.dart';
import '../../models/project.dart';
import '../../models/task.dart';
import '../../providers/auth_provider.dart';
import '../../providers/departments_provider.dart';
import '../../providers/projects_provider.dart';
import '../../providers/roles_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_templates_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../screens/app_screen.dart';
import '../../screens/dashboard_screen.dart';
import '../../screens/login_screen.dart';
import '../../theme/nocturne_theme.dart';
import '../app_logo.dart';
import '../blurred_dialog.dart';
import '../motion_widgets.dart';
import '../panel/panel.dart';
import '../people_plates.dart';
import '../project_name_lookup.dart';
import '../sync_status_indicator.dart';
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
    this.forcedExpanded,
    this.onToggle,
  });

  /// When set, overrides [AppSettings.sidebarExpanded] for this build — the
  /// shell forces the icon rail at compact widths and a full-width drawer
  /// when the user opens it there, without touching the saved preference.
  final bool? forcedExpanded;

  /// Replaces the default "toggle the saved preference" action of the
  /// collapse button and the rail's search key (the shell opens/closes its
  /// drawer instead at compact widths).
  final VoidCallback? onToggle;

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
    final expanded = forcedExpanded ?? settings.sidebarExpanded;
    void toggle() => onToggle != null
        ? onToggle!()
        : ref.read(settingsProvider.notifier).setSidebarExpanded(!expanded);
    final signedIn = ref.watch(signedInProvider);
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

    final departments = signedIn && profile?.departmentId != null
        ? ref.watch(departmentsProvider).valueOrNull
        : null;
    final department = departments
        ?.where((d) => d.id == profile?.departmentId)
        .firstOrNull;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: expanded ? 232 : 56,
      decoration: BoxDecoration(
        color: tokens.raised,
        border: Border(right: BorderSide(color: tokens.edge)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // On a short window the mini calendar would squeeze the nav
          // list to nothing, so it moves to the end of the scrolling area
          // (still reachable) instead of being pinned below it.
          final calendarInScroll = box.maxHeight < 720;
          final calendar = MiniCalendar(
            month: calendarMonth,
            selectedDay: selectedDay,
            onDayTap: onDaySelected,
          );
          return Column(
        children: [
          const SizedBox(height: 12),
          _Header(expanded: expanded, onToggle: toggle),
          if (signedIn) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              // Showing the user's own name next to a logout icon reads
              // to some people as a profile/account button rather than
              // a sign-out one — confirm first so a curious tap doesn't
              // silently sign them out.
              child: expanded && profile != null
                  ? _UserCard(
                      name: profile.displayName,
                      isManager: profile.isManager,
                      title: ref
                          .watch(departmentRolesProvider)
                          .valueOrNull
                          ?.where((r) => r.id == profile.customRoleId)
                          .firstOrNull
                          ?.name,
                      department: department,
                      onTap: () => _confirmSignOut(context, ref),
                    )
                  : _NavRow(
                      icon: Icons.logout,
                      label: profile?.displayName ?? 'Sign out',
                      expanded: expanded,
                      onTap: () => _confirmSignOut(context, ref),
                    ),
            ),
            if (expanded) ...[
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SyncStatusIndicator(),
                ),
              ),
            ],
          ],
          const SizedBox(height: 8),
          // The nav sections scroll independently of the calendar/Settings
          // pinned below: enough favorited/archived/templated content would
          // otherwise overflow a short window, since this is the one
          // variable-height part of an otherwise fixed sidebar.
          Expanded(
            child: SingleChildScrollView(
              child: SlidingHighlight(
                activeId: currentScreen,
                color: accent.withValues(alpha: tokens.isDark ? 0.16 : 0.10),
                radius: BorderRadius.circular(NocturneRadius.md),
                child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        _SidebarSearch(
                          expanded: expanded,
                          onOpenTask: onOpenTask,
                          onOpenProject: onFavoriteProjectTap,
                          onExpand: onToggle,
                        ),
                        const SizedBox(height: 4),
                        _NavRow(
                          icon: Icons.dashboard_outlined,
                          label: 'Dashboard',
                          count: dashboardCount,
                          expanded: expanded,
                          active: currentScreen == AppScreen.dashboard,
                          accent: accent,
                          onTap: () => onScreenSelected(AppScreen.dashboard),
                        ),
                        if (signedIn && ref.watch(permissionsProvider).viewTeam) ...[
                          const SizedBox(height: 1),
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
                          const SizedBox(height: 1),
                          _NavRow(
                            icon: Icons.admin_panel_settings_outlined,
                            label: 'Admin',
                            expanded: expanded,
                            active: currentScreen == AppScreen.admin,
                            accent: accent,
                            onTap: () => onScreenSelected(AppScreen.admin),
                          ),
                          const SizedBox(height: 1),
                          _NavRow(
                            icon: Icons.account_tree_outlined,
                            label: 'Organization',
                            expanded: expanded,
                            active: currentScreen == AppScreen.orgChart,
                            accent: accent,
                            onTap: () => onScreenSelected(AppScreen.orgChart),
                          ),
                        ],
                        const SizedBox(height: 1),
                        _NavRow(
                          icon: Icons.calendar_month_outlined,
                          label: 'Calendar',
                          expanded: expanded,
                          active: currentScreen == AppScreen.calendar,
                          accent: accent,
                          onTap: () => onScreenSelected(AppScreen.calendar),
                        ),
                        const SizedBox(height: 1),
                        _NavRow(
                          icon: Icons.wb_sunny_outlined,
                          label: 'Today',
                          count: todayCount,
                          expanded: expanded,
                          active: currentScreen == AppScreen.today,
                          accent: accent,
                          onTap: () => onScreenSelected(AppScreen.today),
                        ),
                        const SizedBox(height: 1),
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
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                      child: _SmallSectionLabel('Favorites'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          for (final project in favorites)
                            _NavRow(
                              icon: Icons.folder,
                              label: project.name,
                              expanded: expanded,
                              iconColor: context.projectColor(project.colorIndex),
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: expanded
                        ? const _SmallSectionLabel('Library')
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
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
                        const SizedBox(height: 1),
                        _NavRow(
                          icon: Icons.copy_all_outlined,
                          label: 'Templates',
                          count: templates.length,
                          expanded: expanded,
                          active: currentScreen == AppScreen.templates,
                          accent: accent,
                          onTap: () => onScreenSelected(AppScreen.templates),
                        ),
                        const SizedBox(height: 1),
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
                  if (expanded && calendarInScroll) ...[
                    const SizedBox(height: 8),
                    calendar,
                  ],
                ],
              ),
              ),
            ),
          ),
          if (expanded && !calendarInScroll) ...[
            calendar,
            const SizedBox(height: 8),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: expanded
                ? Row(
                    children: [
                      Expanded(
                        child: _NavRow(
                          icon: Icons.settings_outlined,
                          label: 'Settings',
                          expanded: expanded,
                          active: currentScreen == AppScreen.settings,
                          accent: accent,
                          onTap: () => onScreenSelected(AppScreen.settings),
                        ),
                      ),
                      const _ThemeToggle(),
                    ],
                  )
                : Column(
                    children: [
                      _NavRow(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        expanded: expanded,
                        active: currentScreen == AppScreen.settings,
                        accent: accent,
                        onTap: () => onScreenSelected(AppScreen.settings),
                      ),
                      const _ThemeToggle(),
                    ],
                  ),
          ),
        ],
          );
        },
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
    if (!(confirmed ?? false)) return;

    final pending = Hive.box<OutboxEntry>(outboxBoxName).length;
    if (pending > 0) {
      if (!context.mounted) return;
      final action = await showBlurredDialog<_PendingSignOutAction>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            '$pending change${pending == 1 ? '' : 's'} not shared yet',
          ),
          content: const Text(
            'These haven\'t reached your team yet. Sync them now, discard '
            'them and sign out anyway, or stay signed in.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_PendingSignOutAction.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_PendingSignOutAction.discard),
              child: const Text('Discard and sign out'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_PendingSignOutAction.sync),
              child: const Text('Sync now'),
            ),
          ],
        ),
      );
      switch (action) {
        case null:
        case _PendingSignOutAction.cancel:
          return;
        case _PendingSignOutAction.discard:
          unawaited(Hive.box<OutboxEntry>(outboxBoxName).clear());
        case _PendingSignOutAction.sync:
          await Future.wait([
            ref.read(tasksProvider.notifier).replayOutbox(),
            ref.read(projectsProvider.notifier).replayOutbox(),
          ]);
          final stillPending = Hive.box<OutboxEntry>(outboxBoxName).length;
          if (stillPending > 0) {
            showSyncFailureToast(
              '$stillPending change${stillPending == 1 ? '' : 's'} still '
              'couldn\'t sync — staying signed in.',
            );
            return;
          }
      }
    }

    await ref.read(authControllerProvider).signOut();
    // Hive boxes live on this device, not per-account — without this,
    // whoever signs in next on the same machine would see the previous
    // person's tasks/projects until their own pull replaces them.
    ref.read(tasksProvider.notifier).clearAll();
    ref.read(projectsProvider.notifier).clearAll();
    unawaited(Hive.box<OutboxEntry>(outboxBoxName).clear());
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
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

enum _PendingSignOutAction { cancel, discard, sync }

class _Header extends StatelessWidget {
  const _Header({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final toggle = IconButton(
      tooltip: expanded ? 'Collapse sidebar' : 'Expand sidebar',
      icon: Icon(Icons.view_sidebar_outlined, size: 18, color: tokens.neutral400),
      onPressed: onToggle,
      visualDensity: VisualDensity.compact,
    );
    if (!expanded) {
      return Column(
        children: [
          const AppLogo(size: 24),
          const SizedBox(height: 8),
          toggle,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Row(
        children: [
          const AppLogo(size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'ProCheck',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          toggle,
        ],
      ),
    );
  }
}

/// Signed-in identity at the top of the sidebar: initials, name, department
/// and role cues. Tapping it signs out (after the existing confirmation).
class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.name,
    required this.isManager,
    this.title,
    required this.department,
    required this.onTap,
  });

  final String name;
  final bool isManager;
  final String? title;
  final Department? department;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final radius = BorderRadius.circular(NocturneRadius.md);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Tooltip(
      message: 'Sign out',
      child: Material(
        color: tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: tokens.edge),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: tokens.neutral900,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                AvatarWell(initial: initial, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 16 / 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Department on its own line so a long name ellipsizes
                      // instead of pushing the role chip around.
                      if (department != null) ...[
                        DepartmentPlate(
                          name: department!.name,
                          isOperator: department!.isOperator,
                          isIt: department!.isIt,
                        ),
                        const SizedBox(height: 3),
                      ],
                      RolePlate(isManager: isManager, title: title),
                    ],
                  ),
                ),
                Icon(Icons.logout, size: 16, color: tokens.neutral500),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick light/dark switch (the full System / Light / Dark choice stays in
/// Settings → Appearance). Flips from whatever is showing now to the other.
class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
      icon: Icon(
        dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 18,
        color: context.nocturne.neutral400,
      ),
      onPressed: () => ref
          .read(settingsProvider.notifier)
          .setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
      visualDensity: VisualDensity.compact,
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
    this.onExpand,
  });

  final bool expanded;

  /// What the collapsed rail's search key does; defaults to expanding the
  /// saved sidebar preference.
  final VoidCallback? onExpand;
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
        onTap: onExpand ??
            () => ref.read(settingsProvider.notifier).setSidebarExpanded(true),
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
          style: TextStyle(fontSize: 13, color: tokens.text),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search',
            hintStyle: TextStyle(fontSize: 13, color: tokens.neutral500),
            prefixIcon: Icon(Icons.search, size: 17, color: tokens.neutral400),
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
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
                        color: context.projectColor(project.colorIndex),
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
  Widget build(BuildContext context) => StampLabel(text);
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
  final VoidCallback onTap;
  final void Function(TapDownDetails details)? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final lit = active && accent != null;
    final radius = BorderRadius.circular(NocturneRadius.md);

    final row = Row(
      mainAxisAlignment: expanded
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 18,
          color: iconColor ?? (lit ? accent : tokens.neutral400),
        ),
        if (expanded) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 20 / 13,
                fontWeight: lit ? FontWeight.w600 : FontWeight.w400,
                color: lit ? accent : tokens.neutral200,
              ),
            ),
          ),
          if (count != null && count! > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: lit ? accent : tokens.neutral500,
                ),
              ),
            ),
        ],
      ],
    );

    // Inside a SlidingHighlight the active row's fill is the shared highlight.
    final highlightKey = lit ? SlidingHighlight.keyOf(context) : null;
    final tile = GestureDetector(
      onSecondaryTapDown: onSecondaryTapDown,
      child: Tooltip(
        message: expanded ? '' : label,
        child: Material(
          color: lit && highlightKey == null
              ? accent!.withValues(alpha: tokens.isDark ? 0.16 : 0.10)
              : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            hoverColor: tokens.neutral800.withValues(alpha: 0.6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                child: row,
              ),
            ),
          ),
        ),
      ),
    );
    final pressable = PressScale(child: tile);
    return highlightKey == null
        ? pressable
        : KeyedSubtree(key: highlightKey, child: pressable);
  }
}
