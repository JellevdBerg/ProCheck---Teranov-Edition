import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_config.dart';
import '../models/profile.dart';
import 'auth_provider.dart';

/// Every profile a manager can assign tasks to or see on the team
/// dashboard: their own department's members, or — for the Operator
/// department — everyone. Mirrors the `profiles_select` RLS policy, so
/// this never shows more than the signed-in user could already query
/// directly; it's a convenience list, not an extra permission.
final departmentMembersProvider = FutureProvider<List<Profile>>((ref) async {
  if (!isSupabaseConfigured) return [];
  if (supabase.auth.currentUser == null) return [];
  // Re-fetch whenever the signed-in profile changes (sign-in/out, or a
  // department reassignment landing via the next pull).
  ref.watch(currentProfileProvider);

  final rows = await supabase.from('profiles').select();
  return (rows as List)
      .map((row) => Profile.fromJson(row as Map<String, dynamic>))
      .toList();
});
