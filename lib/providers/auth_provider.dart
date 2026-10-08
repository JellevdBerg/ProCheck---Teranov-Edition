import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_config.dart';
import '../models/profile.dart';

/// Raw Supabase auth state (signed in / out) — a thin stream wrapper so
/// widgets can `ref.watch` it instead of subscribing to the client
/// directly. Emits once immediately with the current session, then again
/// on every sign-in/sign-out.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

/// The signed-in user's own `profiles` row, re-fetched whenever the auth
/// state changes. Null while signed out; the one-time `handle_new_user`
/// trigger guarantees a profile row exists by the time sign-in succeeds, so
/// a signed-in user with no profile row is treated as an error rather than
/// "still loading".
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final userId = authState?.session?.user.id ?? supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final row = await supabase.from('profiles').select().eq('id', userId).single();
  return Profile.fromJson(row);
});

class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// ProCheck is username/password only — no email appears anywhere in the
/// UI. Supabase Auth still requires one under the hood, so each username
/// maps deterministically to a synthetic `<username>@procheck.local`
/// address; nothing ever needs to be sent to it (see `supabase/README.md`
/// for the "Confirm email" dashboard setting this relies on being off).
String emailForUsername(String username) =>
    '${username.trim().toLowerCase()}@procheck.local';

/// Sign-in/sign-out actions for the login screen. Kept as plain async
/// methods rather than a StateNotifier — there's no persisted state here
/// beyond what Supabase's own client already tracks (see
/// [authStateProvider]).
class AuthController {
  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    try {
      await supabase.auth.signInWithPassword(
        email: emailForUsername(username),
        password: password,
      );
    } on AuthApiException catch (e) {
      throw AuthException(e.message);
    }
  }

  Future<void> signOut() => supabase.auth.signOut();
}

final authControllerProvider = Provider((ref) => AuthController());
