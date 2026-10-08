import 'package:flutter/material.dart';

/// Nocturne design tokens, ported from the design handoff's `styles.css`.
/// Values are the literal px figures from the CSS custom properties — CSS
/// px and Flutter's logical pixels are both device-independent units at the
/// same nominal density, so they carry over directly.
class NocturneSpace {
  static const s1 = 2.8;
  static const s2 = 5.6;
  static const s3 = 8.4;
  static const s4 = 11.2;
  static const s6 = 16.8;
  static const s8 = 22.4;
}

class NocturneRadius {
  static const sm = 4.0;
  static const md = 8.0;
  static const lg = 14.0;
}

/// Dark-ground color roles (Nocturne's native theme). A light counterpart is
/// derived from the same neutral ramp for [AppSettings]'s Light option,
/// which the design handoff didn't specify explicitly — see
/// [NocturneColors.light].
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
  });

  final Color bg;
  final Color surface;
  final Color text;
  final Color divider;
  final Color neutral100;
  final Color neutral200;
  final Color neutral300;
  final Color neutral400;
  final Color neutral500;
  final Color neutral600;
  final Color neutral700;
  final Color neutral800;
  final Color neutral900;

  static const dark = NocturneColors(
    bg: Color(0xFF161826),
    surface: Color(0xFF232532),
    text: Color(0xFFE9E9ED),
    divider: Color(0x29E9E9ED), // ~16% of --color-text
    neutral100: Color(0xFFF3F5FE),
    neutral200: Color(0xFFE4E7F5),
    neutral300: Color(0xFFCFD3E5),
    neutral400: Color(0xFFB2B6CA),
    neutral500: Color(0xFF9397AB),
    neutral600: Color(0xFF75798C),
    neutral700: Color(0xFF595D6C),
    neutral800: Color(0xFF3F424D),
    neutral900: Color(0xFF292B31),
  );

  /// The handoff is dark-only ("Nocturne is a quiet dark interface"); this
  /// light variant applies the same neutral ramp and role relationships
  /// inverted onto a light ground, since Settings still offers a Light
  /// option carried over from the app's pre-redesign theme support.
  static const light = NocturneColors(
    bg: Color(0xFFF3F5FE),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF292B31),
    divider: Color(0x29292B31),
    neutral100: Color(0xFF292B31),
    neutral200: Color(0xFF3F424D),
    neutral300: Color(0xFF595D6C),
    neutral400: Color(0xFF75798C),
    neutral500: Color(0xFF9397AB),
    neutral600: Color(0xFFB2B6CA),
    neutral700: Color(0xFFCFD3E5),
    neutral800: Color(0xFFE4E7F5),
    neutral900: Color(0xFFF3F5FE),
  );
}

/// Priority tag colors — fixed across light/dark (they're status colors,
/// not theme-derived).
class NocturnePriority {
  static const high = Color(0xFFFF5C5C);
  static const med = Color(0xFFFFC93C);
  static const low = Color(0xFF3DDC84);
}

/// Success/"done" accent and destructive-action colors from the handoff.
class NocturneStatus {
  static const done = Color(0xFF6FBF73);
  static const dangerBorder = Color(0xFFC94F4F);
  static const dangerText = Color(0xFFE08A8A);
}

/// The 8 preset accent swatches from the handoff's Settings > Appearance.
const List<Color> nocturneAccentPalette = [
  Color(0xFF9184D9),
  Color(0xFF6A95D6),
  Color(0xFF5CB8A8),
  Color(0xFF6FBF73),
  Color(0xFFD69A5C),
  Color(0xFFD6738F),
  Color(0xFFB07FD6),
  Color(0xFFA08468),
];

const _fontFamily = 'Inter';

