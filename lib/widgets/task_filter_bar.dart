import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_config.dart';
import '../models/department.dart';
import '../models/task.dart';
import '../providers/auth_provider.dart';
import '../providers/departments_provider.dart';
import '../screens/empty_state.dart';
import '../theme/nocturne_theme.dart';
import 'people_plates.dart';

/// Client-side filter shared by Today, Upcoming and Dashboard. The default
/// (no flags) lets every task through. Local widget state, never persisted.
class TaskFilter {
  const TaskFilter({this.mine = false, this.departmentId});

  final bool mine;
  final String? departmentId;

  bool get isActive => mine || departmentId != null;

  TaskFilter copyWith({bool? mine, Object? departmentId = _keep}) => TaskFilter(
    mine: mine ?? this.mine,
    departmentId: identical(departmentId, _keep)
        ? this.departmentId
        : departmentId as String?,
  );

  List<Task> apply(List<Task> tasks, String? userId) => !isActive
      ? tasks
      : tasks
            .where(
              (t) =>
                  (!mine || (userId != null && t.assigneeId == userId)) &&
                  (departmentId == null || t.departmentId == departmentId),
            )
            .toList();
}

const _keep = Object();

/// What the bar may offer: [userId] is null in single-user mode (no
/// "Assigned to me"); [departments] is non-empty only for Operator/IT admins
/// when more than one department exists.
typedef TaskFilterOptions = ({String? userId, List<Department> departments});

final taskFilterOptionsProvider = Provider<TaskFilterOptions>((ref) {
  final signedIn = isSupabaseConfigured && supabase.auth.currentUser != null;
  if (!signedIn) return (userId: null, departments: const <Department>[]);
  final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
  final departments = ref.watch(departmentsProvider).valueOrNull ?? const [];
  return (
    userId: ref.watch(currentProfileProvider).valueOrNull?.id,
    departments: isAdmin && departments.length > 1 ? departments : const [],
  );
});

/// Compact wrapping row of filter chips: All / Assigned to me / Department.
class TaskFilterBar extends ConsumerWidget {
  const TaskFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
  });

  /// Only applied while the bar is visible, so a hidden bar adds no space.
  final EdgeInsets padding;

  final TaskFilter filter;
  final ValueChanged<TaskFilter> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opts = ref.watch(taskFilterOptionsProvider);
    // Nothing but "All" to offer: no bar at all.
    if (opts.userId == null && opts.departments.isEmpty) {
      return const SizedBox.shrink();
    }
    final dept = opts.departments
        .where((d) => d.id == filter.departmentId)
        .firstOrNull;
    return Padding(
      padding: padding,
      child: Wrap(
      spacing: NocturneSpace.s2,
      runSpacing: NocturneSpace.s2,
      children: [
        _Chip(
          label: 'All',
          selected: !filter.isActive,
          onTap: () => onChanged(const TaskFilter()),
        ),
        if (opts.userId != null)
          _Chip(
            label: 'Assigned to me',
            selected: filter.mine,
            onTap: () => onChanged(filter.copyWith(mine: !filter.mine)),
          ),
        if (opts.departments.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'Filter by department',
            onSelected: (id) => onChanged(filter.copyWith(departmentId: id)),
            itemBuilder: (_) => [
              for (final d in opts.departments)
                PopupMenuItem(
                  value: d.id,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: DepartmentPlate(
                      name: d.name,
                      isOperator: d.isOperator,
                      isIt: d.isIt,
                    ),
                  ),
                ),
            ],
            child: _Chip(
              label: dept?.name ?? 'Department',
              selected: dept != null,
              trailing: Icons.arrow_drop_down,
            ),
          ),
      ],
    ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    this.onTap,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final accent = context.nocturneAccent;
    final fg = selected ? accent : tokens.neutral300;
    final radius = BorderRadius.circular(NocturneRadius.md);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? accent.withValues(alpha: tokens.isDark ? 0.18 : 0.12)
            : tokens.raised,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? Colors.transparent : tokens.edge),
        ),
        child: InkWell(
          // Null onTap: the wrapping PopupMenuButton handles the tap.
          onTap: onTap,
          borderRadius: radius,
          hoverColor: tokens.neutral800,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 20 / 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ),
                  if (trailing != null) Icon(trailing, size: 18, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The screen's [EmptyState] with the filter bar above it and, when a filter
/// is hiding everything, a "Clear filter" action below.
class FilteredEmptyState extends StatelessWidget {
  const FilteredEmptyState({
    super.key,
    required this.icon,
    required this.message,
    required this.filter,
    required this.onChanged,
    required this.gutter,
  });

  final IconData icon;
  final String message;
  final TaskFilter filter;
  final ValueChanged<TaskFilter> onChanged;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, NocturneSpace.s4, gutter, 0),
          child: TaskFilterBar(filter: filter, onChanged: onChanged),
        ),
        Expanded(child: EmptyState(icon: icon, message: message)),
        if (filter.isActive)
          Padding(
            padding: const EdgeInsets.only(bottom: NocturneSpace.s6),
            child: Center(
              child: TextButton(
                onPressed: () => onChanged(const TaskFilter()),
                child: const Text('Clear filter'),
              ),
            ),
          ),
      ],
    );
  }
}
