import 'package:flutter_test/flutter_test.dart';

import 'package:procheck/models/profile.dart';
import 'package:procheck/models/project.dart';
import 'package:procheck/providers/department_members_provider.dart';
import 'package:procheck/models/task.dart';

// `owner_id` is nullable in the schema (`on delete set null`), so a row whose
// owner account was deleted must still parse rather than throw on pull.
void main() {
  test('Task.fromSupabase tolerates a null owner_id', () {
    final task = Task.fromSupabase({
      'id': 't1',
      'title': 'Orphaned',
      'created_at': '2026-10-01T10:00:00Z',
      'owner_id': null,
      'department_id': 'd1',
    });
    expect(task.ownerId, '');
    expect(task.departmentId, 'd1');
  });

  test('Project.fromSupabase tolerates a null owner_id', () {
    final project = Project.fromSupabase({
      'id': 'p1',
      'name': 'Orphaned',
      'created_at': '2026-10-01T10:00:00Z',
      'owner_id': null,
      'department_id': 'd1',
    });
    expect(project.ownerId, '');
  });

  // Comments/activity are append-only on the server; the regular upsert must
  // not carry this device's copy or it overwrites a teammate's new entries.
  test('Project.toSupabase omits append-only columns unless asked', () {
    final project = Project(
      id: 'p1',
      name: 'P',
      createdAt: DateTime(2026, 10, 1),
      ownerId: 'o1',
      departmentId: 'd1',
    );
    expect(project.toSupabase().containsKey('comments'), isFalse);
    expect(project.toSupabase().containsKey('activity_log'), isFalse);
    final full = project.toSupabase(includeAppendOnly: true);
    expect(full['comments'], isEmpty);
    expect(full['activity_log'], isEmpty);
    expect(full['owner_id'], 'o1');
  });

  test('DirectoryEntry.fromJson maps role and tolerates a null department', () {
    final manager = DirectoryEntry.fromJson({
      'id': 'u1',
      'display_name': 'Mia',
      'role': 'manager',
      'department_id': null,
    });
    expect(manager.role, UserRole.manager);
    expect(manager.departmentId, isNull);
    expect(
      DirectoryEntry.fromJson({
        'id': 'u2',
        'display_name': 'Sam',
        'role': 'member',
        'department_id': 'd1',
      }).role,
      UserRole.member,
    );
  });
}
