import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_config.dart';
import 'auth_provider.dart';

/// A row from `admin_audit` (see
/// `supabase/migrations/20261011500000_phase5_admin_audit_log.sql`) —
/// written only by the security-definer admin functions and the
/// `admin-users` Edge Function, never by a client directly.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.createdAt,
    required this.actorId,
    required this.action,
    required this.targetType,
    required this.outcome,
    this.targetId,
    this.before,
    this.after,
  });

  final String id;
  final DateTime createdAt;
  final String? actorId;
  final String action;
  final String targetType;
  final String? targetId;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final String outcome;

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    actorId: json['actor_id'] as String?,
    action: json['action'] as String,
    targetType: json['target_type'] as String,
    targetId: json['target_id'] as String?,
    before: json['before'] as Map<String, dynamic>?,
    after: json['after'] as Map<String, dynamic>?,
    outcome: json['outcome'] as String,
  );
}

/// The most recent audit rows an admin can see — `admin_audit`'s RLS
/// already restricts this to `is_admin()`, so a plain member gets an
/// empty list rather than an error. Filtering (actor/action/date) happens
/// client-side over this one fetch, same as the rest of the Admin screen.
final auditLogProvider = FutureProvider<List<AuditEntry>>((ref) async {
  if (!isSupabaseConfigured) return [];
  ref.watch(currentProfileProvider);
  if (supabase.auth.currentUser == null) return [];

  final rows = await supabase
      .from('admin_audit')
      .select()
      .order('created_at', ascending: false)
      .limit(500);
  return (rows as List)
      .map((row) => AuditEntry.fromJson(row as Map<String, dynamic>))
      .toList();
});

/// Open tasks (owned or assigned) belonging to a deactivated person, keyed
/// by that person's id — the Admin screen's "needs attention" strip.
final inactiveWithOpenTasksProvider = FutureProvider<Map<String, int>>((
  ref,
) async {
  if (!isSupabaseConfigured) return {};
  ref.watch(currentProfileProvider);
  if (supabase.auth.currentUser == null) return {};

  final rows = await supabase
      .from('tasks')
      .select('owner_id, assignee_id')
      .eq('is_checked', false);
  final counts = <String, int>{};
  for (final row in rows as List) {
    final map = row as Map<String, dynamic>;
    for (final id in {map['owner_id'], map['assignee_id']}) {
      if (id is String) counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return counts;
});

/// Projects with no owning department — can only happen from data that
/// predates the empty-department-only hard delete rule, but worth
/// surfacing rather than letting them silently disappear from every
/// department-scoped view.
final projectsWithoutDepartmentProvider = FutureProvider<int>((ref) async {
  if (!isSupabaseConfigured) return 0;
  ref.watch(currentProfileProvider);
  if (supabase.auth.currentUser == null) return 0;

  final rows = await supabase.from('projects').select('id').isFilter(
        'department_id',
        null,
      );
  return (rows as List).length;
});
