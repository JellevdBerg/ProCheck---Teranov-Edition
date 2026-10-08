import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_config.dart';
import '../models/department.dart';
import 'auth_provider.dart';

/// Every department, for the admin screen's department list and the
/// "which department does this person belong to" picker. `departments`
/// has no visibility restriction beyond being signed in (see
/// `departments_select_authenticated` in the RLS migration), so this is
/// safe for any signed-in user to read, not just an Operator.
final departmentsProvider = FutureProvider<List<Department>>((ref) async {
  if (!isSupabaseConfigured) return [];
  if (supabase.auth.currentUser == null) return [];
  ref.watch(currentProfileProvider);

  final rows = await supabase.from('departments').select().order('name');
  return (rows as List)
      .map((row) => Department.fromJson(row as Map<String, dynamic>))
      .toList();
});

/// Whether the signed-in user sits in the Operator department — gates the
/// admin screen's nav entry. Calls the same `is_operator()` SQL function
/// the RLS policies use, so this can never show the nav item to someone
/// the backend would then refuse (see `admin_create_department`/
/// `admin_create_profile`'s own `is_operator()` checks).
final isOperatorProvider = FutureProvider<bool>((ref) async {
  if (!isSupabaseConfigured) return false;
  if (supabase.auth.currentUser == null) return false;
  ref.watch(currentProfileProvider);

  return await supabase.rpc('is_operator') as bool;
});
