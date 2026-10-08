import 'package:flutter/material.dart';

import '../../theme/industrial_shadows.dart';

/// A small glowing status dot with an uppercase monospace label — the
/// Industrial Skeuomorphism redesign's "LED indicator" signature, e.g. a
/// sync/connectivity state. Pulses gently while [active]; skips the pulse
/// (and renders at steady opacity) when [reduceMotion] is set.
class StatusLed extends StatefulWidget {
  const StatusLed({
    super.key,
    required this.label,
    required this.color,
    this.active = true,
    this.reduceMotion = false,
  });

  final String label;
  final Color color;
  final bool active;
  final bool reduceMotion;

  @override
  State<StatusLed> createState() => _StatusLedState();
}

class _StatusLedState extends State<StatusLed>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active && !widget.reduceMotion) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant StatusLed oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldPulse = widget.active && !widget.reduceMotion;
    if (shouldPulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!shouldPulse && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = widget.reduceMotion || !widget.active
            ? 1.0
            : 0.55 + (_controller.value * 0.45);
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: opacity),
            boxShadow: glow(widget.color),
          ),
        );
      },
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 6),
        Text(
          widget.label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
            color: widget.color,
          ),
        ),
      ],
    );
  }
}
