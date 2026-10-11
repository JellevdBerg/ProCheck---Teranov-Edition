import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/update_check_provider.dart';
import '../theme/nocturne_theme.dart';

/// A dismissible banner pinned to the top of the main content area when a
/// newer release is available on GitHub. Checked once per session; a
/// dismissal lasts until the app is relaunched.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(updateBannerDismissedProvider);
    final update = ref.watch(updateCheckProvider).valueOrNull;
    if (dismissed || update == null) return const SizedBox.shrink();

    final t = context.nocturne;
    return Material(
      color: t.isDark ? t.neutral800 : t.neutral100,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.system_update_outlined, size: 18, color: context.nocturneAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'ProCheck ${update.version} is available.'
                '${update.releaseNotes.isNotEmpty ? ' ${_firstLine(update.releaseNotes)}' : ''}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.isDark ? t.text : t.surface),
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(update.releaseUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Download'),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () =>
                  ref.read(updateBannerDismissedProvider.notifier).state = true,
            ),
          ],
        ),
      ),
    );
  }
}

String _firstLine(String text) => text.split('\n').first.trim();
