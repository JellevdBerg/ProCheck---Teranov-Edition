/// A row in the `departments` table — the visibility boundary between
/// teams (see `supabase/migrations/20261004120000_department_scoping.sql`).
/// Not a Hive object: like [Profile], there's nothing to cache offline,
/// it's just read fresh from Supabase.
class Department {
  const Department({
    required this.id,
    required this.name,
    required this.isOperator,
    required this.isIt,
    this.archivedAt,
  });

  final String id;
  final String name;

  /// Set when the department is archived (Phase 4 lifecycle) — kept
  /// around with its history, just hidden from new project/member
  /// assignment. Blocked while it still owns projects.
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  /// The one department (capped by a DB-side unique index) whose members
  /// bypass every other department's visibility boundary.
  final bool isOperator;

  /// The one other department (same cap) with nearly the same bypass —
  /// everything Operator has except creating/assigning into Operator or
  /// IT itself (see `is_admin()` vs. `is_operator()` in
  /// `20261008140000_it_department.sql`).
  final bool isIt;

  /// Either admin tier — company-wide visibility, reaches the Admin
  /// screen.
  bool get isAdminTier => isOperator || isIt;

  factory Department.fromJson(Map<String, dynamic> json) => Department(
    id: json['id'] as String,
    name: json['name'] as String,
    isOperator: json['is_operator'] as bool? ?? false,
    isIt: json['is_it'] as bool? ?? false,
    archivedAt: json['archived_at'] == null
        ? null
        : DateTime.tryParse(json['archived_at'] as String),
  );
}
