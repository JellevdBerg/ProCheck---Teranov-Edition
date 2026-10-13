import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/update_installer.dart';
import '../providers/update_check_provider.dart';
import '../theme/nocturne_theme.dart';

/// A dismissible banner pinned to the top of the main content area when a
/// newer release is available on GitHub. Checked once per session; a
/// dismissal lasts until the app is relaunched. "Update and restart"
/// downloads, verifies and installs the new build, then relaunches.
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
              onPressed: () => _updateNow(context, update),
              child: const Text('Update and restart'),
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

Future<void> _updateNow(BuildContext context, UpdateInfo update) async {
  final progress = ValueNotifier<double?>(null);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('Updating to ${update.version}'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: value),
              const SizedBox(height: 12),
              const Text('ProCheck will restart when the update is installed.'),
            ],
          ),
        ),
      ),
    ),
  );
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    // Exits the process on success; only returns by throwing.
    await installUpdate(update, onProgress: (p) => progress.value = p);
  } on UpdateUnsupported catch (e) {
    navigator.pop();
    final download = update.assetUrl;
    messenger?.showSnackBar(SnackBar(
      content: Text(download == null ? '$e' : '$e Downloading it instead.'),
    ));
    if (download != null) {
      await launchUrl(Uri.parse(download), mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    navigator.pop();
    messenger?.showSnackBar(
      const SnackBar(content: Text("Couldn't download the update. Try again later.")),
    );
  }
}

String _firstLine(String text) => text.split('\n').first.trim();
