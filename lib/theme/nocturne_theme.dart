import 'package:flutter/material.dart';

/// Design tokens for the enterprise design (see `docs/DESIGN.md`). The class
/// names still say "Nocturne" (about 40 call sites use them); the look is a
/// flat, Swiss-grid utilitarian system with matched light and dark themes.
class NocturneSpace {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
}

class NocturneRadius {
  static const sm = 4.0;
  static const md = 6.0;
  static const lg = 8.0;
}

/// Window-width classes every screen adapts to. Compare against the width
/// the widget is actually given (LayoutBuilder), not the whole window.
class NocturneBreakpoints {
  static const compact = 720.0;
  static const medium = 1200.0;
  static const wide = 1800.0;
}

/// Color roles for both themes. Token names are stable; see
/// [NocturneColors.dark] and [NocturneColors.light].
class NocturneColors {
  const NocturneColors({
    required this.bg,
    required this.surface,
    required this.text,
    required this.divider,
    required this.neutral100,
    required this.neutral200,
    required this.neutral300,
    required this.neutral400,
    required this.neutral500,
    required this.neutral600,
    required this.neutral700,
    required this.neutral800,
    required this.neutral900,
    required this.well,
    required this.hi,
    required this.lo,
    required this.edge,
    required this.raised,
    required this.borderStrong,
    required this.done,
    required this.danger,
    required this.warn,
    required this.low,
    required this.isDark,
  });

  /// App canvas.
  final Color bg;

  /// Cards, rows, dialogs.
  final Color surface;
  final Color text;
  final Color divider;

  /// Text/fill ramp. 100 = strongest text, 500 = dimmest text that still
  /// meets 4.5:1, 600 = icons, 700 = strong border, 800/900 = subtle fills.
  final Color neutral100;
  final Color neutral200;
  final Color neutral300;
  final Color neutral400;
  final Color neutral500;
  final Color neutral600;
  final Color neutral700;
  final Color neutral800;
  final Color neutral900;

  /// Input / field fill.
  final Color well;

  /// Legacy bevel pair, kept only so old call sites compile; the design has
  /// no bevels. Prefer [edge] / [borderStrong].
  final Color hi;
  final Color lo;

  /// Default 1px border.
  final Color edge;

  /// Sidebar, table header, hover wash, segmented track.
  final Color raised;

  /// Inputs and anything that must read as interactive.
  final Color borderStrong;

  /// Text-safe status colors. Green means done and nothing else.
  final Color done;
  final Color danger;
  final Color warn;
  final Color low;
  final bool isDark;

  static const dark = NocturneColors(
    bg: Color(0xFF0F1115),
    surface: Color(0xFF171A20),
    text: Color(0xFFE8EAEE),
    divider: Color(0xFF2A2F39),
    neutral100: Color(0xFFF4F5F7),
    neutral200: Color(0xFFE8EAEE),
    neutral300: Color(0xFFC4C9D3),
    neutral400: Color(0xFFAEB4C0),
    neutral500: Color(0xFF8A92A1),
    neutral600: Color(0xFF6B7385),
    neutral700: Color(0xFF3A4150),
    neutral800: Color(0xFF2A2F39),
    neutral900: Color(0xFF1D2128),
    well: Color(0xFF12151A),
    hi: Color(0xFF2A2F39),
    lo: Color(0xFF0B0C0F),
    edge: Color(0xFF2A2F39),
    raised: Color(0xFF1D2128),
    borderStrong: Color(0xFF3A4150),
    done: Color(0xFF4CC38A),
    danger: Color(0xFFFF6B63),
    warn: Color(0xFFF0B04A),
    low: Color(0xFF8FA0C2),
    isDark: true,
  );

  /// Neutral ramp runs dark->light with the number, as in [dark] roles.
  static const light = NocturneColors(
    bg: Color(0xFFF5F6F8),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF1B1F29),
    divider: Color(0xFFE1E4EA),
    neutral100: Color(0xFF1B1F29),
    neutral200: Color(0xFF2A303D),
    neutral300: Color(0xFF4A5262),
    neutral400: Color(0xFF596173),
    neutral500: Color(0xFF666E80),
    neutral600: Color(0xFF8A92A3),
    neutral700: Color(0xFFC9CED8),
    neutral800: Color(0xFFE1E4EA),
    neutral900: Color(0xFFF0F1F4),
    well: Color(0xFFFFFFFF),
    hi: Color(0xFFFFFFFF),
    lo: Color(0xFFC9CED8),
    edge: Color(0xFFE1E4EA),
    raised: Color(0xFFF0F1F4),
    borderStrong: Color(0xFFC9CED8),
    done: Color(0xFF1E8A4C),
    danger: Color(0xFFC7372F),
    warn: Color(0xFF9A5B00),
    low: Color(0xFF5B6B8A),
    isDark: false,
  );
}

