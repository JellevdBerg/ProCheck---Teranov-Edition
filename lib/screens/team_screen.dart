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

        return LayoutBuilder(
          builder: (context, constraints) {
            final gutter = constraints.maxWidth < NocturneBreakpoints.compact
                ? NocturneSpace.s4
                : NocturneSpace.s6;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Padding(
                  padding: EdgeInsets.all(gutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Team',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: NocturneSpace.s1),
                      Text(
                        'Open tasks and estimated remaining time per teammate.',
                        style: TextStyle(color: tokens.neutral500),
                      ),
                      const SizedBox(height: NocturneSpace.s4),
                      Expanded(
                        child: DecoratedBox(
                          decoration: panelDecoration(context),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              NocturneRadius.lg,
                            ),
                            child: ListView.separated(
                              itemCount: rows.length,
                              separatorBuilder: (_, _) => const Divider(),
                              itemBuilder: (context, index) => _TeamMemberRow(
                                row: rows[index],
                                maxOpen: maxOpen,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
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
    final tokens = context.nocturne;
    final hours = row.totalMinutes ~/ 60;
    final minutes = row.totalMinutes % 60;
    final estimateLabel = row.totalMinutes == 0
        ? 'No estimate'
        : hours > 0
        ? '${hours}h ${minutes}m'
        : '${minutes}m';

    final who = Row(
      children: [
        AvatarWell(
          initial: row.member.displayName.isEmpty
              ? '?'
              : row.member.displayName[0].toUpperCase(),
        ),
        const SizedBox(width: NocturneSpace.s3),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: NocturneSpace.s2,
            runSpacing: NocturneSpace.s1,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  row.member.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              RolePlate(isManager: row.member.isManager),
            ],
          ),
        ),
      ],
    );
    final open = Text(
      '${row.openTaskCount} open',
      style: TextStyle(fontSize: 13, color: tokens.neutral300),
    );
    final estimate = Text(
      estimateLabel,
      textAlign: TextAlign.right,
      style: TextStyle(fontSize: 13, color: tokens.neutral300),
    );
    final gauge = GaugeBar(value: row.openTaskCount / maxOpen);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NocturneSpace.s3,
        vertical: NocturneSpace.s2,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Stack the occupancy line under the person when narrow.
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                who,
                const SizedBox(height: NocturneSpace.s2),
                Row(
                  children: [
                    open,
                    const SizedBox(width: NocturneSpace.s3),
                    Expanded(child: gauge),
                    const SizedBox(width: NocturneSpace.s3),
                    estimate,
                  ],
                ),
              ],
            );
          }
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              children: [
                Expanded(child: who),
                const SizedBox(width: NocturneSpace.s4),
                SizedBox(width: 64, child: open),
                SizedBox(width: 140, child: gauge),
                const SizedBox(width: NocturneSpace.s4),
                SizedBox(width: 88, child: estimate),
              ],
            ),
          );
        },
      ),
    );
  }
}
