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
import '../providers/auth_provider.dart';
import '../providers/projects_provider.dart';
import '../providers/app_info_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_templates_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/update_check_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/color_spectrum_picker.dart';
import '../widgets/nocturne/nocturne_widgets.dart';
import '../widgets/panel/panel.dart';
import '../widgets/text_prompt_dialog.dart';
import '../widgets/wobble_checkbox.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = constraints.maxWidth < NocturneBreakpoints.compact
            ? NocturneSpace.s4
            : NocturneSpace.s6;
        return Padding(
          padding: EdgeInsets.all(gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: NocturneSpace.s4),
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('settings-scroll'),
                  child: Align(
                    alignment: Alignment.topLeft,
                    // Settings read best as one capped column of cards.
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: double.infinity),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _AppearanceCard(),
                          SizedBox(height: NocturneSpace.s4),
                          _AccountCard(),
                          SizedBox(height: NocturneSpace.s4),
                          _TaskDefaultsCard(),
                          SizedBox(height: NocturneSpace.s4),
                          _ShortcutsCard(),
                          SizedBox(height: NocturneSpace.s4),
                          _BackupCard(),
                          SizedBox(height: NocturneSpace.s4),
                          _AboutCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Company edition only: there's no self-service password change in the
/// UI anywhere (accounts are admin/manager-provisioned, matching the
/// no-self-signup philosophy — see supabase/README.md) — this says so
/// explicitly rather than leaving it looking like a missing feature.
class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(signedInProvider)) return const SizedBox.shrink();
    return const _SettingsSection(
      title: 'Account',
      children: [
        _SettingRow(
          label: 'Password',
          help:
              "Password changes are handled by your department's manager.",
          control: SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.watch(packageInfoProvider).valueOrNull;
    final checking = ref.watch(updateCheckProvider).isLoading;

    return _SettingsSection(
      title: 'About',
      children: [
        _SettingRow(
          label: 'Version',
          help: packageInfo != null
              ? '${packageInfo.version} (build ${packageInfo.buildNumber})'
              : null,
          control: NocturneButton(
            label: checking ? 'Checking…' : 'Check for updates',
            icon: Icons.system_update_outlined,
            onPressed: checking ? null : () => _checkNow(context, ref),
          ),
        ),
      ],
    );
  }

  Future<void> _checkNow(BuildContext context, WidgetRef ref) async {
    ref.read(updateBannerDismissedProvider.notifier).state = false;
    String message;
    try {
      final update = await ref.refresh(updateCheckProvider.future);
      message = update != null
          ? 'ProCheck ${update.version} is available — see the banner above.'
          : "You're on the latest version.";
    } catch (_) {
      message = "Couldn't check for updates right now.";
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

/// A titled card of setting rows separated by hairlines.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
    this.danger = false,
  });

  final String title;
  final List<Widget> children;

  /// Outlines the card in the danger colour (the wipe-everything section).
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: NocturneSpace.s2),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: danger ? t.danger : null,
            ),
          ),
        ),
        DecoratedBox(
          decoration: panelDecoration(context).copyWith(
            border: Border.all(
              color: danger ? t.danger.withValues(alpha: 0.5) : t.edge,
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One setting: label + help text, control beside it when there is room and
/// under it when there is not (or when [stacked], for tall controls).
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.control,
    this.help,
    this.stacked = false,
  });

  final String label;
  final String? help;
  final Widget control;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        if (help != null) _Hint(help!),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NocturneSpace.s4,
        vertical: NocturneSpace.s3,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (stacked || constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: NocturneSpace.s2),
                Align(alignment: Alignment.centerLeft, child: control),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: text),
              const SizedBox(width: NocturneSpace.s4),
              Flexible(
                child: Align(alignment: Alignment.centerRight, child: control),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One mutually-exclusive option as a bordered row; the selected one gets an
/// accent outline and tint. Still a real [RadioListTile] underneath, so the
/// surrounding [RadioGroup] drives selection, keyboard and semantics exactly
/// as before. Wrapped in a [Material] (not a filled DecoratedBox) so the
/// tile's ink and background stay valid.
class _RadioKey<T> extends StatelessWidget {
  const _RadioKey({
    required this.value,
    required this.selected,
    required this.label,
  });

  final T value;
  final bool selected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    final accent = context.nocturneAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: NocturneSpace.s1),
      child: Material(
        color: selected
            ? accent.withValues(alpha: t.isDark ? 0.14 : 0.08)
            : t.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NocturneRadius.md),
          side: BorderSide(color: selected ? accent : t.edge),
        ),
        child: RadioListTile<T>(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: NocturneSpace.s3,
          ),
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(label),
          value: value,
          selected: selected,
        ),
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

    return _SettingsSection(
      title: 'Appearance',
      children: [
        _SettingRow(
          label: 'Theme',
          stacked: true,
          control: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: RadioGroup<ThemeMode>(
              groupValue: settings.themeMode,
              onChanged: (mode) => notifier.setThemeMode(mode!),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RadioKey<ThemeMode>(
                    label: 'Match system',
                    value: ThemeMode.system,
                    selected: settings.themeMode == ThemeMode.system,
                  ),
                  _RadioKey<ThemeMode>(
                    label: 'Light',
                    value: ThemeMode.light,
                    selected: settings.themeMode == ThemeMode.light,
                  ),
                  _RadioKey<ThemeMode>(
                    label: 'Dark',
                    value: ThemeMode.dark,
                    selected: settings.themeMode == ThemeMode.dark,
                  ),
                ],
              ),
            ),
          ),
        ),
        _SettingRow(
          label: 'Accent color',
          stacked: true,
          control: Wrap(
            spacing: NocturneSpace.s2,
            runSpacing: NocturneSpace.s2,
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
        ),
        _SettingRow(
          label: 'Reduce motion',
          help: 'Quick fades instead of sliding/scaling animations',
          control: WobbleCheckbox(
            value: settings.reduceMotion,
            reduceMotion: settings.reduceMotion,
            onChanged: (v) => notifier.setReduceMotion(v ?? false),
          ),
        ),
        _SettingRow(
          label: 'Compact rows',
          help: 'Fit more tasks on screen',
          control: Switch(
            value: settings.compactRows,
            onChanged: notifier.setCompactRows,
          ),
        ),
      ],
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
    return _SwatchWell(
      selected: selected,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: selected
            ? Icon(Icons.check, color: _onSwatch(color), size: 14)
            : null,
      ),
    );
  }
}