/// Priority tag colors (mid-tones; tags darken the text on the light theme).
/// Prefer [NocturneColors.danger]/[NocturneColors.warn]/[NocturneColors.low]
/// when the color is used as text.
class NocturnePriority {
  static const high = Color(0xFFE5484D);
  static const med = Color(0xFFD9930D);
  static const low = Color(0xFF6B7FA8);
}

/// Success/"done" and destructive-action colors. Green = done only.
class NocturneStatus {
  static const done = Color(0xFF2FA066);
  static const dangerBorder = Color(0xFFD14343);
  static const dangerText = Color(0xFFE5636A);
}

/// The 8 preset accent swatches (Settings > Appearance). Mid-tones: the
/// theme lightens them on dark and deepens them on light (see [tuneAccent]).
/// Green and red are left out on purpose: they carry meaning in this app.
const List<Color> nocturneAccentPalette = [
  Color(0xFF3F5BE8), // indigo (default)
  Color(0xFF2D8CF0), // azure
  Color(0xFF0E9AA7), // teal
  Color(0xFF8B5CF6), // violet
  Color(0xFFD6409F), // magenta
  Color(0xFFE8710A), // orange
  Color(0xFF64748B), // slate
  Color(0xFFA0845C), // sand
];

/// Same hue and saturation as [accent], with lightness pinned to a range
/// that keeps 4.5:1+ against the theme's surface (accent is also used as
/// text and as a fill under white text).
Color tuneAccent(Color accent, Brightness brightness) {
  final hsl = HSLColor.fromColor(accent);
  final l = brightness == Brightness.dark
      ? hsl.lightness.clamp(0.68, 0.80)
      : hsl.lightness.clamp(0.28, 0.46);
  return hsl.withLightness(l.toDouble()).toColor();
}

/// Categorical hues for departments, per theme. Always paired with the
/// department name, never colour alone.
const _deptDark = [
  Color(0xFF7C9CFF),
  Color(0xFF4FC1C9),
  Color(0xFFE58FC0),
  Color(0xFFF0A860),
  Color(0xFFB59CFF),
  Color(0xFF9CCB6B),
  Color(0xFF6DB6F2),
  Color(0xFFD9B26A),
];
const _deptLight = [
  Color(0xFF3F5BE8),
  Color(0xFF0B7F8A),
  Color(0xFFB02F80),
  Color(0xFFB4560A),
  Color(0xFF6B45D6),
  Color(0xFF4F7D1C),
  Color(0xFF1F6FB8),
  Color(0xFF8A6A1F),
];

const _fontFamily = 'IBMPlexSans';

/// Legacy name for the heading family; the design uses one family.
const kPanelFont = _fontFamily;

const _tabular = [FontFeature.tabularFigures()];

