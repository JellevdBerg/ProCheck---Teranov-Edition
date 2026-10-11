import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_config.dart';
import '../models/outbox_entry.dart';
import '../providers/outbox_provider.dart';
import '../providers/projects_provider.dart';
import '../providers/sync_log_provider.dart';
import '../providers/tasks_provider.dart';
import 'blurred_dialog.dart';

/// Small Synced/N pending/Sync failed readout for the app shell (see Phase
/// 3 spec item 6) — tapping it opens a details list of what hasn't reached
/// Supabase yet, with a Retry action for anything the server refused.
/// Nothing to show in local-only mode, so it renders nothing then.
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isSupabaseConfigured) return const SizedBox.shrink();
    final pending = ref.watch(outboxPendingCountProvider);
    final failed = ref.watch(outboxFailedCountProvider);

    final (icon, label, color) = failed > 0
        ? (Icons.sync_problem, 'Sync failed', Colors.redAccent)
        : pending > 0
            ? (Icons.sync, '$pending pending', Colors.amber)
            : (Icons.cloud_done_outlined, 'Synced', Colors.greenAccent);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _showDetails(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, WidgetRef ref) {
    showBlurredDialog<void>(
      context: context,
      builder: (context) => const _SyncDetailsDialog(),
    );
  }
}

class _SyncDetailsDialog extends ConsumerWidget {
  const _SyncDetailsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(outboxEntriesProvider).valueOrNull ?? const [];
    final syncLog = ref.watch(syncLogProvider);

    return AlertDialog(
      title: const Text('Sync status'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              syncLog.lastSyncAt == null
                  ? 'Never synced yet.'
                  : 'Last synced ${syncLog.lastSyncAt!.toLocal()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              const Text('Nothing waiting — everything is shared.')
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _OutboxEntryRow(entry: entry);
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// A small "not shared yet" dot shown next to a task/project row that has
/// an entry in the outbox — renders nothing once that row is no longer
/// pending. [table] is `'tasks'` or `'projects'`, matching [OutboxEntry.table].
class PendingSyncMark extends ConsumerWidget {
  const PendingSyncMark({super.key, required this.table, required this.rowId});

  final String table;
  final String rowId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(outboxEntriesProvider).valueOrNull ?? const [];
    final entry = entries
        .where((e) => e.table == table && e.rowId == rowId)
        .firstOrNull;
    if (entry == null) return const SizedBox.shrink();
    return Tooltip(
      message: entry.failed
          ? 'Not shared yet — ${entry.lastError ?? 'rejected'}'
          : 'Not shared yet — waiting to sync',
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(
          Icons.cloud_off,
          size: 12,
          color: entry.failed ? Colors.redAccent : Colors.amber,
        ),
      ),
    );
  }
}

class _OutboxEntryRow extends ConsumerWidget {
  const _OutboxEntryRow({required this.entry});

  final OutboxEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemLabel = entry.payload?['title'] as String? ??
        entry.payload?['name'] as String? ??
        entry.rowId;
    final category = entry.failed
        ? 'failed: ${entry.lastError ?? 'rejected'}'
        : entry.attempts > 0
            ? 'offline, retrying (attempt ${entry.attempts})'
            : 'pending';

    return ListTile(
      dense: true,
      leading: Icon(
        entry.failed ? Icons.error_outline : Icons.schedule,
        size: 18,
        color: entry.failed ? Colors.redAccent : Colors.amber,
      ),
      title: Text(itemLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${entry.table} · ${entry.op.name} · $category · '
        'queued ${entry.queuedAt.toLocal()}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: entry.failed
          ? TextButton(
              onPressed: () => _retry(ref),
              child: const Text('Retry'),
            )
          : null,
    );
  }

  Future<void> _retry(WidgetRef ref) {
    if (entry.table == 'tasks') {
      return ref.read(tasksProvider.notifier).retryOutboxEntry(entry.rowId);
    }
    return ref.read(projectsProvider.notifier).retryOutboxEntry(entry.rowId);
  }
}
