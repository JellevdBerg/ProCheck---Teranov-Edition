/// A person's row in the `profiles` table (see
/// `supabase/migrations/0001_initial_schema.sql`). Loaded fresh from
/// Supabase on sign-in — unlike [Task]/[Project] this isn't a Hive object,
/// since there's nothing to cache offline yet: without a signed-in session
/// there's no profile to show.
enum UserRole { member, manager }

UserRole _roleFromString(String value) => switch (value) {
  'manager' => UserRole.manager,
  _ => UserRole.member,
};

class Profile {
  const Profile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.departmentId,
  });

  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final String? departmentId;

  bool get isManager => role == UserRole.manager;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['display_name'] as String,
    role: _roleFromString(json['role'] as String),
    departmentId: json['department_id'] as String?,
  );
}
