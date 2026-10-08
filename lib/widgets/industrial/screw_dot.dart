import 'package:flutter/material.dart';

/// A tiny radial-gradient dot simulating a corner screw on a bolted panel —
/// one of the Industrial Skeuomorphism redesign's signature manufacturing
/// details. Used sparingly (see callers) on a handful of marquee panels, not
/// on every card — that would be visual noise rather than a deliberate
/// detail.
class ScrewDot extends StatelessWidget {
  const ScrewDot({super.key, this.size = 4});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: [
            Colors.white.withValues(alpha: 0.18),
            Colors.black.withValues(alpha: 0.35),
          ],
        ),
      ),
    );
  }
}

/// Positions a [ScrewDot] at each corner of a panel, [inset] from the edges
/// — wrap a card's content in a `Stack` with this as the last child.
class ScrewDots extends StatelessWidget {
  const ScrewDots({super.key, this.inset = 10});

  final double inset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(top: inset, left: inset, child: const ScrewDot()),
          Positioned(top: inset, right: inset, child: const ScrewDot()),
          Positioned(bottom: inset, left: inset, child: const ScrewDot()),
          Positioned(bottom: inset, right: inset, child: const ScrewDot()),
        ],
      ),
    );
  }
}
