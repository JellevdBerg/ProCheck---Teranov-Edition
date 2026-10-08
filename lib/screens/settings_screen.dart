import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup_service.dart';
import '../data/test_data_seed.dart';
import '../models/shortcut_binding.dart';
import '../models/task_priority.dart';
import '../providers/projects_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_templates_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/color_spectrum_picker.dart';
import '../widgets/industrial/industrial_panel.dart';
import '../widgets/industrial/screw_dot.dart';
import '../widgets/nocturne/nocturne_widgets.dart';
import '../widgets/text_prompt_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 22.4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 300).floor().clamp(1, 3);
                return SingleChildScrollView(
                  key: const Key('settings-scroll'),
                  child: Wrap(
                    spacing: 22.4,
                    runSpacing: 22.4,
                    children: [
                      SizedBox(
                        width: (constraints.maxWidth - 22.4 * (columns - 1)) /
                            columns,
                        child: const _AppearanceCard(),
                      ),
                      SizedBox(
                        width: (constraints.maxWidth - 22.4 * (columns - 1)) /
                            columns,
                        child: const _TaskDefaultsCard(),
                      ),
                      SizedBox(
                        width: (constraints.maxWidth - 22.4 * (columns - 1)) /
                            columns,
                        child: const _BackupCard(),
                      ),
                      SizedBox(
                        width: (constraints.maxWidth - 22.4 * (columns - 1)) /
                            columns,
                        child: const _ShortcutsCard(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return IndustrialPanel(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(child: _CardTitle('Appearance')),
                ScrewDot(),
                SizedBox(width: 10),
                ScrewDot(),
              ],
            ),
            const NocturneSectionLabel('THEME', padding: EdgeInsets.only(bottom: 8)),
            RadioGroup<ThemeMode>(
              groupValue: settings.themeMode,
              onChanged: (mode) => notifier.setThemeMode(mode!),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<ThemeMode>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('Match system'),
                    value: ThemeMode.system,
                  ),
                  RadioListTile<ThemeMode>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('Light'),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('Dark'),
                    value: ThemeMode.dark,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16.8),
            Text('Accent color', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8.4),
            Wrap(
              spacing: 10,
              runSpacing: 12,
              children: [
                for (var i = 0; i < accentPalette.length; i++)
                  _AccentSwatch(
                    color: accentPalette[i],
                    selected:
                        settings.customAccentValue == null &&
                        settings.accentIndex == i,
                    onTap: () => notifier.setAccentIndex(i),
                  ),
                _CustomAccentSwatch(
                  selected: settings.customAccentValue != null,
                  color: settings.customAccentValue != null
                      ? Color(settings.customAccentValue!)
                      : null,
                  onPicked: notifier.setCustomAccentColor,
                ),
              ],
            ),
            const SizedBox(height: 16.8),
            const NocturneSectionLabel('MOTION', padding: EdgeInsets.only(bottom: 8)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reduce motion'),
              subtitle: const Text(
                'Quick fades instead of sliding/scaling animations',
              ),
              value: settings.reduceMotion,
              onChanged: notifier.setReduceMotion,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2)
              : null,
        ),
        child: selected
            ? Icon(Icons.check, color: _onSwatch(color), size: 14)
            : null,
      ),
    );
  }
}

/// Checkmark color for a swatch of [background] — white reads on a dark
/// swatch, black on a light one. The accent palette (and any custom color a
/// user picks) skews pastel/light, where a hardcoded white checkmark all but
/// disappears.
Color _onSwatch(Color background) =>
    background.computeLuminance() > 0.5 ? Colors.black : Colors.white;

class _CustomAccentSwatch extends StatelessWidget {
  const _CustomAccentSwatch({
    required this.selected,
    required this.color,
    required this.onPicked,
  });

