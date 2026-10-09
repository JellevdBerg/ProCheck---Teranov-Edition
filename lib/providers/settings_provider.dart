import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../data/hive_setup.dart';
import '../models/shortcut_binding.dart';
import '../models/task_priority.dart';
import '../theme/nocturne_theme.dart';

/// The 8 preset accent swatches — also doubles as the per-project color
/// palette (`Project.colorIndex` indexes into this same list), matching the
/// design handoff where a project's color and the app's accent draw from
/// one palette.
const List<Color> accentPalette = nocturneAccentPalette;

enum DateFormatOption {
  mdy,
  dmy,
  iso;

  static DateFormatOption fromIndex(int? index) {
    if (index == null || index < 0 || index >= DateFormatOption.values.length) {
      return DateFormatOption.mdy;
    }
    return DateFormatOption.values[index];
  }

  String get label => switch (this) {
    DateFormatOption.mdy => 'MM/DD/YYYY',
    DateFormatOption.dmy => 'DD/MM/YYYY',
    DateFormatOption.iso => 'YYYY-MM-DD',
  };
}

enum LandingScreenOption {
  projects,
  templates,
  lastViewed,
  // Appended, not inserted — this enum's index is what's persisted to disk
  // (see AppSettings.toJson/fromJson), so a new entry has to go last or
  // every existing install's saved preference would silently shift to a
  // different option.
  dashboard;

  static LandingScreenOption fromIndex(int? index) {
    if (index == null ||
        index < 0 ||
        index >= LandingScreenOption.values.length) {
      return LandingScreenOption.projects;
    }
    return LandingScreenOption.values[index];
  }

  String get label => switch (this) {
    LandingScreenOption.projects => 'Projects',
    LandingScreenOption.templates => 'Templates',
    LandingScreenOption.lastViewed => 'Last viewed',
    LandingScreenOption.dashboard => 'Dashboard',
  };
}

