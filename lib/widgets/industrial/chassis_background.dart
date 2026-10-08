import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/nocturne_theme.dart';

/// The "chassis" backdrop for the Industrial Skeuomorphism redesign: a flat
/// textured surface everything else sits on (Level 0 in the elevation
/// model), replacing a plain flat `Scaffold` fill. Two layers: a soft
/// top-left-lit radial wash (so the whole chassis reads as lit from one
/// consistent direction, matching every panel's drop shadow), plus a fine
/// grain texture simulating the microscopic imperfections of molded plastic.
///
/// Fills whatever space it's given — wrap it around a screen's content with
/// a [Stack] (see `app_shell.dart`, `login_screen.dart`, `splash_screen.dart`).
class ChassisBackground extends StatelessWidget {
  const ChassisBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.6, -0.8),
          radius: 1.6,
          colors: [tokens.surface, tokens.bg],
        ),
      ),
      child: CustomPaint(painter: _GrainPainter(tokens.neutral900)),
    );
  }
}

/// A fixed, deterministically-seeded field of faint dots — cheap to paint
/// (no per-frame regeneration; `shouldRepaint` is always false) and reads as
/// grain at normal viewing distance without the cost of a real noise shader.
class _GrainPainter extends CustomPainter {
  _GrainPainter(this.grainColor);

  final Color grainColor;

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(7); // fixed seed: same grain pattern every build
    final paint = Paint()..color = grainColor.withValues(alpha: 0.05);
    // One dot per ~900px^2 keeps this cheap even on a large desktop window.
    final count = (size.width * size.height / 900).clamp(0, 6000).toInt();
    for (var i = 0; i < count; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      canvas.drawCircle(Offset(dx, dy), 0.6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) =>
      oldDelegate.grainColor != grainColor;
}
