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
  // Watched BEFORE the signed-out early return so a later sign-in re-runs
  // this provider (otherwise the signed-out result is cached forever).
  ref.watch(currentProfileProvider);
  if (supabase.auth.currentUser == null) return [];

  final rows = await supabase.from('departments').select().order('name');
  return (rows as List)
      .map((row) => Department.fromJson(row as Map<String, dynamic>))
      .toList();
});

/// Whether the signed-in user sits in the Operator department specifically
/// (not IT) — gates the narrower admin actions only Operator can do:
/// creating the IT department, and creating/assigning accounts into
/// Operator or IT itself. Calls the same `is_operator()` SQL function the
/// RLS policies use, so the UI can never offer something the backend
/// would then refuse.
final isOperatorProvider = FutureProvider<bool>((ref) async {
  if (!isSupabaseConfigured) return false;
  // Watched BEFORE the signed-out early return so a later sign-in re-runs
  // this provider (otherwise the signed-out result is cached forever).
  ref.watch(currentProfileProvider);
  if (supabase.auth.currentUser == null) return false;

  return await supabase.rpc('is_operator') as bool;
});

/// Whether the signed-in user is in either admin-tier department
/// (Operator or IT) — gates the Admin screen's nav entry itself. Calls
/// `is_admin()`, the same broad check the tasks/projects/profiles RLS
/// policies use (see `20261008140000_it_department.sql`).
final isAdminProvider = FutureProvider<bool>((ref) async {
  if (!isSupabaseConfigured) return false;
  // Watched BEFORE the signed-out early return so a later sign-in re-runs
  // this provider (otherwise the signed-out result is cached forever).
  ref.watch(currentProfileProvider);
  if (supabase.auth.currentUser == null) return false;

  return await supabase.rpc('is_admin') as bool;
});
