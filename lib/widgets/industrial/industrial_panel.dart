import 'package:flutter/material.dart';

import '../../theme/industrial_shadows.dart';
import '../../theme/nocturne_theme.dart';

/// Drop-in replacement for [Card]: a real dual neumorphic shadow (dark
/// bottom-right + faint light top-left, via [panelShadow]) instead of
/// Material's single elevation shadow, which [CardTheme] can't express as a
/// shadow list. Mirrors [Card]'s commonly-used constructor params so
/// existing call sites only need their `Card(` swapped for
/// `IndustrialPanel(`.
class IndustrialPanel extends StatelessWidget {
  const IndustrialPanel({
    super.key,
    this.margin,
    this.color,
    this.shape,
    this.clipBehavior = Clip.antiAlias,
    required this.child,
  });

  final EdgeInsetsGeometry? margin;
  final Color? color;
  final ShapeBorder? shape;
  final Clip clipBehavior;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final resolvedShape = shape;
    final borderRadius =
        resolvedShape is RoundedRectangleBorder &&
            resolvedShape.borderRadius is BorderRadius
        ? resolvedShape.borderRadius as BorderRadius
        : BorderRadius.circular(NocturneRadius.xl);

    return Container(
      margin: margin,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: color ?? tokens.surface,
        borderRadius: borderRadius,
        boxShadow: panelShadow(tokens),
      ),
      // A descendant ListTile/InkWell paints its background and splashes on
      // the nearest Material ancestor — without this, Card used to provide
      // that for free, so swapping it for a plain Container breaks them.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
