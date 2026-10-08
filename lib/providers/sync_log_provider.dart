import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A rolling record of Supabase sync activity, for the Operator-only
/// developer panel — not shown anywhere else. Every pull/mirror write in
/// [TasksNotifier]/[ProjectsNotifier] already fails silently by design
/// (a flaky connection or an RLS rejection shouldn't block the UI), which
/// also meant there was nowhere to see that it happened. This doesn't
/// change that behavior, it just gives the silent catch blocks somewhere
/// to report to.
final syncLogProvider = StateNotifierProvider<SyncLogNotifier, SyncLogState>(
  (ref) => SyncLogNotifier(),
);

class SyncLogState {
  const SyncLogState({this.lastSyncAt, this.entries = const []});

  final DateTime? lastSyncAt;
  final List<SyncLogEntry> entries;

  SyncLogState copyWith({DateTime? lastSyncAt, List<SyncLogEntry>? entries}) =>
      SyncLogState(
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        entries: entries ?? this.entries,
      );
}

class SyncLogEntry {
  SyncLogEntry({
    required this.at,
    required this.source,
    required this.action,
    required this.message,
  });

  final DateTime at;

  /// 'tasks' or 'projects'.
  final String source;

  /// 'pull', 'upsert', or 'delete'.
  final String action;
  final String message;
}

class SyncLogNotifier extends StateNotifier<SyncLogState> {
  SyncLogNotifier() : super(const SyncLogState());

  static const _maxEntries = 20;

  void recordSuccessfulPull() {
    state = state.copyWith(lastSyncAt: DateTime.now());
  }

  void recordError({
    required String source,
    required String action,
    required Object error,
  }) {
    final entry = SyncLogEntry(
      at: DateTime.now(),
      source: source,
      action: action,
      message: error.toString(),
    );
    state = state.copyWith(
      entries: [entry, ...state.entries].take(_maxEntries).toList(),
    );
  }
}
