import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_config.dart';
import '../models/department.dart';
import '../models/department_role.dart';
import '../models/profile.dart';
import '../models/task.dart';
import '../providers/admin_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/department_members_provider.dart';
import '../providers/departments_provider.dart';
import '../providers/roles_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/blurred_dialog.dart';
import '../widgets/motion_widgets.dart';
import '../widgets/nocturne/nocturne_widgets.dart';
import '../widgets/panel/panel.dart';
import '../widgets/people_plates.dart';
import '../widgets/text_prompt_dialog.dart';

/// Minutes in a standard working week (40 h) and day (8 h): the capacity
/// occupancy is measured against. Month capacity = 8 h × the month's weekdays.
const _weekMinutes = 40 * 60;
const _dayMinutes = 8 * 60;

enum _Window { week, month }

/// The manager's Team dashboard: every member next to their workload
/// ("occupancy"), plus the department's job titles. Visibility is governed
/// entirely by the `profiles`/`tasks` RLS policies — this renders whatever
/// [departmentMembersProvider]/[tasksProvider] already surface.
class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
  _Window _window = _Window.week;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final membersAsync = ref.watch(departmentMembersProvider);
    final tasks = ref.watch(tasksProvider);
    final perms = ref.watch(permissionsProvider);
    final me = ref.watch(currentProfileProvider).valueOrNull;
    final roles = ref.watch(departmentRolesProvider).valueOrNull ?? const [];
    final departments = ref.watch(departmentsProvider).valueOrNull ?? const [];

    return membersAsync.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(NocturneSpace.s6),
        children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: NocturneSpace.s3),
              child: Row(
                children: [
                  const Skeleton(width: 28, height: 28),
                  const SizedBox(width: NocturneSpace.s3),
                  Skeleton(width: 120.0 + 24 * (i % 3)),
                  const Spacer(),
                  const Skeleton(width: 64),
                ],
              ),
            ),
        ],
      ),
      error: (error, _) => Center(
        child: PanelNotice('Could not load team: $error', isError: true),
      ),
      data: (members) {
        final now = DateTime.now();
        final range = _rangeFor(_window, now);
        final rows = [
          for (final m in members) _occupancyFor(m, tasks, range),
        ]..sort((a, b) => b.load.compareTo(a.load));
        final multiDept = members.map((m) => m.departmentId).toSet().length > 1;
        final canAdd = perms.isManager && !perms.isAdmin && me?.departmentId != null;

        return LayoutBuilder(
          builder: (context, constraints) {
            final gutter = constraints.maxWidth < NocturneBreakpoints.compact
                ? NocturneSpace.s4
                : NocturneSpace.s6;
            return ListView(
              padding: EdgeInsets.all(gutter),
              children: [
                Wrap(
                  spacing: NocturneSpace.s3,
                  runSpacing: NocturneSpace.s2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Team', style: Theme.of(context).textTheme.displaySmall),
                        const SizedBox(height: NocturneSpace.s1),
                        Text(
                          _window == _Window.week
                              ? 'Open work due this week (and overdue) against a 40 h week.'
                              : 'Open work due this month (and overdue) against ${range.capacity ~/ 60} h '
                                    '(8 h × ${range.workdays} weekdays).',
                          style: TextStyle(color: tokens.neutral500),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NocturneSegmented<_Window>(
                          options: _Window.values,
                          value: _window,
                          labelBuilder: (w) => w == _Window.week ? 'Week' : 'Month',
                          onChanged: (w) => setState(() => _window = w),
                        ),
                        if (canAdd) ...[
                          const SizedBox(width: NocturneSpace.s2),
                          NocturneButton(
                            label: 'Add member',
                            icon: Icons.person_add_alt_1_outlined,
                            variant: NocturneButtonVariant.primary,
                            onPressed: () => _addMember(context, me!.departmentId!),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: NocturneSpace.s4),
                if (rows.isEmpty)
                  const PanelNotice('No team members yet.')
                else
                  DecoratedBox(
                    decoration: panelDecoration(context),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(NocturneRadius.lg),
                      child: Column(
                        children: [
                          for (var i = 0; i < rows.length; i++) ...[
                            if (i > 0) const Divider(),
                            StaggerIn(
                              key: ValueKey(rows[i].member.id),
                              index: i,
                              child: _TeamMemberRow(
                              row: rows[i],
                              roles: roles,
                              department: multiDept
                                  ? departments
                                        .where((d) => d.id == rows[i].member.departmentId)
                                        .firstOrNull
                                  : null,
                              me: me,
                              perms: perms,
                              onChanged: () => ref.invalidate(departmentMembersProvider),
                            ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (perms.isManager || perms.isAdmin) ...[
                  const SizedBox(height: NocturneSpace.s6),
                  _RolesCard(
                    roles: roles,
                    departments: departments,
                    myDepartmentId: me?.departmentId,
                    admin: perms.isAdmin,
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addMember(BuildContext context, String departmentId) async {
    final name = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    String? error;
    final ok = await showBlurredDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add member'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: NocturneSpace.s3),
                TextField(
                  controller: username,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: NocturneSpace.s3),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password (min. 6)'),
                ),
                if (error != null) ...[
                  const SizedBox(height: NocturneSpace.s3),
                  Text(error!, style: TextStyle(color: context.nocturne.danger)),
                ],
              ],
            ),
          ),
          actions: [
            NocturneButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop(false)),
            NocturneButton(
              label: 'Create',
              variant: NocturneButtonVariant.primary,
              onPressed: () async {
                try {
                  await ref.read(adminControllerProvider).createAccount(
                    username: username.text,
                    password: password.text,
                    displayName: name.text,
                    role: 'member',
                    departmentId: departmentId,
                  );
                  if (context.mounted) Navigator.of(context).pop(true);
                } on AuthException catch (e) {
                  setLocal(() => error = e.message);
                }
              },
            ),
          ],
        ),
      ),
    );
    if (ok ?? false) ref.invalidate(departmentMembersProvider);
  }
}

class _Range {
  _Range(this.end, this.capacity, this.workdays);
  final DateTime end;
  final int capacity;
  final int workdays;
}

_Range _rangeFor(_Window window, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (window == _Window.week) {
    final end = today.add(Duration(days: 7 - today.weekday + 1)); // exclusive Monday
    return _Range(end, _weekMinutes, 5);
  }
  final end = DateTime(now.year, now.month + 1, 1);
  var workdays = 0;
  for (var d = DateTime(now.year, now.month, 1); d.isBefore(end); d = d.add(const Duration(days: 1))) {
    if (d.weekday <= DateTime.friday) workdays++;
  }
  return _Range(end, workdays * _dayMinutes, workdays);
}

class _MemberOccupancy {
  _MemberOccupancy({
    required this.member,
    required this.openTaskCount,
    required this.overdueCount,
    required this.loadMinutes,
    required this.unestimated,
    required this.capacity,
  });

  final Profile member;
  final int openTaskCount;
  final int overdueCount;
  final int loadMinutes;
  final int unestimated;
  final int capacity;

  double get load => capacity == 0 ? 0 : loadMinutes / capacity;
}

_MemberOccupancy _occupancyFor(Profile member, List<Task> tasks, _Range range) {
  final now = DateTime.now();
  final open = tasks.where((t) => !t.isChecked && t.assigneeId == member.id).toList();
  var minutes = 0;
  var unestimated = 0;
  var overdue = 0;
  for (final t in open) {
    final due = t.dueDateEnd ?? t.dueDate;
    if (due != null && due.isBefore(now)) overdue++;
    if (due == null || !due.isBefore(range.end)) continue;
    if (t.estimatedMinutes == null) {
      unestimated++;
    } else {
      minutes += t.estimatedMinutes!;
    }
  }
  return _MemberOccupancy(
    member: member,
    openTaskCount: open.length,
    overdueCount: overdue,
    loadMinutes: minutes,
    unestimated: unestimated,
    capacity: range.capacity,
  );
}

String _hm(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return h > 0 ? (m == 0 ? '${h}h' : '${h}h ${m}m') : '${m}m';
}

class _TeamMemberRow extends ConsumerWidget {
  const _TeamMemberRow({
    required this.row,
    required this.roles,
    required this.department,
    required this.me,
    required this.perms,
    required this.onChanged,
  });

  final _MemberOccupancy row;
  final List<DepartmentRole> roles;
  final Department? department;
  final Profile? me;
  final Permissions perms;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.nocturne;
    final member = row.member;
    final title = roles.where((r) => r.id == member.customRoleId).firstOrNull?.name;
    final pct = (row.load * 100).round();
    final gaugeColor = row.load > 1
        ? tokens.danger
        : row.load > 0.85
        ? tokens.warn
        : null;

    final who = Row(
      children: [
        AvatarWell(
          initial: member.displayName.isEmpty ? '?' : member.displayName[0].toUpperCase(),
        ),
        const SizedBox(width: NocturneSpace.s3),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: NocturneSpace.s2,
            runSpacing: NocturneSpace.s1,
            children: [
              Text(
                member.id == me?.id ? '${member.displayName} (you)' : member.displayName,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              RolePlate(isManager: member.isManager, title: title),
              // ignore: use_null_aware_elements
              if (department != null)
                DepartmentPlate(
                  name: department!.name,
                  isOperator: department!.isOperator,
                  isIt: department!.isIt,
                ),
            ],
          ),
        ),
      ],
    );
    final load = Text(
      '$pct%  ·  ${_hm(row.loadMinutes)} of ${_hm(row.capacity)}',
      style: TextStyle(fontSize: 13, color: gaugeColor ?? tokens.neutral300,
          fontWeight: row.load > 1 ? FontWeight.w600 : FontWeight.w400),
    );
    final counts = Text(
      '${row.openTaskCount} open'
      '${row.overdueCount > 0 ? ' · ${row.overdueCount} overdue' : ''}'
      '${row.unestimated > 0 ? ' · ${row.unestimated} unestimated' : ''}',
      style: TextStyle(fontSize: 12, color: row.overdueCount > 0 ? tokens.danger : tokens.neutral500),
    );
    final gauge = GaugeBar(value: row.load, color: gaugeColor);
    final actions = _MemberActions(
      member: member,
      roles: roles,
      me: me,
      perms: perms,
      onChanged: onChanged,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NocturneSpace.s3,
        vertical: NocturneSpace.s2,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [Expanded(child: who), actions]),
                const SizedBox(height: NocturneSpace.s2),
                gauge,
                const SizedBox(height: NocturneSpace.s1),
                Wrap(
                  spacing: NocturneSpace.s3,
                  children: [load, counts],
                ),
              ],
            );
          }
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              children: [
                Expanded(flex: 3, child: who),
                const SizedBox(width: NocturneSpace.s4),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      gauge,
                      const SizedBox(height: NocturneSpace.s1),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [load, counts],
                      ),
                    ],
                  ),
                ),
                actions,
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The "⋯" menu on a person: give a job title, promote/demote (IT/Operator),
/// remove. Which entries show is a convenience; the database decides.
class _MemberActions extends ConsumerWidget {
  const _MemberActions({
    required this.member,
    required this.roles,
    required this.me,
    required this.perms,
    required this.onChanged,
  });

  final Profile member;
  final List<DepartmentRole> roles;
  final Profile? me;
  final Permissions perms;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (member.id == me?.id || !isSupabaseConfigured) return const SizedBox(width: 40);
    final sameDept = member.departmentId == me?.departmentId;
    final canManage = perms.isAdmin || (perms.isManager && sameDept);
    if (!canManage) return const SizedBox(width: 40);
    final deptRoles = roles.where((r) => r.departmentId == member.departmentId).toList();

    Future<void> run(Future<void> Function() action, String done) async {
      try {
        await action();
        onChanged();
      } on AuthException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }

    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz),
      onSelected: (v) async {
        final roles = ref.read(rolesControllerProvider);
        if (v == 'none') return run(() => roles.assign(member.id, null), 'cleared');
        if (v == 'manager') return run(() => roles.setRole(member.id, 'manager'), 'promoted');
        if (v == 'member') return run(() => roles.setRole(member.id, 'member'), 'demoted');
        if (v == 'remove') {
          final yes = await showConfirmDialog(
            context,
            title: 'Remove ${member.displayName}?',
            message: 'This deletes their account. Their tasks stay.',
            confirmLabel: 'Remove',
          );
          if (yes) await run(() => ref.read(adminControllerProvider).deleteAccount(member.id), 'removed');
          return;
        }
        if (v.startsWith('role:')) {
          return run(() => roles.assign(member.id, v.substring(5)), 'assigned');
        }
      },
      itemBuilder: (_) => [
        if (!member.isManager) ...[
          const PopupMenuItem(enabled: false, child: Text('Job title')),
          const PopupMenuItem(value: 'none', child: Text('No title (member)')),
          for (final r in deptRoles)
            PopupMenuItem(
              value: 'role:${r.id}',
              child: Row(children: [
                Icon(r.id == member.customRoleId ? Icons.check : null, size: 16),
                const SizedBox(width: 8),
                Text(r.name),
              ]),
            ),
          if (perms.isAdmin) const PopupMenuDivider(),
        ],
        if (perms.isAdmin)
          member.isManager
              ? const PopupMenuItem(value: 'member', child: Text('Make member'))
              : const PopupMenuItem(value: 'manager', child: Text('Make manager')),
        if (perms.isAdmin || !member.isManager) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'remove', child: Text('Remove account')),
        ],
      ],
    );
  }
}

