import 'package:flutter/material.dart';

import '../providers/settings_provider.dart';
import 'blurred_dialog.dart';
import 'motion_widgets.dart';
import 'nocturne/nocturne_widgets.dart';

/// A simple dialog that prompts for a single line of text.
/// Returns the trimmed text, or null if cancelled / left empty.
Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  String? initialValue,
  String confirmLabel = 'Save',
}) {
  final controller = TextEditingController(text: initialValue);
  final nudge = GlobalKey<NudgeState>();
  void submit(BuildContext context) {
    final trimmed = controller.text.trim();
    trimmed.isEmpty
        ? nudge.currentState?.nudge()
        : Navigator.of(context).pop(trimmed);
  }

  return showBlurredDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Nudge(
        key: nudge,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(),
          onSubmitted: (_) => submit(context),
        ),
      ),
      actions: [
        NocturneButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        NocturneButton(
          label: confirmLabel,
          variant: NocturneButtonVariant.primary,
          onPressed: () => submit(context),
        ),
      ],
    ),
  );
}

/// A dialog that prompts for a project name and an accent color together.
/// Returns the trimmed name and chosen [accentPalette] index, or null if
/// cancelled / left empty.
Future<(String, int)?> showProjectPromptDialog(
  BuildContext context, {
  required String title,
  String? initialValue,
  int initialColorIndex = 0,
  String confirmLabel = 'Save',
}) {
  final controller = TextEditingController(text: initialValue);
  var selectedColor = initialColorIndex;
  final nudge = GlobalKey<NudgeState>();
  return showBlurredDialog<(String, int)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Nudge(
              key: nudge,
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < accentPalette.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => selectedColor = i),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: accentPalette[i],
                      child: selectedColor == i
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          NocturneButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          NocturneButton(
            label: confirmLabel,
            variant: NocturneButtonVariant.primary,
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) {
                Navigator.of(context).pop((trimmed, selectedColor));
              } else {
                nudge.currentState?.nudge();
              }
            },
          ),
        ],
      ),
    ),
  );
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final result = await showBlurredDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        NocturneButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        NocturneButton(
          label: confirmLabel,
          variant: NocturneButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}