class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.accentIndex,
    required this.reduceMotion,
    this.compactRows = false,
    this.customAccentValue,
    this.defaultPriorityIndex = 0,
    this.dateFormat = DateFormatOption.mdy,
    this.defaultLanding = LandingScreenOption.projects,
    this.sidebarExpanded = true,
    this.lastViewedScreenIndex = 0,
    this.shortcutOverrides = const {},
  });

  final ThemeMode themeMode;
  final int accentIndex;
  final bool reduceMotion;

  /// Dense ~32px task rows instead of the comfortable default.
  final bool compactRows;

  /// When set, overrides [accentIndex] — a user-picked custom color from
  /// Settings > Appearance rather than one of the [accentPalette] presets.
  final int? customAccentValue;

  final int defaultPriorityIndex;
  final DateFormatOption dateFormat;
  final LandingScreenOption defaultLanding;

  /// Persisted so the sidebar stays collapsed/expanded across restarts.
  final bool sidebarExpanded;

  /// [AppScreen.index] of whichever screen was showing when the app last
  /// closed — used when [defaultLanding] is [LandingScreenOption.lastViewed].
  final int lastViewedScreenIndex;

  /// User-rebound shortcuts, keyed by action. An action missing here still
  /// uses [ShortcutBinding.defaults].
  final Map<ShortcutAction, ShortcutBinding> shortcutOverrides;

  ShortcutBinding shortcutFor(ShortcutAction action) =>
      shortcutOverrides[action] ?? ShortcutBinding.defaults[action]!;

  Color get accentColor =>
      customAccentValue != null ? Color(customAccentValue!) : accentPalette[accentIndex];

  TaskPriority get defaultPriority => TaskPriority.fromIndex(defaultPriorityIndex);

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? accentIndex,
    bool? reduceMotion,
    bool? compactRows,
    int? customAccentValue,
    bool clearCustomAccent = false,
    int? defaultPriorityIndex,
    DateFormatOption? dateFormat,
    LandingScreenOption? defaultLanding,
    bool? sidebarExpanded,
    int? lastViewedScreenIndex,
    Map<ShortcutAction, ShortcutBinding>? shortcutOverrides,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      accentIndex: accentIndex ?? this.accentIndex,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      compactRows: compactRows ?? this.compactRows,
      customAccentValue: clearCustomAccent
          ? null
          : (customAccentValue ?? this.customAccentValue),
      defaultPriorityIndex: defaultPriorityIndex ?? this.defaultPriorityIndex,
      dateFormat: dateFormat ?? this.dateFormat,
      defaultLanding: defaultLanding ?? this.defaultLanding,
      sidebarExpanded: sidebarExpanded ?? this.sidebarExpanded,
      lastViewedScreenIndex:
          lastViewedScreenIndex ?? this.lastViewedScreenIndex,
      shortcutOverrides: shortcutOverrides ?? this.shortcutOverrides,
    );
  }

  static Map<String, dynamic> _shortcutToJson(ShortcutBinding binding) => {
    'keyId': binding.key.keyId,
    'cmdOrCtrl': binding.cmdOrCtrl,
    'shift': binding.shift,
    'alt': binding.alt,
  };

  static ShortcutBinding? _shortcutFromJson(Map<dynamic, dynamic>? json) {
    if (json == null) return null;
    final keyId = json['keyId'] as int?;
    if (keyId == null) return null;
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    if (key == null) return null;
    return ShortcutBinding(
      key: key,
      cmdOrCtrl: json['cmdOrCtrl'] as bool? ?? false,
      shift: json['shift'] as bool? ?? false,
      alt: json['alt'] as bool? ?? false,
    );
  }

  static Map<String, dynamic> _shortcutOverridesToJson(
    Map<ShortcutAction, ShortcutBinding> overrides,
  ) => {
    for (final entry in overrides.entries)
      entry.key.name: _shortcutToJson(entry.value),
  };

  static Map<ShortcutAction, ShortcutBinding> _shortcutOverridesFromJson(
    Map<dynamic, dynamic>? json,
  ) {
    if (json == null) return const {};
    final result = <ShortcutAction, ShortcutBinding>{};
    for (final action in ShortcutAction.values) {
      final binding = _shortcutFromJson(
        json[action.name] as Map<dynamic, dynamic>?,
      );
      if (binding != null) result[action] = binding;
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.index,
    'accentIndex': accentIndex,
    'reduceMotion': reduceMotion,
    'compactRows': compactRows,
    'customAccentValue': customAccentValue,
    'defaultPriorityIndex': defaultPriorityIndex,
    'dateFormat': dateFormat.index,
    'defaultLanding': defaultLanding.index,
    'sidebarExpanded': sidebarExpanded,
    'lastViewedScreenIndex': lastViewedScreenIndex,
    'shortcutOverrides': _shortcutOverridesToJson(shortcutOverrides),
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final accentIndex = json['accentIndex'] as int? ?? 0;
    return AppSettings(
      themeMode: ThemeMode
          .values[(json['themeMode'] as int?) ?? ThemeMode.system.index],
      accentIndex: accentIndex.clamp(0, accentPalette.length - 1),
      reduceMotion: json['reduceMotion'] as bool? ?? false,
      compactRows: json['compactRows'] as bool? ?? false,
      customAccentValue: json['customAccentValue'] as int?,
      defaultPriorityIndex: json['defaultPriorityIndex'] as int? ?? 0,
      dateFormat: DateFormatOption.fromIndex(json['dateFormat'] as int?),
      defaultLanding: LandingScreenOption.fromIndex(
        json['defaultLanding'] as int?,
      ),
      sidebarExpanded: json['sidebarExpanded'] as bool? ?? true,
      lastViewedScreenIndex: json['lastViewedScreenIndex'] as int? ?? 0,
      shortcutOverrides: _shortcutOverridesFromJson(
        json['shortcutOverrides'] as Map<dynamic, dynamic>?,
      ),
    );
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  return SettingsNotifier();
});