/// A swatch inside a ring; the selected one gets a strong ring (plus its
/// check mark, so it never depends on colour alone).
class _SwatchWell extends StatelessWidget {
  const _SwatchWell({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        padding: const EdgeInsets.all(NocturneSpace.s1),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? t.text : t.edge,
            width: selected ? 2 : 1,
          ),
        ),
        child: child,
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
    return _SwatchWell(
      selected: selected,
      onTap: () async {
        final picked = await showCustomColorDialog(
          context,
          color ?? Colors.purple,
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // An unset custom swatch shows the hue wheel it opens.
          gradient: color == null
              ? const SweepGradient(
                  colors: [
                    Color(0xFFE5484D),
                    Color(0xFFF0B04A),
                    Color(0xFF4CC38A),
                    Color(0xFF2D8CF0),
                    Color(0xFF8B5CF6),
                    Color(0xFFE5484D),
                  ],
                )
              : null,
          color: color,
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

    return _SettingsSection(
      title: 'Task defaults',
      children: [
        _SettingRow(
          label: 'Default priority',
          control: NocturneSegmented<TaskPriority>(
            options: TaskPriority.values,
            value: settings.defaultPriority,
            labelBuilder: (p) => p.label,
            onChanged: notifier.setDefaultPriority,
          ),
        ),
        _SettingRow(
          label: 'Date format',
          stacked: true,
          control: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: RadioGroup<DateFormatOption>(
              groupValue: settings.dateFormat,
              onChanged: (v) => notifier.setDateFormat(v!),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final option in DateFormatOption.values)
                    _RadioKey<DateFormatOption>(
                      label: option.label,
                      value: option,
                      selected: settings.dateFormat == option,
                    ),
                ],
              ),
            ),
          ),
        ),
        _SettingRow(
          label: 'Default landing screen',
          control: NocturneSegmented<LandingScreenOption>(
            options: LandingScreenOption.values,
            value: settings.defaultLanding,
            labelBuilder: (o) => o.label,
            onChanged: notifier.setDefaultLanding,
          ),
        ),
      ],
    );
  }
}

