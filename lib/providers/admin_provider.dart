import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../data/supabase_config.dart';
import 'auth_provider.dart';

/// Operator/IT-only actions. Department creation and the still-kept
/// `admin_create_profile` fallback call a SECURITY DEFINER SQL function
/// (see `supabase/migrations/20261008130000_admin_provisioning.sql`);
/// account create/reset-password/deactivate/reactivate go through the
/// `admin-users` Edge Function instead (Phase 4 — uses the real Supabase
/// Auth Admin API for banning/password changes rather than writing into
/// auth.users by hand). Every one of these re-checks authority
/// server-side — this class doesn't grant anything.
class AdminController {
  Future<void> createDepartment(String name, {bool isIt = false}) async {
    try {
      await supabase.rpc(
        'admin_create_department',
        params: {'p_name': name, 'p_is_it': isIt},
      );
    } on PostgrestException catch (e) {
      throw AuthException(e.message);
    }
  }

  Future<void> archiveDepartment(String departmentId) async {
    try {
      await supabase.rpc(
        'admin_archive_department',
        params: {'p_department_id': departmentId},
      );
    } on PostgrestException catch (e) {
      throw AuthException(e.message);
    }
  }

  /// Hard delete — Operator-only, and only for a department with no
  /// members or projects left (see the migration for why).
  Future<void> deleteDepartment(String departmentId) async {
    try {
      await supabase.rpc(
        'admin_delete_department',
        params: {'p_department_id': departmentId},
      );
    } on PostgrestException catch (e) {
      throw AuthException(e.message);
    }
  }

  Future<void> createAccount({
    required String username,
    required String password,
    required String displayName,
    required String role,
    String? departmentId,
  }) => _invoke('create', {
    'username': username,
    'password': password,
    'displayName': displayName,
    'role': role,
    'departmentId': departmentId,
  });

  Future<void> resetPassword({
    required String userId,
    required String password,
  }) => _invoke('reset_password', {'userId': userId, 'password': password});

  /// The default "remove" action — bans the auth user and sets
  /// `profiles.is_active = false`. Keeps the person's task/project
  /// history intact; they just stop showing up for new assignment.
  Future<void> deactivateAccount(String userId) =>
      _invoke('deactivate', {'userId': userId});

  Future<void> reactivateAccount(String userId) =>
      _invoke('reactivate', {'userId': userId});

  /// Hard delete — Operator-only, behind a typed confirmation in the UI.
  Future<void> deleteAccount(String userId) async {
    try {
      await supabase.rpc('admin_delete_profile', params: {'p_user_id': userId});
    } on PostgrestException catch (e) {
      throw AuthException(e.message);
    }
  }

  Future<void> _invoke(String action, Map<String, dynamic> params) async {
    try {
      final response = await supabase.functions.invoke(
        'admin-users',
        body: {'action': action, ...params},
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw AuthException(data['error'].toString());
      }
    } on FunctionException catch (e) {
      final data = e.details;
      final message = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Request failed (${e.status})';
      throw AuthException(message);
    }
  }
}

final adminControllerProvider = Provider((ref) => AdminController());