/// Persistence to Hive is fire-and-forget, matching the rest of the app.
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(_load());

  static Box get _box => Hive.box(settingsBoxName);

  static AppSettings _load() {
    final themeModeIndex =
        _box.get('themeMode', defaultValue: ThemeMode.system.index) as int;
    final accentIndex = _box.get('accentIndex', defaultValue: 0) as int;
    final reduceMotion = _box.get('reduceMotion', defaultValue: false) as bool;
    return AppSettings(
      themeMode: ThemeMode.values[themeModeIndex],
      accentIndex: accentIndex.clamp(0, accentPalette.length - 1),
      reduceMotion: reduceMotion,
      compactRows: _box.get('compactRows', defaultValue: false) as bool,
      customAccentValue: _box.get('customAccentValue') as int?,
      defaultPriorityIndex:
          _box.get('defaultPriorityIndex', defaultValue: 0) as int,
      dateFormat: DateFormatOption.fromIndex(
        _box.get('dateFormat') as int?,
      ),
      defaultLanding: LandingScreenOption.fromIndex(
        _box.get('defaultLanding') as int?,
      ),
      sidebarExpanded: _box.get('sidebarExpanded', defaultValue: true) as bool,
      lastViewedScreenIndex:
          _box.get('lastViewedScreenIndex', defaultValue: 0) as int,
      shortcutOverrides: _loadShortcutOverrides(),
    );
  }

  static Map<ShortcutAction, ShortcutBinding> _loadShortcutOverrides() {
    final result = <ShortcutAction, ShortcutBinding>{};
    for (final action in ShortcutAction.values) {
      final keyId = _box.get('shortcut_${action.name}_keyId') as int?;
      if (keyId == null) continue;
      final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
      if (key == null) continue;
      result[action] = ShortcutBinding(
        key: key,
        cmdOrCtrl:
            _box.get('shortcut_${action.name}_cmdOrCtrl', defaultValue: false)
                as bool,
        shift:
            _box.get('shortcut_${action.name}_shift', defaultValue: false)
                as bool,
        alt: _box.get('shortcut_${action.name}_alt', defaultValue: false)
            as bool,
      );
    }
    return result;
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    unawaited(_box.put('themeMode', mode.index));
  }

  void setAccentIndex(int index) {
    state = state.copyWith(accentIndex: index, clearCustomAccent: true);
    unawaited(_box.put('accentIndex', index));
    unawaited(_box.delete('customAccentValue'));
  }

  void setCustomAccentColor(Color color) {
    final value = color.toARGB32();
    state = state.copyWith(customAccentValue: value);
    unawaited(_box.put('customAccentValue', value));
  }

  void setReduceMotion(bool value) {
    state = state.copyWith(reduceMotion: value);
    unawaited(_box.put('reduceMotion', value));
  }

  void setCompactRows(bool value) {
    state = state.copyWith(compactRows: value);
    unawaited(_box.put('compactRows', value));
  }

  void setDefaultPriority(TaskPriority priority) {
    state = state.copyWith(defaultPriorityIndex: priority.index);
    unawaited(_box.put('defaultPriorityIndex', priority.index));
  }

  void setDateFormat(DateFormatOption format) {
    state = state.copyWith(dateFormat: format);
    unawaited(_box.put('dateFormat', format.index));
  }

  void setDefaultLanding(LandingScreenOption option) {
    state = state.copyWith(defaultLanding: option);
    unawaited(_box.put('defaultLanding', option.index));
  }

  void setSidebarExpanded(bool expanded) {
    state = state.copyWith(sidebarExpanded: expanded);
    unawaited(_box.put('sidebarExpanded', expanded));
  }

  /// Rebinds [action] to [binding]. Callers are expected to have already
  /// checked [AppSettings.shortcutOverrides] (via [AppSettings.shortcutFor])
  /// for a duplicate against the app's other shortcuts before calling this —
  /// this method itself doesn't validate, so it can also be used to restore
  /// a backup that (in principle) recorded a conflict.
  void setShortcutBinding(ShortcutAction action, ShortcutBinding binding) {
    state = state.copyWith(
      shortcutOverrides: {...state.shortcutOverrides, action: binding},
    );
    unawaited(_box.put('shortcut_${action.name}_keyId', binding.key.keyId));
    unawaited(
      _box.put('shortcut_${action.name}_cmdOrCtrl', binding.cmdOrCtrl),
    );
    unawaited(_box.put('shortcut_${action.name}_shift', binding.shift));
    unawaited(_box.put('shortcut_${action.name}_alt', binding.alt));
  }

  /// Reverts [action] back to [ShortcutBinding.defaults].
  void resetShortcutBinding(ShortcutAction action) {
    final overrides = {...state.shortcutOverrides}..remove(action);
    state = state.copyWith(shortcutOverrides: overrides);
    unawaited(_box.delete('shortcut_${action.name}_keyId'));
    unawaited(_box.delete('shortcut_${action.name}_cmdOrCtrl'));
    unawaited(_box.delete('shortcut_${action.name}_shift'));
    unawaited(_box.delete('shortcut_${action.name}_alt'));
  }

  /// Records the current screen so a "Last viewed" landing preference can
  /// return to it next launch. Not exposed as user-visible state, so it
  /// updates the box directly without touching [state]/notifying listeners.
  void recordLastViewedScreen(int screenIndex) {
    unawaited(_box.put('lastViewedScreenIndex', screenIndex));
  }

  /// Resets settings to their defaults. Used by Settings > Wipe All Data.
  void resetToDefaults() {
    unawaited(_box.clear());
    state = const AppSettings(
      themeMode: ThemeMode.system,
      accentIndex: 0,
      reduceMotion: false,
    );
  }

  /// Replaces all settings at once. Used when restoring from a backup.
  void restoreAll(AppSettings settings) {
    unawaited(_box.put('themeMode', settings.themeMode.index));
    unawaited(_box.put('accentIndex', settings.accentIndex));
    unawaited(_box.put('reduceMotion', settings.reduceMotion));
    unawaited(_box.put('compactRows', settings.compactRows));
    if (settings.customAccentValue != null) {
      unawaited(_box.put('customAccentValue', settings.customAccentValue));
    } else {
      unawaited(_box.delete('customAccentValue'));
    }
    unawaited(
      _box.put('defaultPriorityIndex', settings.defaultPriorityIndex),
    );
    unawaited(_box.put('dateFormat', settings.dateFormat.index));
    unawaited(_box.put('defaultLanding', settings.defaultLanding.index));
    unawaited(_box.put('sidebarExpanded', settings.sidebarExpanded));
    unawaited(
      _box.put('lastViewedScreenIndex', settings.lastViewedScreenIndex),
    );
    for (final action in ShortcutAction.values) {
      unawaited(_box.delete('shortcut_${action.name}_keyId'));
      unawaited(_box.delete('shortcut_${action.name}_cmdOrCtrl'));
      unawaited(_box.delete('shortcut_${action.name}_shift'));
      unawaited(_box.delete('shortcut_${action.name}_alt'));
    }
    for (final entry in settings.shortcutOverrides.entries) {
      final binding = entry.value;
      unawaited(
        _box.put('shortcut_${entry.key.name}_keyId', binding.key.keyId),
      );
      unawaited(
        _box.put(
          'shortcut_${entry.key.name}_cmdOrCtrl',
          binding.cmdOrCtrl,
        ),
      );
      unawaited(
        _box.put('shortcut_${entry.key.name}_shift', binding.shift),
      );
      unawaited(_box.put('shortcut_${entry.key.name}_alt', binding.alt));
    }
    state = settings;
  }
}
