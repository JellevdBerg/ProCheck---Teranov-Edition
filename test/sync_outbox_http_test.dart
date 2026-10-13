import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:procheck/data/hive_setup.dart';
import 'package:procheck/data/supabase_config.dart';
import 'package:procheck/models/outbox_entry.dart';
import 'package:procheck/providers/syncable_notifier.dart';

/// isSupabaseConfigured is `const bool.fromEnvironment`-backed, so it can
/// only be true if THIS test run was launched with the dart-defines below —
/// there's no way to flip it from inside a test. Run this file on its own
/// to actually exercise it:
///
///   flutter test --dart-define=SUPABASE_URL=https://fake.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=fake-anon-key \
///     test/sync_outbox_http_test.dart
///
/// Under the default `flutter test` sweep (no dart-defines), every test
/// below is skipped rather than failing.
final _httpTestsEnabled = isSupabaseConfigured;

/// A minimal [SyncableNotifier] mixer — enough to drive
/// [SyncableNotifier.upsertWithConflictCheck]/[SyncableNotifier.replayOutbox]
/// against a faked Supabase backend without going through
/// [TasksNotifier]'s/[ProjectsNotifier]'s full constructor (which would
/// also try a real realtime websocket connect and a profile fetch — things
/// this test has no interest in and no fake transport for).
class _FakeRowNotifier extends StateNotifier<List<Map<String, dynamic>>>
    with SyncableNotifier<Map<String, dynamic>> {
  _FakeRowNotifier(this.ref) : super(const []);

  @override
  final Ref ref;

  @override
  String get syncTable => 'tasks';

  @override
  Box<Map<String, dynamic>> get syncBox =>
      Hive.box<Map<String, dynamic>>('fake_sync_rows');

  @override
  Map<String, dynamic> rowFromSupabase(Map<String, dynamic> row) => row;

  @override
  String idOf(Map<String, dynamic> item) => item['id'] as String;

  @override
  DateTime? updatedAtOf(Map<String, dynamic> item) => item['updated_at'] == null
      ? null
      : DateTime.parse(item['updated_at'] as String);

  @override
  void resortState() {}

  @override
  String describeConflict(Map<String, dynamic>? remote, UpsertOutcome outcome) =>
      'conflict';
}

final _fakeRowProvider =
    StateNotifierProvider<_FakeRowNotifier, List<Map<String, dynamic>>>(
  (ref) => _FakeRowNotifier(ref),
);

