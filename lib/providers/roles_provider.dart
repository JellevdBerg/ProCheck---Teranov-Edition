import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../data/supabase_config.dart';
import '../models/department_role.dart';
import 'auth_provider.dart';
import 'departments_provider.dart';

/// Every custom role the signed-in user may see: their own department's, or
/// all of them for IT / Operator (enforced by RLS on `department_roles`).
final departmentRolesProvider = FutureProvider<List<DepartmentRole>>((ref) async {
  if (!isSupabaseConfigured) return const [];
  // Watched before the signed-out return so a later sign-in re-runs this.
  ref.watch(currentProfileProvider);
  if (supabase.auth.currentUser == null) return const [];
  final rows = await supabase.from('department_roles').select().order('name');
  return (rows as List)
      .map((r) => DepartmentRole.fromJson(r as Map<String, dynamic>))
      .toList();
});

/// Create / edit / delete roles and hand them to members. All of it is
/// enforced by RLS and the SQL functions; this only calls them.
class RolesController {
  RolesController(this._ref);
  final Ref _ref;

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      final result = await action();
      _ref.invalidate(departmentRolesProvider);
      return result;
    } on PostgrestException catch (e) {
      throw AuthException(
        e.code == '23503'
            ? 'That role is still assigned to someone. Reassign them first.'
            : e.code == '23505'
            ? 'This department already has a role with that name.'
            : e.message,
      );
    }
  }

  Future<void> create(String departmentId, String name, Map<String, bool> perms) =>
      _run(() => supabase.from('department_roles').insert({
        'department_id': departmentId,
        'name': name.trim(),
        ...perms,
      }));

  Future<void> update(String id, {String? name, Map<String, bool>? perms}) =>
      _run(() => supabase.from('department_roles').update({
        // ignore: use_null_aware_elements
        if (name != null) 'name': name.trim(),
        ...?perms,
      }).eq('id', id));

  Future<void> delete(String id) =>
      _run(() => supabase.from('department_roles').delete().eq('id', id));

  /// Gives [userId] the job title [roleId] (null clears it).
  Future<void> assign(String userId, String? roleId) => _run(
    () => supabase.rpc('set_member_role', params: {
      'p_user_id': userId,
      'p_role_id': roleId,
    }),
  );

  /// Promotes a member to manager or demotes a manager (IT / Operator only).
  Future<void> setRole(String userId, String role) => _run(
    () => supabase.rpc('set_user_role', params: {
      'p_user_id': userId,
      'p_role': role,
    }),
  );
}

final rolesControllerProvider = Provider((ref) => RolesController(ref));

/// What the signed-in person may do, derived from the same data the database
/// uses (manager flag, Operator/IT, their job title's flags). This only
/// decides which buttons to show; every action is enforced server-side.
class Permissions {
  const Permissions({
    this.isManager = false,
    this.isAdmin = false,
    this.isOperator = false,
    this.createProjects = false,
    this.editProjects = false,
    this.manageTasks = false,
    this.viewTeam = false,
  });

  /// Single-user / signed-out use: nothing is restricted.
  static const everything = Permissions(
    isManager: true,
    isAdmin: true,
    isOperator: true,
    createProjects: true,
    editProjects: true,
    manageTasks: true,
    viewTeam: true,
  );

  final bool isManager;

  /// Operator or IT — the same broad check `is_admin()` makes server-side.
  /// A few call sites used to call this "isAdminTier"; same fact, one name.
  final bool isAdmin;

  /// The Operator department specifically, not IT — gates the narrower
  /// admin actions only Operator can do. Previously fetched separately
  /// from [isOperatorProvider] at each call site instead of living here
  /// alongside the other role-tier facts.
  final bool isOperator;

  final bool createProjects;
  final bool editProjects;
  final bool manageTasks;
  final bool viewTeam;
}

final permissionsProvider = Provider<Permissions>((ref) {
  if (!isSupabaseConfigured || supabase.auth.currentUser == null) {
    return Permissions.everything;
  }
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  if (profile == null) return const Permissions();
  final admin = ref.watch(isAdminProvider).valueOrNull ?? false;
  final operator = ref.watch(isOperatorProvider).valueOrNull ?? false;
  if (admin || profile.isManager) {
    return Permissions(isManager: profile.isManager, isAdmin: admin,
        isOperator: operator,
        createProjects: true, editProjects: true, manageTasks: true, viewTeam: true);
  }
  final role = ref
      .watch(departmentRolesProvider)
      .valueOrNull
      ?.where((r) => r.id == profile.customRoleId)
      .firstOrNull;
  return Permissions(
    isOperator: operator,
    createProjects: role?.createProjects ?? false,
    editProjects: role?.editProjects ?? false,
    manageTasks: role?.manageTasks ?? false,
    viewTeam: role?.viewTeam ?? false,
  );
});
