import 'package:flutter/material.dart';

/// Design tokens. The class names still say "Nocturne" (about 40 call sites
/// use them); the look is the industrial control-panel system described in
/// `docs/DESIGN.md` — graphite (dark) and enamel (light) finishes of one
/// design.
class NocturneSpace {
  static const s1 = 2.8;
  static const s2 = 5.6;
  static const s3 = 8.4;
  static const s4 = 11.2;
  static const s6 = 16.8;
  static const s8 = 22.4;
}

class NocturneRadius {
  static const sm = 3.0;
  static const md = 6.0;
  static const lg = 10.0;
}

/// Color roles for both finishes. Token names are stable; see
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
    required this.isDark,
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

  /// Recessed surface (inputs, readouts, switch housings).
  final Color well;

  /// Bevel highlight (light from the top-left) and bevel shadow.
  final Color hi;
  final Color lo;

  /// Hairline around raised plates.
  final Color edge;
  final bool isDark;

  /// "Graphite": powder-coated steel, warm off-white engraving.
  static const dark = NocturneColors(
    bg: Color(0xFF1B1D1F),
    surface: Color(0xFF2A2D30),
    text: Color(0xFFE8E6DF),
    divider: Color(0x40E8E6DF),
    neutral100: Color(0xFFF2F0E9),
    neutral200: Color(0xFFDAD8D1),
    neutral300: Color(0xFFC2C1BB),
    neutral400: Color(0xFFAAABA6),
    neutral500: Color(0xFF9A9C97),
    neutral600: Color(0xFF7C7F7A),
    neutral700: Color(0xFF5A5E5E),
    neutral800: Color(0xFF3A3E42),
    neutral900: Color(0xFF232628),
    well: Color(0xFF141618),
    hi: Color(0xFF4A4F55),
    lo: Color(0xFF0B0C0D),
    edge: Color(0xFF3A3E42),
    isDark: true,
  );

  /// "Enamel": pale aluminium plates, graphite engraving. Same geometry,
  /// bevels and lamps as [dark] — only the material differs. Neutral ramp
  /// runs dark→light with the number, as before.
  static const light = NocturneColors(
    bg: Color(0xFFD4D6D1),
    surface: Color(0xFFE6E7E3),
    text: Color(0xFF1F2224),
    divider: Color(0x4D1F2224),
    neutral100: Color(0xFF191B1D),
    neutral200: Color(0xFF2B2F31),
    neutral300: Color(0xFF383C40),
    neutral400: Color(0xFF42474B),
    neutral500: Color(0xFF4F5458),
    neutral600: Color(0xFF70767A),
    neutral700: Color(0xFF9A9FA2),
    neutral800: Color(0xFFB9BCB8),
    neutral900: Color(0xFFC6C9C4),
    well: Color(0xFFBFC2BC),
    hi: Color(0xFFFFFFFF),
    lo: Color(0xFF8A8E8A),
    edge: Color(0xFFA9ADA8),
    isDark: false,
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

const _fontFamily = 'Barlow';

/// Engraved-label / heading family. Only SemiBold (600) is bundled.
const kPanelFont = 'BarlowCondensed';

/// Builds the app's [ThemeData] for [brightness], tinted by [accent] (either
/// a preset from [nocturneAccentPalette] or a user's custom color).
ThemeData buildNocturneTheme({
  required Brightness brightness,
  required Color accent,
}) {
  final tokens = brightness == Brightness.dark
      ? NocturneColors.dark
      : NocturneColors.light;
  // Accent used as *text* (links, text buttons): darkened on enamel so it
  // keeps 4.5:1 against the pale plates; the accent itself is unchanged.
  final accentText = brightness == Brightness.dark
      ? accent
      : Color.lerp(accent, Colors.black, 0.45)!;
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

  // Headings use Barlow Condensed SemiBold (the one bundled weight); body
  // text never goes past Barlow Medium.
  TextStyle heading(double size) => TextStyle(
    fontFamily: _fontFamily,
    fontWeight: FontWeight.w600,
    fontSize: size,
    color: tokens.text,
    letterSpacing: 0.3,
  ).copyWith(fontFamily: kPanelFont);
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
      displaySmall: heading(36),
      headlineMedium: heading(29),
      headlineSmall: heading(24),
      titleLarge: heading(22),
      titleMedium: body(18, weight: FontWeight.w500),
      titleSmall: body(15, weight: FontWeight.w500),
      bodyLarge: body(16),
      bodyMedium: body(15),
      bodySmall: body(13.5),
      labelLarge: body(14, weight: FontWeight.w500),
      labelSmall: body(12),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.bg,
      foregroundColor: tokens.text,
      elevation: 0,
      titleTextStyle: heading(22),
    ),
    // A raised plate: bevel via a hairline edge plus a short, hard shadow
    // (light from the top-left). Screens wanting the full gradient plate
    // use PanelCard.
    cardTheme: CardThemeData(
      color: tokens.surface,
      elevation: 2,
      shadowColor: tokens.lo,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.md),
        side: BorderSide(color: tokens.edge, width: 1),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surface,
      elevation: 8,
      shadowColor: tokens.lo,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.lg),
        side: BorderSide(color: tokens.edge),
      ),
      titleTextStyle: heading(24),
    ),
    // Inputs are recessed wells.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.well,
      hintStyle: TextStyle(color: tokens.neutral400),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.md),
        borderSide: BorderSide(color: tokens.edge),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.md),
        borderSide: BorderSide(color: tokens.edge),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.md),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.text,
        backgroundColor: tokens.surface,
        side: BorderSide(color: tokens.edge),
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
        foregroundColor: accentText,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NocturneRadius.md),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 2,
        shadowColor: tokens.lo,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NocturneRadius.md),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? accent : tokens.well,
      ),
      trackOutlineColor: WidgetStatePropertyAll(tokens.edge),
      thumbColor: WidgetStatePropertyAll(
        tokens.isDark ? tokens.neutral200 : tokens.surface,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NocturneRadius.md),
        side: BorderSide(color: tokens.edge),
      ),
    ),
    iconTheme: IconThemeData(color: tokens.neutral300),
    listTileTheme: ListTileThemeData(
      iconColor: tokens.neutral300,
      selectedColor: accentText,
    ),
    dividerTheme: DividerThemeData(color: tokens.divider, thickness: 1),
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
