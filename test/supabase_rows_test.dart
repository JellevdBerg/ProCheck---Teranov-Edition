import 'package:flutter_test/flutter_test.dart';

import 'package:procheck/models/project.dart';
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
}
