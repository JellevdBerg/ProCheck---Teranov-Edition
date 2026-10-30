import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';

/// Motion tokens (see `docs/DESIGN.md`), tuned in the motion lab: a stiff,
/// lightly bouncy spring for highlights that move between items, and a
/// standard ease-out for everything that enters or settles.
class Motion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
  static const out = Cubic(0, 0, 0.2, 1);

  /// The theme switch's circle reveal.
  static const reveal = Duration(milliseconds: 560);

  /// Stiffness 840, damping ratio 0.6: about 9% overshoot, settled by 394ms.
  static const spring = SpringCurve(
    stiffness: 840,
    dampingRatio: 0.6,
    duration: springDuration,
  );
  static const springDuration = Duration(milliseconds: 394);

  /// Gap between rows as a screen comes in, and how far they slide up.
  static const stagger = Duration(milliseconds: 50);
  static const travel = 20.0;
  static const pressScale = 0.95;

  /// True when the app's Reduce motion setting or the OS asks for no motion.
  /// Outside a ProviderScope (bare widget tests) only the OS setting counts.
  static bool reduced(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return true;
    final scope = context
        .getElementForInheritedWidgetOfExactType<UncontrolledProviderScope>();
    return scope != null &&
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(settingsProvider).reduceMotion;
  }

  /// Set by the shell whenever the screen changes. Rows only stagger in
  /// shortly after, not when a list re-creates them on scroll.
  static DateTime screenShownAt = DateTime.now();
}

/// A damped spring (mass 1) from 0 to 1, sampled over [duration]. May
/// overshoot 1 before it settles.
class SpringCurve extends Curve {
  const SpringCurve({
    required this.stiffness,
    required this.dampingRatio,
    required this.duration,
  });

  final double stiffness;
  final double dampingRatio;
  final Duration duration;

  @override
  double transformInternal(double t) => SpringSimulation(
    SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: stiffness,
      ratio: dampingRatio,
    ),
    0,
    1,
    0,
  ).x(t * duration.inMicroseconds / Duration.microsecondsPerSecond);
}
