/// A job title a manager creates for their department (`department_roles`),
/// with the few extra permissions it grants on top of plain member rights.
/// "Manager" is the one fixed role and is not a [DepartmentRole].
class DepartmentRole {
  const DepartmentRole({
    required this.id,
    required this.departmentId,
    required this.name,
    this.createProjects = false,
    this.editProjects = false,
    this.manageTasks = false,
    this.viewTeam = false,
  });

  final String id;
  final String departmentId;
  final String name;
  final bool createProjects;
  final bool editProjects;
  final bool manageTasks;
  final bool viewTeam;

  factory DepartmentRole.fromJson(Map<String, dynamic> json) => DepartmentRole(
    id: json['id'] as String,
    departmentId: json['department_id'] as String,
    name: json['name'] as String,
    createProjects: json['create_projects'] as bool? ?? false,
    editProjects: json['edit_projects'] as bool? ?? false,
    manageTasks: json['manage_tasks'] as bool? ?? false,
    viewTeam: json['view_team'] as bool? ?? false,
  );

  /// The checkbox labels, in the order the role editor shows them.
  static const permissionLabels = {
    'create_projects': 'Create projects',
    'edit_projects': 'Edit and archive projects',
    'manage_tasks': 'Add and assign tasks in projects',
    'view_team': 'View the Team dashboard',
  };

  bool has(String permission) => switch (permission) {
    'create_projects' => createProjects,
    'edit_projects' => editProjects,
    'manage_tasks' => manageTasks,
    'view_team' => viewTeam,
    _ => false,
  };
}
