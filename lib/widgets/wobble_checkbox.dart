import 'package:flutter/material.dart';

import '../theme/nocturne_theme.dart';

/// The check-off control, and the app's one expressive moment: the box fills
/// green, the tick draws itself, and a single soft ring pulses out. Still a
/// real [Checkbox] underneath (transparent, scaled up to the box's hit area)
/// so tap, keyboard, focus and semantics behave exactly as before; the box is
/// only the picture. All motion is skipped when [reduceMotion] is set.
///
/// (The class name is historic; the sound and the progress-bar easing live
/// with the callers and in `GaugeBar`.)
class WobbleCheckbox extends StatefulWidget {
  const WobbleCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.reduceMotion = false,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final bool reduceMotion;

  /// How long the check-off animation takes to play out. Exposed so other
  /// widgets that need to sequence something after it (e.g. auto-removing a
  /// completed standalone task) can wait for the same duration rather than
  /// guessing at a matching one of their own.
  static const duration = Duration(milliseconds: 350);

  @override
  State<WobbleCheckbox> createState() => _WobbleCheckboxState();
}

class _WobbleCheckboxState extends State<WobbleCheckbox>
    with SingleTickerProviderStateMixin {
  static const _box = 18.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WobbleCheckbox.duration,
    value: widget.value ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant WobbleCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value) return;
    if (widget.reduceMotion) {
      _controller.value = widget.value ? 1 : 0;
    } else if (widget.value) {
      _controller.forward(from: 0);
    } else {
      // Un-checking is quiet: just snap back.
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                size: const Size.square(28),
                painter: _TickPainter(
                  checked: widget.value,
                  progress: _controller.value,
                  done: t.done,
                  border: t.borderStrong,
                  idleFill: t.well,
                ),
              ),
            ),
          ),
          // Invisible but fully functional: hit target, focus ring, semantics.
          Transform.scale(
            scale: 1.5,
            child: Checkbox(
              value: widget.value,
              onChanged: widget.onChanged,
              fillColor: const WidgetStatePropertyAll(Colors.transparent),
              checkColor: Colors.transparent,
              side: const BorderSide(color: Colors.transparent),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter({
    required this.checked,
    required this.progress,
    required this.done,
    required this.border,
    required this.idleFill,
  });

  final bool checked;
  final double progress; // 0..1 over WobbleCheckbox.duration
  final Color done;
  final Color border;
  final Color idleFill;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const s = _WobbleCheckboxState._box;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: s, height: s),
      const Radius.circular(5),
    );

    if (!checked) {
      canvas.drawRRect(rect, Paint()..color = idleFill);
      canvas.drawRRect(
        rect.deflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = border,
      );
      return;
    }

    // 0..0.4 fill, 0.15..0.7 tick draw, 0.2..1 ring pulse.
    double seg(double a, double b) => ((progress - a) / (b - a)).clamp(0.0, 1.0);
    final fill = Curves.easeOut.transform(seg(0, 0.4));
    final draw = Curves.easeOutCubic.transform(seg(0.15, 0.7));
    final ring = Curves.easeOut.transform(seg(0.2, 1));

    if (ring > 0 && ring < 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: s + 10 * ring, height: s + 10 * ring),
          Radius.circular(5 + 5 * ring),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = done.withValues(alpha: 0.45 * (1 - ring)),
      );
    }

    canvas.drawRRect(rect, Paint()..color = Color.lerp(idleFill, done, fill)!);
    if (fill < 1) {
      canvas.drawRRect(
        rect.deflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Color.lerp(border, done, fill)!,
      );
    }

    final tick = Path()
      ..moveTo(c.dx - 4.2, c.dy + 0.4)
      ..lineTo(c.dx - 1.2, c.dy + 3.4)
      ..lineTo(c.dx + 4.4, c.dy - 3.2);
    final metric = tick.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * draw),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.checked != checked ||
      old.progress != progress ||
      old.done != done ||
      old.border != border ||
      old.idleFill != idleFill;
}
