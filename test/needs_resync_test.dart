import 'package:flutter_test/flutter_test.dart';
import 'package:procheck/providers/syncable_notifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('needsResync', () {
    test('signing back in after a sign-out resyncs', () {
      expect(
        needsResync(
          event: AuthChangeEvent.signedIn,
          sessionUserId: 'u1',
          syncedUserId: null,
        ),
        isTrue,
      );
    });

    test('a different user signing in resyncs', () {
      expect(
        needsResync(
          event: AuthChangeEvent.signedIn,
          sessionUserId: 'u2',
          syncedUserId: 'u1',
        ),
        isTrue,
      );
    });

    test('token refresh / initial session for the synced user does not', () {
      for (final event in [
        AuthChangeEvent.tokenRefreshed,
        AuthChangeEvent.initialSession,
        AuthChangeEvent.signedIn,
      ]) {
        expect(
          needsResync(
            event: event,
            sessionUserId: 'u1',
            syncedUserId: 'u1',
          ),
          isFalse,
        );
      }
    });

    test('signing out and a session-less event never resync', () {
      expect(
        needsResync(
          event: AuthChangeEvent.signedOut,
          sessionUserId: null,
          syncedUserId: 'u1',
        ),
        isFalse,
      );
    });
  });
}
