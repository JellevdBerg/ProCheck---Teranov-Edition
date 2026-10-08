import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;

import '../data/supabase_config.dart';
import 'auth_provider.dart';

/// Operator-only actions: creating departments and user accounts. Both
/// call a SECURITY DEFINER SQL function (see
/// `supabase/migrations/20261008130000_admin_provisioning.sql`) that
/// re-checks `is_operator()` itself — this class doesn't grant anything,
/// it just calls what the backend already gates.
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

  Future<void> createAccount({
    required String username,
    required String password,
    required String displayName,
    required String role,
    String? departmentId,
  }) async {
    try {
      await supabase.rpc(
        'admin_create_profile',
        params: {
          'p_username': username,
          'p_password': password,
          'p_display_name': displayName,
          'p_role': role,
          'p_department_id': departmentId,
        },
      );
    } on PostgrestException catch (e) {
      throw AuthException(e.message);
    }
  }

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

  Future<void> deleteAccount(String userId) async {
    try {
      await supabase.rpc('admin_delete_profile', params: {'p_user_id': userId});
    } on PostgrestException catch (e) {
      throw AuthException(e.message);
    }
  }
}

final adminControllerProvider = Provider((ref) => AdminController());
