import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_config.dart';
import '../models/project.dart';
import '../providers/auth_provider.dart';
import '../providers/departments_provider.dart';
import '../providers/projects_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tasks_provider.dart';
import '../screens/app_screen.dart';
import '../theme/nocturne_theme.dart';

const _maxPerGroup = 8;

/// Opens the Ctrl/Cmd+K command palette. The callbacks are the shell's own
/// existing navigation/creation functions, so every result behaves exactly
/// like its sidebar or shortcut equivalent.
Future<void> showCommandPalette(
  BuildContext context, {
  required ValueChanged<AppScreen> onScreenSelected,
  required ValueChanged<Project> onOpenProject,
  required void Function(String? projectId, String taskId) onOpenTask,
  required VoidCallback onNewTask,
  required VoidCallback onNewProject,
}) {
  final reduceMotion = ProviderScope.containerOf(
    context,
  ).read(settingsProvider).reduceMotion;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 120),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (context, _, _) => SafeArea(
      child: LayoutBuilder(
        builder: (context, box) => Align(
          alignment: const Alignment(0, -0.5),
          child: SizedBox(
            width: (box.maxWidth - 32).clamp(0.0, 560.0),
            child: _CommandPalette(
              onScreenSelected: onScreenSelected,
              onOpenProject: onOpenProject,
              onOpenTask: onOpenTask,
              onNewTask: onNewTask,
              onNewProject: onNewProject,
            ),
          ),
        ),
      ),
    ),
  );
}

class _Entry {
  _Entry(this.group, this.icon, this.label, this.run, {this.subtitle});
  final String group;
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback run;
}

class _CommandPalette extends ConsumerStatefulWidget {
  const _CommandPalette({
    required this.onScreenSelected,
    required this.onOpenProject,
    required this.onOpenTask,
    required this.onNewTask,
    required this.onNewProject,
  });

  final ValueChanged<AppScreen> onScreenSelected;
  final ValueChanged<Project> onOpenProject;
  final void Function(String? projectId, String taskId) onOpenTask;
  final VoidCallback onNewTask;
  final VoidCallback onNewProject;

  @override
  ConsumerState<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<_CommandPalette> {
  final _controller = TextEditingController();
  final _selectedKey = GlobalKey();
  int _selected = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_Entry> _entries() {
    final query = _controller.text.trim().toLowerCase();
    bool matches(String s) => query.isEmpty || s.toLowerCase().contains(query);

    // Same gating as AppSidebar.
    final signedIn = isSupabaseConfigured && supabase.auth.currentUser != null;
    final isManager =
        signedIn && (ref.watch(currentProfileProvider).valueOrNull?.isManager ?? false);
    final isAdmin =
        signedIn && (ref.watch(isAdminProvider).valueOrNull ?? false);

    final screens = <(String, IconData, AppScreen)>[
      ('Dashboard', Icons.dashboard_outlined, AppScreen.dashboard),
      ('Calendar', Icons.calendar_month_outlined, AppScreen.calendar),
      ('Today', Icons.wb_sunny_outlined, AppScreen.today),
      ('Upcoming', Icons.calendar_today_outlined, AppScreen.upcoming),
      ('Projects', Icons.folder_outlined, AppScreen.projects),
      ('Templates', Icons.copy_all_outlined, AppScreen.templates),
      ('Archived', Icons.archive_outlined, AppScreen.archived),
      ('Settings', Icons.settings_outlined, AppScreen.settings),
      if (isManager) ('Team', Icons.groups_outlined, AppScreen.team),
      if (isAdmin)
        ('Admin', Icons.admin_panel_settings_outlined, AppScreen.admin),
    ];
    final dark = Theme.of(context).brightness == Brightness.dark;

    final goTo = [
      for (final (label, icon, screen) in screens)
        if (matches(label))
          _Entry('Go to', icon, label, () => widget.onScreenSelected(screen)),
    ].take(_maxPerGroup);

    final projects = ref.watch(projectsProvider).where((p) => !p.archived);
    final projectEntries = query.isEmpty
        ? const <_Entry>[]
        : [
            for (final p in projects)
              if (matches(p.name))
                _Entry(
                  'Projects',
                  Icons.folder,
                  p.name,
                  () => widget.onOpenProject(p),
                ),
          ].take(_maxPerGroup);

    final names = {for (final p in ref.watch(projectsProvider)) p.id: p.name};
    final taskEntries = query.isEmpty
        ? const <_Entry>[]
        : [
            for (final t in ref.watch(tasksProvider))
              if (t.title.toLowerCase().contains(query) ||
                  (t.notes?.toLowerCase().contains(query) ?? false))
                _Entry(
                  'Tasks',
                  Icons.check_circle_outline,
                  t.title,
                  () => widget.onOpenTask(t.projectId, t.id),
                  subtitle: names[t.projectId],
                ),
          ].take(_maxPerGroup);

    final actions = <(String, IconData, VoidCallback)>[
      ('New task', Icons.add_task, widget.onNewTask),
      ('New project', Icons.create_new_folder_outlined, widget.onNewProject),
      (
        dark ? 'Switch to light theme' : 'Switch to dark theme',
        dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        () => ref
            .read(settingsProvider.notifier)
            .setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
      ),
    ];
    final actionEntries = [
      for (final (label, icon, run) in actions)
        if (matches(label)) _Entry('Actions', icon, label, run),
    ];

    return [...goTo, ...projectEntries, ...taskEntries, ...actionEntries];
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + delta) % count);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx);
    });
  }

  void _run(_Entry entry) {
    Navigator.of(context).pop();
    entry.run();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final accent = context.nocturneAccent;
    final entries = _entries();
    final selected = entries.isEmpty ? 0 : _selected.clamp(0, entries.length - 1);

    final rows = <Widget>[];
    String? group;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.group != group) {
        group = e.group;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              e.group.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: tokens.neutral500,
              ),
            ),
          ),
        );
      }
      final isSel = i == selected;
      rows.add(
        InkWell(
          key: isSel ? _selectedKey : null,
          onTap: () => _run(e),
          child: Container(
            color: isSel
                ? accent.withValues(alpha: tokens.isDark ? 0.16 : 0.10)
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(e.icon, size: 17, color: isSel ? accent : tokens.neutral400),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: tokens.text),
                  ),
                ),
                if (e.subtitle != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      e.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: tokens.neutral500),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _move(1, entries.length),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _move(entries.length - 1, entries.length),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Material(
        color: tokens.surface,
        elevation: 12,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NocturneRadius.lg),
          side: BorderSide(color: tokens.edge),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(fontSize: 14, color: tokens.text),
              onChanged: (_) => setState(() => _selected = 0),
              onSubmitted: (_) {
                if (entries.isNotEmpty) _run(entries[selected]);
              },
              decoration: InputDecoration(
                hintText: 'Type a command or search',
                hintStyle: TextStyle(fontSize: 14, color: tokens.neutral500),
                prefixIcon: Icon(Icons.search, size: 18, color: tokens.neutral400),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            Divider(height: 1, color: tokens.edge),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: entries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No matches',
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.neutral500,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(children: rows),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