class _BackupCard extends ConsumerWidget {
  const _BackupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsSection(
          title: 'Backup & restore',
          children: [
            _SettingRow(
              label: 'Back up your data',
              help: 'Save all projects, tasks, templates and settings to a file',
              control: NocturneButton(
                label: 'Export backup',
                icon: Icons.upload_file_outlined,
                onPressed: () => _exportBackup(context, ref),
              ),
            ),
            _SettingRow(
              label: 'Restore from a backup',
              help: 'Replace everything with the contents of a backup file',
              control: NocturneButton(
                label: 'Import backup',
                icon: Icons.download_outlined,
                onPressed: () => _importBackup(context, ref),
              ),
            ),
            if (kDebugMode)
              _SettingRow(
                label: 'Test data',
                help: 'Replace projects and tasks with a small test dataset',
                control: NocturneButton(
                  label: 'Load test data',
                  icon: Icons.science_outlined,
                  onPressed: () => _confirmLoadTestData(context, ref),
                ),
              ),
          ],
        ),
        const SizedBox(height: NocturneSpace.s4),
        _SettingsSection(
          title: 'Danger zone',
          danger: true,
          children: [
            _SettingRow(
              label: 'Erase everything',
              help: 'Permanently delete everything and reset settings',
              control: NocturneButton(
                label: 'Wipe all data',
                icon: Icons.delete_outline,
                variant: NocturneButtonVariant.primary,
                color: context.nocturne.danger,
                onPressed: () => _confirmWipe(context, ref),
              ),
            ),
          ],
        ),
      ],
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
      if (context.mounted) {
        _showImportError(context, "Couldn't read that file.");
      }
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Backup imported.')));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Test data loaded.')));
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
    final t = context.nocturne;

    return _SettingsSection(
      title: 'Keyboard shortcuts',
      children: [
        for (final action in ShortcutAction.values)
          _SettingRow(
            label: action.label,
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: panelDecoration(
                    context,
                    depth: PanelDepth.recessed,
                    radius: NocturneRadius.sm,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NocturneSpace.s2,
                      vertical: NocturneSpace.s1,
                    ),
                    child: Text(
                      settings.shortcutFor(action).displayLabel,
                      style: TextStyle(fontSize: 12, color: t.neutral200),
                    ),
                  ),
                ),
                if (settings.shortcutOverrides.containsKey(action))
                  IconButton(
                    tooltip: 'Reset to default',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.restore, size: 16),
                    onPressed: () => notifier.resetShortcutBinding(action),
                  )
                else
                  const SizedBox(width: NocturneSpace.s2),
                NocturneButton(
                  label: 'Change',
                  dense: true,
                  variant: NocturneButtonVariant.ghost,
                  onPressed: () => _rebind(context, ref, action),
                ),
              ],
            ),
          ),
      ],
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

    Navigator.of(context).pop(
      ShortcutBinding(key: key, cmdOrCtrl: cmdOrCtrl, shift: shift, alt: alt),
    );
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
              DecoratedBox(
                decoration: panelDecoration(
                  context,
                  depth: PanelDepth.recessed,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(NocturneSpace.s3),
                  child: Text(
                    'Hold a modifier (Ctrl/Cmd or Alt) and press a key.',
                  ),
                ),
              ),
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
        NocturneButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Dim helper text under a control label.
class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 12, color: context.nocturne.neutral500),
    );
  }
}