/// A manager's job titles: create, rename, tick permissions, delete.
class _RolesCard extends ConsumerStatefulWidget {
  const _RolesCard({
    required this.roles,
    required this.departments,
    required this.myDepartmentId,
    required this.admin,
  });

  final List<DepartmentRole> roles;
  final List<Department> departments;
  final String? myDepartmentId;
  final bool admin;

  @override
  ConsumerState<_RolesCard> createState() => _RolesCardState();
}

class _RolesCardState extends ConsumerState<_RolesCard> {
  String? _deptId;

  String? get _dept => _deptId ?? widget.myDepartmentId;

  Future<void> _edit(BuildContext context, {DepartmentRole? role}) async {
    final dept = role?.departmentId ?? _dept;
    if (dept == null) return;
    final name = TextEditingController(text: role?.name ?? '');
    final perms = {
      for (final k in DepartmentRole.permissionLabels.keys) k: role?.has(k) ?? false,
    };
    String? error;
    final saved = await showBlurredDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(role == null ? 'New role' : 'Edit role'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Job title'),
                ),
                const SizedBox(height: NocturneSpace.s2),
                const StampLabel('Can also'),
                for (final e in DepartmentRole.permissionLabels.entries)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(e.value),
                    value: perms[e.key],
                    onChanged: (v) => setLocal(() => perms[e.key] = v ?? false),
                  ),
                Text(
                  'Managing roles, promoting managers, adding or removing '
                  'people and deleting projects stay with managers.',
                  style: TextStyle(fontSize: 12, color: context.nocturne.neutral500),
                ),
                if (error != null) ...[
                  const SizedBox(height: NocturneSpace.s2),
                  Text(error!, style: TextStyle(color: context.nocturne.danger)),
                ],
              ],
            ),
          ),
          actions: [
            NocturneButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop(false)),
            NocturneButton(
              label: 'Save',
              variant: NocturneButtonVariant.primary,
              onPressed: () async {
                if (name.text.trim().isEmpty) {
                  setLocal(() => error = 'Enter a job title');
                  return;
                }
                try {
                  final c = ref.read(rolesControllerProvider);
                  if (role == null) {
                    await c.create(dept, name.text, perms);
                  } else {
                    await c.update(role.id, name: name.text, perms: perms);
                  }
                  if (context.mounted) Navigator.of(context).pop(true);
                } on AuthException catch (e) {
                  setLocal(() => error = e.message);
                }
              },
            ),
          ],
        ),
      ),
    );
    if (saved ?? false) ref.invalidate(departmentMembersProvider);
  }

  Future<void> _delete(BuildContext context, DepartmentRole role) async {
    final yes = await showConfirmDialog(
      context,
      title: 'Delete "${role.name}"?',
      message: 'Only possible when nobody has this title.',
    );
    if (!yes) return;
    try {
      await ref.read(rolesControllerProvider).delete(role.id);
    } on AuthException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dept = _dept;
    final shown = widget.roles.where((r) => r.departmentId == dept).toList();
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.admin && widget.departments.isNotEmpty) ...[
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: DropdownButton<String>(
                value: dept,
                isExpanded: true,
                hint: const Text('Department'),
                underline: const SizedBox.shrink(),
                items: [
                  for (final d in widget.departments.where((d) => !d.isOperator))
                    DropdownMenuItem(
                      value: d.id,
                      child: Text(d.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _deptId = v),
              ),
            ),
          ),
          const SizedBox(width: NocturneSpace.s2),
        ],
        NocturneButton(
          label: 'New role',
          icon: Icons.add,
          dense: true,
          onPressed: dept == null ? null : () => _edit(context),
        ),
      ],
    );
    return DecoratedBox(
      decoration: panelDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(NocturneSpace.s3),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: NocturneSpace.s2,
              runSpacing: NocturneSpace.s2,
              children: [const StampLabel('Job titles'), controls],
            ),
          ),
          const Divider(),
          _rolesBody(context, shown, dept),
        ],
      ),
    );
  }

  Widget _rolesBody(BuildContext context, List<DepartmentRole> shown, String? dept) {
    final tokens = context.nocturne;
    return Builder(builder: (context) {
      if (shown.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(NocturneSpace.s4),
          child: Text(
            dept == null
                ? 'Pick a department to manage its job titles.'
                : 'No job titles yet. Create one (e.g. Senior) to give members a title and extra permissions.',
            style: TextStyle(color: tokens.neutral500),
          ),
        );
      }
      return _rolesList(context, shown);
    });
  }

  Widget _rolesList(BuildContext context, List<DepartmentRole> shown) {
    return Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NocturneSpace.s3,
                      vertical: NocturneSpace.s2,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: NocturneSpace.s2,
                            runSpacing: NocturneSpace.s1,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(shown[i].name,
                                  style: Theme.of(context).textTheme.bodyLarge),
                              for (final e in DepartmentRole.permissionLabels.entries)
                                if (shown[i].has(e.key))
                                  NocturneTag(label: e.value, outline: true),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit role',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _edit(context, role: shown[i]),
                        ),
                        IconButton(
                          tooltip: 'Delete role',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _delete(context, shown[i]),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
    );
  }
}