/// `Supabase.initialize` defaults to a SharedPreferences-backed PKCE
/// storage, which needs a platform channel this plain `flutter test` VM
/// doesn't have. Nothing here uses the PKCE flow, so a plain in-memory
/// stand-in is enough to let init complete.
class _InMemoryAsyncStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!_httpTestsEnabled) {
    test(
      'HTTP-level outbox transitions (skipped — see this file\'s header '
      'for how to actually run them)',
      () {},
      skip: true,
    );
    return;
  }

  // Reassigned per test so one `MockClient` (Supabase can only be
  // initialized once per process) can play a different fake backend for
  // each scenario.
  late FutureOr<http.Response> Function(http.Request) handler;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('procheck_outbox_http_');
    await setUpHive(testDirectoryPath: tempDir.path);
    await Hive.openBox<Map<String, dynamic>>('fake_sync_rows');

    await Supabase.initialize(
      url: 'https://fake.supabase.co',
      publishableKey: 'fake-anon-key',
      httpClient: MockClient((request) => Future.sync(() => handler(request))),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _InMemoryAsyncStorage(),
      ),
    );
    // Sets currentUser with no network call: the access token isn't a real
    // JWT, so gotrue's expiry check (which decodes one) fails to parse,
    // treats it as non-expiring, and saves the session locally — see
    // `Session.isExpired`/`_expiresAt` in package:gotrue.
    await supabase.auth.recoverSession(
      jsonEncode({
        'access_token': 'fake-access-token',
        'token_type': 'bearer',
        'refresh_token': 'fake-refresh-token',
        'user': {'id': 'test-user-1'},
      }),
    );
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await Hive.box<Map<String, dynamic>>('fake_sync_rows').clear();
    await Hive.box<OutboxEntry>(outboxBoxName).clear();
  });

  // postgrest-dart's response parsing reads `response.request` (for the
  // HTTP method), which `MockClient` only sets if the response we hand
  // back already carries it — otherwise a plain null-check crash gets
  // miscategorized by `upsertWithConflictCheck` as a network failure,
  // masking whatever status/body was actually meant to be tested.
  http.Response rowsResponse(
    http.Request request,
    List<Map<String, dynamic>> rows, {
    int status = 200,
  }) =>
      http.Response(
        jsonEncode(rows),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );

  http.Response errorResponse(
    http.Request request,
    Map<String, dynamic> body,
    int status,
  ) =>
      http.Response(
        jsonEncode(body),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );

  test(
    'network failure leaves the write pending; a later replay that '
    'reaches the server clears it',
    () async {
      var calls = 0;
      handler = (request) async {
        calls++;
        if (calls == 1) {
          // What `upsertWithConflictCheck` sees for an unreachable server.
          throw const SocketException('network unreachable');
        }
        return rowsResponse(request, [
          {
            'id': 'row-net',
            'title': 'came back online',
            'updated_at': '2026-10-11T00:00:00Z',
          },
        ], status: 201);
      };

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(_fakeRowProvider.notifier);

      final first = await notifier.upsertWithConflictCheck(
        'row-net',
        {'id': 'row-net', 'title': 'came back online'},
      );
      expect(first.outcome, UpsertOutcome.networkFailure);
      expect(calls, 1);

      // This is what TasksNotifier/ProjectsNotifier's `_mirrorUpsert` does
      // on this same outcome.
      notifier.enqueueOutbox('row-net', {'id': 'row-net', 'title': 'came back online'});
      final outbox = Hive.box<OutboxEntry>(outboxBoxName);
      expect(outbox.get('tasks:row-net'), isNotNull);

      await notifier.replayOutbox();
      expect(calls, 2);
      expect(outbox.get('tasks:row-net'), isNull); // cleared on success
      expect(
        Hive.box<Map<String, dynamic>>('fake_sync_rows').get('row-net')?['title'],
        'came back online',
      );
    },
  );

  test(
    'an update RLS silently refuses (row still at the base version) is '
    'rejected, not reported as changed elsewhere',
    () async {
      handler = (request) async {
        // PATCH matched no row; the follow-up read shows it untouched.
        if (request.method == 'PATCH') return rowsResponse(request, []);
        return rowsResponse(request, [
          {
            'id': 'row-ro',
            'title': 'theirs',
            'updated_at': '2026-10-11T00:00:00Z',
          },
        ]);
      };

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(_fakeRowProvider.notifier);

      final result = await notifier.upsertWithConflictCheck(
        'row-ro',
        {'id': 'row-ro', 'title': 'mine'},
        baseUpdatedAt: DateTime.parse('2026-10-11T00:00:00Z'),
      );
      expect(result.outcome, UpsertOutcome.rejected);
    },
  );

  test(
    '403/RLS rejection marks the outbox entry failed and it is never '
    'retried automatically',
    () async {
      var calls = 0;
      handler = (request) async {
        calls++;
        return errorResponse(request, {
          'message': 'new row violates row-level security policy',
          'code': '42501',
        }, 403);
      };

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(_fakeRowProvider.notifier);

      final result = await notifier.upsertWithConflictCheck(
        'row-rls',
        {'id': 'row-rls', 'title': 'not allowed'},
      );
      expect(result.outcome, UpsertOutcome.rejected);
      expect(result.error, isA<PostgrestException>());
      expect(calls, 1);

      // Queue it (as `_mirrorUpsert` would have on the first, synchronous
      // attempt failing this same way) and replay it.
      notifier.enqueueOutbox('row-rls', {'id': 'row-rls', 'title': 'not allowed'});
      await notifier.replayOutbox();

      final outbox = Hive.box<OutboxEntry>(outboxBoxName);
      final entry = outbox.get('tasks:row-rls');
      expect(entry, isNotNull);
      expect(entry!.failed, isTrue);
      expect(entry.lastError, contains('row-level security'));

      // A second replay must not call the server again for a failed entry.
      final callsBeforeSecondReplay = calls;
      await notifier.replayOutbox();
      expect(calls, callsBeforeSecondReplay);
    },
  );
}
