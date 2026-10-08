import 'package:supabase_flutter/supabase_flutter.dart';

/// Project URL and anon/publishable key, read from `--dart-define` so
/// neither ever lands in source control. Pass them at build/run time, e.g.:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxxx
///
/// For day-to-day development, put the same flags in a `--dart-define-from-file`
/// JSON file (e.g. `supabase.local.json`, already gitignored) instead of
/// typing them every time; see the Flutter docs for `--dart-define-from-file`.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Whether Supabase credentials were supplied at all. Call sites use this to
/// skip auth entirely when they're missing, so running the app with no
/// `--dart-define`s still boots (useful for local-only Hive development)
/// instead of crashing on an empty URL.
bool get isSupabaseConfigured =>
    _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

Future<void> setUpSupabase() async {
  if (!isSupabaseConfigured) return;
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabaseAnonKey,
  );
}

SupabaseClient get supabase => Supabase.instance.client;