/// Builds the app's [ThemeData] for [brightness], tinted by [accent] (either
/// a preset from [nocturneAccentPalette] or a user's custom color).
ThemeData buildNocturneTheme({
  required Brightness brightness,
  required Color accent,
}) {
  final tokens = brightness == Brightness.dark
      ? NocturneColors.dark
      : NocturneColors.light;
  final onAccent = accent.computeLuminance() > 0.5
      ? Colors.black
      : Colors.white;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: accent,
    onPrimary: onAccent,
    secondary: accent,
    onSecondary: onAccent,
    error: NocturneStatus.dangerBorder,
    onError: Colors.white,
    surface: tokens.surface,
    onSurface: tokens.text,
  );

  // Headings never go past the design system's 500 weight — even though
  // Material's default TextTheme assigns bolder weights to larger styles.
  TextStyle heading(double size) => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w500,
    fontSize: size,
    color: tokens.text,
    letterSpacing: -0.2,
  );
  TextStyle body(double size, {FontWeight weight = FontWeight.w400}) =>
      TextStyle(
        fontFamily: _fontFamily,
        fontWeight: weight,
        fontSize: size,
        color: tokens.text,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: tokens.bg,
    canvasColor: tokens.bg,
    colorScheme: colorScheme,
    dividerColor: tokens.divider,
    hintColor: tokens.neutral400,
    textTheme: TextTheme(
      displaySmall: heading(32),
      headlineMedium: heading(25),
      headlineSmall: heading(20),
      titleLarge: heading(19),
      titleMedium: heading(17),
      titleSmall: body(14, weight: FontWeight.w500),
      bodyLarge: body(15),
      bodyMedium: body(14),
      bodySmall: body(13),
      labelLarge: body(13, weight: FontWeight.w500),
      labelSmall: body(11),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.bg,
      foregroundColor: tokens.text,
      elevation: 0,
      titleTextStyle: heading(19),
    ),
    cardTheme: CardThemeData(
      color: tokens.surface,
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      // A soft neutral drop shadow (never accent-tinted — see
      // NocturneColors doc comment) gives cards a hint of lift over the flat
      // elevation:0 + border look, without reading as a generic Material
      // card shadow.
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.md),
        side: BorderSide(color: tokens.neutral800, width: 1),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.lg),
      ),
      titleTextStyle: heading(20),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surface,
      hintStyle: TextStyle(color: tokens.neutral400),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.md),
        borderSide: BorderSide(color: tokens.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.md),
        borderSide: BorderSide(color: tokens.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.md),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NocturneRadius.md),
        ),
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NocturneRadius.md),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NocturneRadius.md),
        ),
      ),
    ),
    iconTheme: IconThemeData(color: tokens.neutral300),
    listTileTheme: ListTileThemeData(iconColor: tokens.neutral300),
    dividerTheme: DividerThemeData(color: tokens.divider, thickness: 1),
    // Flutter's default scrollbar is a flat mid-grey bar that ignores the
    // rest of the palette — swapped for one built from the theme's own
    // neutral ramp so it doesn't stick out as an unstyled platform control.
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(tokens.neutral600.withValues(alpha: 0.6)),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      radius: const Radius.circular(NocturneRadius.sm),
      thickness: const WidgetStatePropertyAll(6),
    ),
    extensions: [NocturneThemeExtension(tokens: tokens, accent: accent)],
  );
}

/// Exposes the raw [NocturneColors] token set (and the active accent) to
/// widgets that need a role the standard [ColorScheme] doesn't carry, e.g.
/// `neutral500` for muted meta text.
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
  Color get nocturneAccent =>
      Theme.of(this).extension<NocturneThemeExtension>()!.accent;

  /// The one hover/press tint every interactive surface in the app should
  /// use — a translucent wash of the current theme accent — so hovering
  /// anything reads as the same design system no matter which screen it's
  /// on. Pair with [nocturneSplashColor] on an InkWell's hoverColor/
  /// splashColor/highlightColor, and [NocturneRadius.md] for its
  /// borderRadius (matching Card's own radius).
  Color get nocturneHoverColor => nocturneAccent.withValues(alpha: 0.12);
  Color get nocturneSplashColor => nocturneAccent.withValues(alpha: 0.18);
}
