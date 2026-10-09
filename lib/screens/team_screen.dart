import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile.dart';
import '../models/task.dart';
import '../providers/department_members_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/panel/panel.dart';
import '../widgets/people_plates.dart';

/// A manager-only view of the department's workload: every member next to
/// their open task count and total estimated time remaining ("occupancy").
/// Visibility beyond the signed-in user's own department is governed
/// entirely by the `profiles`/`tasks` RLS policies — this just renders
/// whatever [departmentMembersProvider]/[tasksProvider] already surface.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.nocturne;
    final membersAsync = ref.watch(departmentMembersProvider);
    final tasks = ref.watch(tasksProvider);

    return membersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: PanelNotice('Could not load team: $error', isError: true),
      ),
      data: (members) {
        if (members.isEmpty) {
          return const Center(child: PanelNotice('No team members yet.'));
        }
        final rows = [
          for (final member in members) _occupancyFor(member, tasks),
        ]..sort((a, b) => b.totalMinutes.compareTo(a.totalMinutes));
        final maxOpen = rows.fold<int>(
          1,
          (m, r) => r.openTaskCount > m ? r.openTaskCount : m,
        );

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Team', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Open tasks and estimated remaining time per teammate.',
                style: TextStyle(color: tokens.neutral500),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: DecoratedBox(
                  decoration: panelDecoration(context),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _TeamMemberRow(row: rows[index], maxOpen: maxOpen),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  _MemberOccupancy _occupancyFor(Profile member, List<Task> tasks) {
    final assigned = tasks.where(
      (t) => !t.isChecked && t.assigneeId == member.id,
    );
    final totalMinutes = assigned.fold<int>(
      0,
      (sum, t) => sum + (t.estimatedMinutes ?? 0),
    );
    return _MemberOccupancy(
      member: member,
      openTaskCount: assigned.length,
      totalMinutes: totalMinutes,
    );
  }
}

class _MemberOccupancy {
  _MemberOccupancy({
    required this.member,
    required this.openTaskCount,
    required this.totalMinutes,
  });

  final Profile member;
  final int openTaskCount;
  final int totalMinutes;
}

class _TeamMemberRow extends StatelessWidget {
  const _TeamMemberRow({required this.row, required this.maxOpen});

  final _MemberOccupancy row;

  /// Largest open-task count on the page: the occupancy gauge's full scale.
  final int maxOpen;

  @override
  Widget build(BuildContext context) {
    final hours = row.totalMinutes ~/ 60;
    final minutes = row.totalMinutes % 60;
    final estimateLabel = row.totalMinutes == 0
        ? 'No estimate'
        : hours > 0
        ? '${hours}h ${minutes}m'
        : '${minutes}m';

    const figures = [FontFeature.tabularFigures()];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          AvatarWell(
            initial: row.member.displayName.isEmpty
                ? '?'
                : row.member.displayName[0].toUpperCase(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.member.displayName),
                const SizedBox(height: 3),
                RolePlate(isManager: row.member.isManager),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${row.openTaskCount} open',
                style: const TextStyle(fontFeatures: figures),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 80,
                child: GaugeBar(
                  value: row.openTaskCount / maxOpen,
                  segments: 10,
                  height: 6,
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 112,
            child: DecoratedBox(
              decoration: panelDecoration(context, depth: PanelDepth.recessed),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  estimateLabel,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontFeatures: figures),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
