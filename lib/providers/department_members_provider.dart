import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_config.dart';
import '../models/profile.dart';
import 'auth_provider.dart';

/// A person as `profile_directory()` exposes them: just enough to show a
/// name, with no email/username. Unlike [Profile], a plain member can fetch
/// these for their own department (see
/// `20261009100000_atomic_appends_and_profile_directory.sql`).
class DirectoryEntry {
  const DirectoryEntry({
    required this.id,
    required this.displayName,
    required this.role,
    this.departmentId,
    this.customRoleId,
    this.customRoleName,
    this.isActive = true,
  });

  final String id;
  final String displayName;
  final UserRole role;
  final String? departmentId;
  final String? customRoleId;

  /// The job title, when this person has one.
  final String? customRoleName;

  /// Deactivated accounts (Phase 4 lifecycle) disappear from assignment
  /// pickers but keep showing up anywhere their history is read back.
  final bool isActive;

  factory DirectoryEntry.fromJson(Map<String, dynamic> json) => DirectoryEntry(
    id: json['id'] as String,
    displayName: json['display_name'] as String,
    role: json['role'] == 'manager' ? UserRole.manager : UserRole.member,
    departmentId: json['department_id'] as String?,
    customRoleId: json['custom_role_id'] as String?,
    customRoleName: json['custom_role_name'] as String?,
    isActive: json['is_active'] as bool? ?? true,
  );
}

/// Names for everyone the signed-in user may see, keyed by id. Empty when
/// signed out, or when the server function isn't deployed yet — callers fall
/// back to what they did before, so this can ship ahead of the migration.
final profileDirectoryProvider = FutureProvider<Map<String, DirectoryEntry>>((
  ref,
) async {
  if (!isSupabaseConfigured) return const {};
  // Watched BEFORE the signed-out early return so a later sign-in re-runs
  // this provider (otherwise the signed-out result is cached forever).
  ref.watch(currentProfileProvider);
  if (supabase.auth.currentUser == null) return const {};
  try {
    final rows = await supabase.rpc('profile_directory');
    return {
      for (final row in rows as List)
        (row as Map<String, dynamic>)['id'] as String: DirectoryEntry.fromJson(
          row,
        ),
    };
  } catch (_) {
    return const {};
  }
});

/// Every profile a manager can assign tasks to or see on the team
/// dashboard: their own department's members, or — for the Operator
/// department — everyone. Mirrors the `profiles_select` RLS policy, so
/// this never shows more than the signed-in user could already query
/// directly; it's a convenience list, not an extra permission.
final departmentMembersProvider = FutureProvider<List<Profile>>((ref) async {
  if (!isSupabaseConfigured) return [];
  // Watched BEFORE the signed-out early return so a later sign-in re-runs
  // this provider (otherwise the signed-out result is cached forever).
  ref.watch(currentProfileProvider);
  if (supabase.auth.currentUser == null) return [];
  // Re-fetch whenever the signed-in profile changes (sign-in/out, or a
  // department reassignment landing via the next pull).

  final rows = await supabase.from('profiles').select();
  return (rows as List)
      .map((row) => Profile.fromJson(row as Map<String, dynamic>))
      .toList();
});