  final bool selected;
  final Color? color;
  final ValueChanged<Color> onPicked;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showCustomColorDialog(context, color ?? Colors.purple);
        if (picked != null) onPicked(picked);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: color == null
              ? const SweepGradient(
                  colors: [
                    Color(0xFFFF5C5C),
                    Color(0xFFFFC93C),
                    Color(0xFF3DDC84),
                    Color(0xFF6A95D6),
                    Color(0xFFB07FD6),
                    Color(0xFFFF5C5C),
                  ],
                )
              : null,
          color: color,
          border: selected
              ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2)
              : Border.all(color: Theme.of(context).dividerColor),
        ),
        child: selected && color != null
            ? Icon(Icons.check, color: _onSwatch(color!), size: 14)
            : null,
      ),
    );
  }
}

class _TaskDefaultsCard extends ConsumerWidget {
  const _TaskDefaultsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return IndustrialPanel(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('Task defaults'),
            Text('Default priority', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8.4),
            NocturneSegmented<TaskPriority>(
              options: TaskPriority.values,
              value: settings.defaultPriority,
              labelBuilder: (p) => p.label,
              onChanged: notifier.setDefaultPriority,
            ),
            const SizedBox(height: 16.8),
            Text('Date format', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            RadioGroup<DateFormatOption>(
              groupValue: settings.dateFormat,
              onChanged: (v) => notifier.setDateFormat(v!),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final option in DateFormatOption.values)
                    RadioListTile<DateFormatOption>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(option.label),
                      value: option,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16.8),
            Text(
              'Default landing screen',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8.4),
            NocturneSegmented<LandingScreenOption>(
              options: LandingScreenOption.values,
              value: settings.defaultLanding,
              labelBuilder: (o) => o.label,
              onChanged: notifier.setDefaultLanding,
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupCard extends ConsumerWidget {
  const _BackupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IndustrialPanel(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('Backup & danger zone'),
            const NocturneSectionLabel(
              'BACKUP & RESTORE',
              padding: EdgeInsets.only(bottom: 8),
            ),
            NocturneButton(
              label: 'Export backup',
              icon: Icons.upload_file_outlined,
              onPressed: () => _exportBackup(context, ref),
            ),
            const SizedBox(height: 8),
            NocturneButton(
              label: 'Import backup',
              icon: Icons.download_outlined,
              onPressed: () => _importBackup(context, ref),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 16.8),
              const NocturneSectionLabel(
                'TESTING',
                padding: EdgeInsets.only(bottom: 8),
              ),
              NocturneButton(
                label: 'Load test data',
                icon: Icons.science_outlined,
                onPressed: () => _confirmLoadTestData(context, ref),
              ),
            ],
            const SizedBox(height: 16.8),
            const NocturneSectionLabel(
              'DANGER ZONE',
              padding: EdgeInsets.only(bottom: 8),
            ),
            NocturneButton(
              label: 'Wipe all data',
              icon: Icons.delete_outline,
              color: NocturneStatus.dangerBorder,
              onPressed: () => _confirmWipe(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final json = buildBackupJson(
      projects: ref.read(projectsProvider.notifier).allValues,
      tasks: ref.read(tasksProvider.notifier).allValues,
      taskTemplates: ref.read(taskTemplatesProvider.notifier).allValues,
      settings: ref.read(settingsProvider),
    );
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
    );
    final fileName = suggestedBackupFileName();

    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Export ProCheck backup',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    if (savedPath == null) return;

    if (!kIsWeb) {
      await File(savedPath).writeAsBytes(bytes);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb ? 'Backup downloaded.' : 'Backup saved to $savedPath',
          ),
        ),
      );
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import ProCheck backup',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.single.bytes;
    if (bytes == null) {
      if (context.mounted) _showImportError(context, "Couldn't read that file.");
      return;
    }

    final BackupData data;
    try {
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      data = parseBackupJson(decoded);
    } catch (e) {
      if (context.mounted) {
        _showImportError(
          context,
          e is BackupFormatException
              ? e.message
              : "This file isn't a valid ProCheck backup.",
        );
      }
      return;
    }

    if (!context.mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Import backup?',
      message:
          'This replaces everything currently in ProCheck with the backup: '
          '${data.projects.length} project(s), ${data.tasks.length} task(s), '
          'and ${data.taskTemplates.length} template(s). This cannot be undone.',
      confirmLabel: 'Import',
    );
    if (!confirmed) return;

    ref.read(settingsProvider.notifier).restoreAll(data.settings);
    ref.read(projectsProvider.notifier).restoreAll(data.projects);
    ref.read(tasksProvider.notifier).restoreAll(data.tasks);
    ref.read(taskTemplatesProvider.notifier).restoreAll(data.taskTemplates);

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backup imported.')));
    }
  }