/// Builds the app's [ThemeData] for [brightness], tinted by [accent] (either
/// a preset from [nocturneAccentPalette] or a user's custom color).
ThemeData buildNocturneTheme({
  required Brightness brightness,
  required Color accent,
}) {
  final tokens = brightness == Brightness.dark
      ? NocturneColors.dark
      : NocturneColors.light;
  accent = tuneAccent(accent, brightness);
  final onAccent = accent.computeLuminance() > 0.5
      ? Colors.black
      : Colors.white;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: accent,
    onPrimary: onAccent,
    secondary: accent,
    onSecondary: onAccent,
    error: tokens.danger,
    onError: tokens.isDark ? Colors.black : Colors.white,
    surface: tokens.surface,
    onSurface: tokens.text,
    outline: tokens.borderStrong,
    outlineVariant: tokens.edge,
  );

  TextStyle ts(
    double size,
    double height, {
    FontWeight weight = FontWeight.w400,
    double spacing = 0,
    Color? color,
  }) => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: weight,
    fontSize: size,
    height: height / size,
    letterSpacing: spacing,
    color: color ?? tokens.text,
    fontFeatures: _tabular,
  );

  OutlineInputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(NocturneRadius.md),
    borderSide: BorderSide(color: c, width: w),
  );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(NocturneRadius.md),
  );
  final buttonText = ts(13, 20, weight: FontWeight.w500);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: _fontFamily,
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: tokens.bg,
    canvasColor: tokens.bg,
    colorScheme: colorScheme,
    dividerColor: tokens.divider,
    hintColor: tokens.neutral500,
    splashFactory: NoSplash.splashFactory,
    hoverColor: tokens.raised,
    highlightColor: Colors.transparent,
    focusColor: accent.withValues(alpha: 0.16),
    textTheme: TextTheme(
      displaySmall: ts(28, 36, weight: FontWeight.w600, spacing: -0.2),
      headlineMedium: ts(24, 32, weight: FontWeight.w600, spacing: -0.15),
      headlineSmall: ts(20, 28, weight: FontWeight.w600, spacing: -0.1),
      titleLarge: ts(20, 28, weight: FontWeight.w600, spacing: -0.1),
      titleMedium: ts(16, 24, weight: FontWeight.w600),
      titleSmall: ts(14, 20, weight: FontWeight.w600),
      bodyLarge: ts(14, 20),
      bodyMedium: ts(13, 20),
      bodySmall: ts(12, 16, color: tokens.neutral400),
      labelLarge: ts(13, 20, weight: FontWeight.w500),
      labelMedium: ts(12, 16, weight: FontWeight.w500),
      labelSmall: ts(11, 16, weight: FontWeight.w500, spacing: 0.1),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.bg,
      foregroundColor: tokens.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: ts(20, 28, weight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: tokens.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.lg),
        side: BorderSide(color: tokens.edge),
      ),
    ),
    // The one place a shadow is allowed: things floating over content.
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: tokens.isDark ? 0.7 : 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.lg),
        side: BorderSide(color: tokens.edge),
      ),
      titleTextStyle: ts(16, 24, weight: FontWeight.w600),
      contentTextStyle: ts(13, 20, color: tokens.neutral300),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      isDense: true,
      fillColor: tokens.well,
      hintStyle: ts(13, 20, color: tokens.neutral500),
      labelStyle: ts(13, 20, color: tokens.neutral400),
      border: inputBorder(tokens.borderStrong),
      enabledBorder: inputBorder(tokens.borderStrong),
      disabledBorder: inputBorder(tokens.edge),
      focusedBorder: inputBorder(accent, 2),
      errorBorder: inputBorder(tokens.danger),
      focusedErrorBorder: inputBorder(tokens.danger, 2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.text,
        backgroundColor: tokens.surface,
        side: BorderSide(color: tokens.borderStrong),
        shape: buttonShape,
        textStyle: buttonText,
        minimumSize: const Size(0, 32),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        shape: buttonShape,
        textStyle: buttonText,
        minimumSize: const Size(0, 32),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 0,
        shape: buttonShape,
        textStyle: buttonText,
        minimumSize: const Size(0, 32),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent
            : tokens.neutral800,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent
            : tokens.borderStrong,
      ),
      thumbColor: WidgetStatePropertyAll(
        tokens.isDark ? tokens.neutral100 : Colors.white,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: tokens.borderStrong, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      fillColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? accent : Colors.transparent,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: tokens.isDark ? 0.7 : 0.2),
      textStyle: ts(13, 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.md),
        side: BorderSide(color: tokens.edge),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: tokens.isDark ? tokens.neutral900 : tokens.neutral100,
        borderRadius: BorderRadius.circular(NocturneRadius.sm),
        border: Border.all(
          color: tokens.isDark ? tokens.edge : tokens.neutral100,
        ),
      ),
      textStyle: ts(12, 16, color: tokens.isDark ? tokens.text : tokens.surface),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(tokens.neutral700),
      radius: const Radius.circular(4),
      thickness: const WidgetStatePropertyAll(6),
    ),
    iconTheme: IconThemeData(color: tokens.neutral400, size: 18),
    listTileTheme: ListTileThemeData(
      iconColor: tokens.neutral400,
      selectedColor: accent,
    ),
    dividerTheme: DividerThemeData(
      color: tokens.divider,
      thickness: 1,
      space: 1,
    ),
    extensions: [NocturneThemeExtension(tokens: tokens, accent: accent)],
  );
}

/// Exposes the raw [NocturneColors] token set (and the active, theme-tuned
/// accent) to widgets that need a role the standard [ColorScheme] doesn't
/// carry, e.g. `neutral500` for muted meta text.
class NocturneThemeExtension extends ThemeExtension<NocturneThemeExtension> {
  const NocturneThemeExtension({required this.tokens, required this.accent});

  final NocturneColors tokens;
  final Color accent;

  @override
  NocturneThemeExtension copyWith({NocturneColors? tokens, Color? accent}) {
    return NocturneThemeExtension(
      tokens: tokens ?? this.tokens,
      accent: accent ?? this.accent,
    );
  }

  @override
  NocturneThemeExtension lerp(
    ThemeExtension<NocturneThemeExtension>? other,
    double t,
  ) {
    if (other is! NocturneThemeExtension) return this;
    return t < 0.5 ? this : other;
  }
}

extension NocturneThemeContext on BuildContext {
  NocturneColors get nocturne =>
      Theme.of(this).extension<NocturneThemeExtension>()!.tokens;

  /// The accent, already tuned for the active theme: safe as text on
  /// [NocturneColors.surface] and as a fill under white text.
  Color get nocturneAccent =>
      Theme.of(this).extension<NocturneThemeExtension>()!.accent;

  /// Hover wash for interactive surfaces: a quiet neutral, not the accent.
  Color get nocturneHoverColor => nocturne.raised;
  Color get nocturneSplashColor => nocturne.neutral800;

  /// Stable categorical color for a department (hash of [key], e.g. its
  /// name or id). Pair with the name; never colour alone.
  Color departmentColor(String key) {
    var h = 0;
    for (final c in key.toLowerCase().codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final list = nocturne.isDark ? _deptDark : _deptLight;
    return list[h % list.length];
  }
}
