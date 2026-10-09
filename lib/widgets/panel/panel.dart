import 'package:flutter/material.dart';

import '../../theme/nocturne_theme.dart';

/// Shared surface primitives for the enterprise design (see
/// `docs/DESIGN.md`). Flat: depth is a 1px border and a fill, never a bevel
/// or a shadow (shadows are reserved for dialogs and menus).
enum PanelDepth {
  /// Cards that hold content: surface fill + hairline border.
  raised,

  /// Fields, wells and tracks: field fill + stronger border.
  recessed,

  /// Printed-on: no border; the given [fill] or nothing.
  flat,
}

/// Decoration for a surface.
BoxDecoration panelDecoration(
  BuildContext context, {
  PanelDepth depth = PanelDepth.raised,
  double radius = NocturneRadius.lg,
  Color? fill,
}) {
  final t = context.nocturne;
  final br = BorderRadius.circular(radius);
  switch (depth) {
    case PanelDepth.raised:
      return BoxDecoration(
        borderRadius: br,
        color: fill ?? t.surface,
        border: Border.all(color: t.edge),
      );
    case PanelDepth.recessed:
      return BoxDecoration(
        borderRadius: br,
        color: fill ?? t.well,
        border: Border.all(color: t.borderStrong),
      );
    case PanelDepth.flat:
      return BoxDecoration(borderRadius: br, color: fill);
  }
}

/// A card for grouping content, with an optional header row.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.depth = PanelDepth.raised,
    this.padding = const EdgeInsets.all(16),
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
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Small section caption: 11px, semibold, tracked, uppercase. For section
/// headers and field legends — never for sentences.
class StampLabel extends StatelessWidget {
  const StampLabel(this.text, {super.key, this.color, this.size = 11});

  final String text;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: kPanelFont,
        fontWeight: FontWeight.w600,
        fontSize: size,
        height: 16 / 11,
        letterSpacing: 0.7,
        color: color ?? context.nocturne.neutral500,
      ),
    );
  }
}

/// A status dot. On = solid [color]; off = hollow ring. Never the only
/// carrier of state — pair with text or position.
class IndicatorLamp extends StatelessWidget {
  const IndicatorLamp({
    super.key,
    required this.on,
    this.color,
    this.size = 8,
  });

  final bool on;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.nocturne.done;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? c : Colors.transparent,
        border: on ? null : Border.all(color: c, width: 1.5),
      ),
    );
  }
}

/// Thin progress bar. [value] is 0..1 and eases to new values (the "progress
/// feedback" half of the check-off moment). [segments] is ignored; kept so
/// existing call sites compile.
class GaugeBar extends StatelessWidget {
  const GaugeBar({
    super.key,
    required this.value,
    this.color,
    this.segments = 0,
    this.height = 6,
  });

  final double value;
  final Color? color;
  final int segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    final v = value.clamp(0.0, 1.0);
    final fill = color ?? context.nocturneAccent;
    final animate = !MediaQuery.of(context).disableAnimations;
    return Semantics(
      value: '${(v * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: v),
            duration: animate
                ? const Duration(milliseconds: 280)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (context, shown, _) => Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: t.neutral800),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: shown,
                  child: ColoredBox(color: fill),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
