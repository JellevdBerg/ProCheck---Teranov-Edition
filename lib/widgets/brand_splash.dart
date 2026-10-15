import 'package:flutter/material.dart';

import 'brand_mark.dart';
import 'brand_paths.dart';

/// The animated launch logo: a Flutter port of the logo package's
/// `splash/splash.css`, keeping its timings, easings and geometry. The
/// brackets snap open, the tick draws in, ProCheck fades in, TERANOV wipes in
/// left to right, then a silver sheen sweeps across ProCheck once.
///
/// With [reduceMotion] the finished logo shows straight away.
class BrandSplash extends StatefulWidget {
  const BrandSplash({super.key, this.reduceMotion = false});

  final bool reduceMotion;

  /// Time until the last animation (the sheen) finishes: 1.4 s delay + 1.1 s.
  static const duration = Duration(milliseconds: 2500);

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BrandSplash.duration,
    value: widget.reduceMotion ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BrandColors.of(context);
    final width = (MediaQuery.sizeOf(context).width * 0.72).clamp(0.0, 380.0);
    return Semantics(
      label: 'ProCheck Teranov is loading',
      image: true,
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size(width, width * 64 / 251.8),
          painter: _SplashPainter(_controller, colors),
        ),
      ),
    );
  }
}

class _SplashPainter extends CustomPainter {
  _SplashPainter(this.animation, this.colors) : super(repaint: animation);

  final Animation<double> animation;
  final BrandColors colors;

  static const _total = 2.5; // seconds

  // The CSS timeline: (delay, duration) in seconds, with its easing.
  static const _brackets = _Beat(.15, .5, Cubic(.2, .8, .2, 1));
  static const _tick = _Beat(.6, .35, Cubic(.6, 0, .3, 1));
  static const _word = _Beat(.85, .45, Cubic(0, 0, .58, 1));
  static const _tag = _Beat(1.0, .6, Cubic(.4, 0, .2, 1));
  static const _sheen = _Beat(1.4, 1.1, Cubic(.4, 0, .2, 1));

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * _total;
    canvas.scale(size.width / 251.8);

    // Brackets and tick live in a scale(1.333333) group (the 48 px mark).
    canvas.save();
    canvas.scale(4 / 3);
    final b = _brackets.at(t);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = true;
    stroke
      ..color = colors.ink.withValues(alpha: b)
      ..strokeWidth = 4;
    final dx = 10 * (1 - b);
    canvas.drawPath(
      Path()
        ..moveTo(14 + dx, 7)
        ..lineTo(7 + dx, 7)
        ..lineTo(7 + dx, 41)
        ..lineTo(14 + dx, 41),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(34 - dx, 7)
        ..lineTo(41 - dx, 7)
        ..lineTo(41 - dx, 41)
        ..lineTo(34 - dx, 41),
      stroke,
    );

    final k = _tick.at(t);
    if (k > 0) {
      final tick = Path()
        ..moveTo(15, 24.5)
        ..lineTo(21.5, 31)
        ..lineTo(33.5, 17);
      final metric = tick.computeMetrics().first;
      stroke
        ..color = BrandColors.accent
        ..strokeWidth = 4.5;
      canvas.drawPath(metric.extractPath(0, metric.length * k), stroke);
    }
    canvas.restore();

    final w = _word.at(t);
    if (w > 0) {
      canvas.drawPath(
        brandWordPath,
        Paint()..color = colors.ink.withValues(alpha: w),
      );
    }

    // TERANOV wipes in over its own bounding box, left to right.
    final g = _tag.at(t);
    if (g > 0) {
      final tb = brandTagPath.getBounds();
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(tb.left, tb.top, tb.left + tb.width * g, tb.bottom),
      );
      canvas.drawPath(brandTagPath, Paint()..color = colors.muted);
      canvas.restore();
    }

    // The sheen bar is clipped to the wordmark and slides 241.8 units right.
    final s = _sheen.at(t);
    final bar = Rect.fromLTWH(10 + 241.8 * s, 0, 70, 64);
    final edge = colors.sheenEdge;
    canvas.save();
    canvas.clipPath(brandWordPath);
    canvas.drawRect(
      bar,
      Paint()
        ..shader = LinearGradient(
          colors: [
            edge.withValues(alpha: 0),
            edge,
            colors.sheenCore,
            edge,
            edge.withValues(alpha: 0),
          ],
          stops: const [0, .3, .5, .7, 1],
        ).createShader(bar),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SplashPainter old) => old.colors != colors;
}

/// One CSS animation: 0 before its delay, eased 0..1 across its duration,
/// then held at 1 (`animation-fill-mode: both`).
class _Beat {
  const _Beat(this.delay, this.duration, this.curve);

  final double delay;
  final double duration;
  final Curve curve;

  double at(double t) =>
      curve.transform(((t - delay) / duration).clamp(0.0, 1.0));
}
