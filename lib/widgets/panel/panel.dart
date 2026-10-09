import 'package:flutter/material.dart';

import '../../theme/nocturne_theme.dart';

/// Shared control-panel primitives. One light source (top-left); the same
/// geometry in the dark "graphite" and light "enamel" finishes. See
/// `docs/DESIGN.md` for usage rules.
enum PanelDepth { raised, recessed, flat }

/// Decoration for a plate. [raised] = bevelled plate standing proud,
/// [recessed] = a well cut into the chassis, [flat] = printed-on, no depth.
BoxDecoration panelDecoration(
  BuildContext context, {
  PanelDepth depth = PanelDepth.raised,
  double radius = NocturneRadius.md,
  Color? fill,
}) {
  final t = context.nocturne;
  final br = BorderRadius.circular(radius);
  switch (depth) {
    case PanelDepth.raised:
      final base = fill ?? t.surface;
      return BoxDecoration(
        borderRadius: br,
        border: Border.all(color: t.edge),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(base, t.hi, t.isDark ? 0.12 : 0.55)!,
            base,
            Color.lerp(base, t.lo, t.isDark ? 0.25 : 0.08)!,
          ],
          stops: const [0, 0.35, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: t.lo.withValues(alpha: t.isDark ? 0.9 : 0.35),
            offset: const Offset(1.5, 2),
            blurRadius: 3,
          ),
          BoxShadow(
            color: t.hi.withValues(alpha: t.isDark ? 0.35 : 0.9),
            offset: const Offset(-1, -1),
            blurRadius: 1,
          ),
        ],
      );
    case PanelDepth.recessed:
      final base = fill ?? t.well;
      return BoxDecoration(
        borderRadius: br,
        border: Border.all(color: t.isDark ? t.lo : t.edge),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(base, t.lo, t.isDark ? 0.5 : 0.12)!, base],
        ),
        // The lip catching light along the bottom edge of the cut.
        boxShadow: [
          BoxShadow(
            color: t.hi.withValues(alpha: t.isDark ? 0.3 : 0.9),
            offset: const Offset(0, 1),
            blurRadius: 0,
          ),
        ],
      );
    case PanelDepth.flat:
      return BoxDecoration(
        borderRadius: br,
        color: fill ?? t.surface,
        border: Border.all(color: t.edge),
      );
  }
}

/// A raised plate for grouping content, with an optional engraved header.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.depth = PanelDepth.raised,
    this.padding = const EdgeInsets.all(14),
    this.fill,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final PanelDepth depth;
  final EdgeInsetsGeometry padding;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: panelDecoration(context, depth: depth, fill: fill),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null || trailing != null) ...[
              Row(
                children: [
                  if (title != null) Expanded(child: StampLabel(title!)),
                  if (title == null) const Spacer(),
                  // build_runner's analyzer cannot parse `?trailing`, and CI runs it.
                  // ignore: use_null_aware_elements
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 10),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Engraved caption: condensed, uppercase, tracked. Use for section headers
/// and plate legends — never for body text.
class StampLabel extends StatelessWidget {
  const StampLabel(this.text, {super.key, this.color, this.size = 13});

  final String text;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: kPanelFont,
        fontWeight: FontWeight.w600,
        fontSize: size,
        letterSpacing: 1.2,
        color: color ?? t.neutral500,
        // Engraved: a highlight one pixel below the glyph.
        shadows: [
          Shadow(
            color: t.hi.withValues(alpha: 0.6),
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

/// A round indicator lamp. Lit = glowing [color]; unlit = the same hue at
/// low value. Never the only carrier of state — pair with text or position.
class IndicatorLamp extends StatelessWidget {
  const IndicatorLamp({
    super.key,
    required this.on,
    this.color = NocturneStatus.done,
    this.size = 10,
  });

  final bool on;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    final unlit = Color.lerp(t.well, color, 0.16)!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: t.isDark ? t.lo : t.edge, width: 1),
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: on
              ? [Color.lerp(color, Colors.white, 0.55)!, color]
              : [Color.lerp(unlit, t.hi, 0.25)!, unlit],
        ),
        boxShadow: on
            ? [
                BoxShadow(
                  color: color.withValues(alpha: t.isDark ? 0.65 : 0.45),
                  blurRadius: size * 0.9,
                ),
              ]
            : null,
      ),
    );
  }
}

/// Segmented LED gauge for progress. [value] is 0..1.
class GaugeBar extends StatelessWidget {
  const GaugeBar({
    super.key,
    required this.value,
    this.color,
    this.segments = 20,
    this.height = 10,
  });

  final double value;
  final Color? color;
  final int segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    final lit = color ?? context.nocturneAccent;
    final filled = (value.clamp(0.0, 1.0) * segments).round();
    return Semantics(
      value: '${(value.clamp(0.0, 1.0) * 100).round()}%',
      child: DecoratedBox(
        decoration: panelDecoration(
          context,
          depth: PanelDepth.recessed,
          radius: 3,
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < segments; i++) ...[
                  if (i > 0) const SizedBox(width: 1.5),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1),
                        color: i < filled ? lit : Color.lerp(t.well, lit, 0.10),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