  void _showImportError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _confirmLoadTestData(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Load test data?',
      message:
          'This replaces every project and task currently in ProCheck with '
          'a small dataset for testing (projects, subtasks, due dates, a '
          'multi-day task, completed items, and an archived project). This '
          'cannot be undone.',
      confirmLabel: 'Load test data',
    );
    if (!confirmed) return;

    final data = buildTestData();
    ref.read(projectsProvider.notifier).restoreAll(data.projects);
    ref.read(tasksProvider.notifier).restoreAll(data.tasks);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test data loaded.')),
      );
    }
  }

  Future<void> _confirmWipe(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Wipe all data?',
      message:
          'This permanently deletes every project, task, subtask, and '
          'template, and resets settings to their defaults. This cannot '
          'be undone.',
      confirmLabel: 'Wipe everything',
    );
    if (!confirmed) return;

    ref.read(projectsProvider.notifier).clearAll();
    ref.read(tasksProvider.notifier).clearAll();
    ref.read(taskTemplatesProvider.notifier).clearAll();
    ref.read(settingsProvider.notifier).resetToDefaults();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All ProCheck data has been wiped.')),
      );
    }
  }
}

class _ShortcutsCard extends ConsumerWidget {
  const _ShortcutsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return IndustrialPanel(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('Keyboard shortcuts'),
            for (final action in ShortcutAction.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        action.label,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      settings.shortcutFor(action).displayLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (settings.shortcutOverrides.containsKey(action))
                      IconButton(
                        tooltip: 'Reset to default',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.restore, size: 16),
                        onPressed: () => notifier.resetShortcutBinding(action),
                      )
                    else
                      const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _rebind(context, ref, action),
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _rebind(
    BuildContext context,
    WidgetRef ref,
    ShortcutAction action,
  ) async {
    final binding = await _recordShortcut(context);
    if (binding == null) return;

    final settings = ref.read(settingsProvider);
    for (final other in ShortcutAction.values) {
      if (other == action) continue;
      if (settings.shortcutFor(other).sameCombo(binding)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${binding.displayLabel} is already used by '
                '"${other.label}". Pick a different combination.',
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
    }

    ref.read(settingsProvider.notifier).setShortcutBinding(action, binding);
  }
}

final _modifierKeys = {
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
};

Future<ShortcutBinding?> _recordShortcut(BuildContext context) {
  return showDialog<ShortcutBinding>(
    context: context,
    builder: (context) => const _ShortcutRecorderDialog(),
  );
}

/// A small dialog that listens for the next non-modifier key press (while a
/// modifier is held) and resolves with the [ShortcutBinding] it forms, so
/// rebinding is "press the combo you want" rather than picking from menus.
class _ShortcutRecorderDialog extends StatefulWidget {
  const _ShortcutRecorderDialog();

  @override
  State<_ShortcutRecorderDialog> createState() =>
      _ShortcutRecorderDialogState();
}

class _ShortcutRecorderDialogState extends State<_ShortcutRecorderDialog> {
  final _focusNode = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (_modifierKeys.contains(key)) return KeyEventResult.handled;

    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final cmdOrCtrl =
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
    final alt =
        pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight);
    final shift =
        pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);

    if (!cmdOrCtrl && !alt) {
      setState(
        () => _error =
            "Hold Ctrl/Cmd or Alt too, so this won't collide with typing.",
      );
      return KeyEventResult.handled;
    }

    Navigator.of(
      context,
    ).pop(ShortcutBinding(key: key, cmdOrCtrl: cmdOrCtrl, shift: shift, alt: alt));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Press a new shortcut'),
      content: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKey,
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Hold a modifier (Ctrl/Cmd or Alt) and press a key.'),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
