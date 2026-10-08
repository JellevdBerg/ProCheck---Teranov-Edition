/// A row in the `departments` table — the visibility boundary between
/// teams (see `supabase/migrations/20261004120000_department_scoping.sql`).
/// Not a Hive object: like [Profile], there's nothing to cache offline,
/// it's just read fresh from Supabase.
class Department {
  const Department({
    required this.id,
    required this.name,
    required this.isOperator,
  });

  final String id;
  final String name;

  /// The one department (capped by a DB-side unique index) whose members
  /// bypass every other department's visibility boundary.
  final bool isOperator;

  factory Department.fromJson(Map<String, dynamic> json) => Department(
    id: json['id'] as String,
    name: json['name'] as String,
    isOperator: json['is_operator'] as bool? ?? false,
  );
}
