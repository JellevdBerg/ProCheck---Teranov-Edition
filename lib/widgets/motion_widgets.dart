import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/motion.dart';

/// Fades and slides [child] up into place, [index] steps of [Motion.stagger]
/// after the screen appears. Rows past the first dozen, and rows built well
/// after the screen changed (scrolling), show at once. An [isNew] row (just
/// added) always grows in.
class StaggerIn extends StatefulWidget {
  const StaggerIn({
    super.key,
    required this.index,
    required this.child,
    this.isNew = false,
  });

  final int index;
  final Widget child;
  final bool isNew;

  static const _maxStaggered = 12;
  static const _window = Duration(milliseconds: 800);

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  );
  late Animation<double> _curve = _controller;
  bool _started = false;
  bool _grow = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) return;
    _grow = widget.isNew;
    final i = _grow ? 0 : widget.index;
    final fresh =
        DateTime.now().difference(Motion.screenShownAt) < StaggerIn._window;
    if (!_grow && (i >= StaggerIn._maxStaggered || !fresh)) return;
    final delay = Motion.stagger * i;
    final total = delay + Motion.slow;
    _controller.duration = total;
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: Motion.out,
      ),
    );
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final faded = FadeTransition(
      opacity: _curve,
      child: AnimatedBuilder(
        animation: _curve,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (1 - _curve.value) * Motion.travel * 0.8),
          child: child,
        ),
      ),
    );
    if (!_grow) return faded;
    return SizeTransition(
      sizeFactor: _curve,
      alignment: Alignment.topCenter,
      child: faded,
    );
  }
}

/// Shrinks [child] to [Motion.pressScale] while a pointer is down on it.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || Motion.reduced(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? Motion.pressScale : 1,
        duration: Motion.fast,
        curve: Motion.out,
        child: widget.child,
      ),
    );
  }
}

/// Swaps [child] when [switchKey] changes: the old page fades out quickly and
/// the new one fades in while sliding up [Motion.travel].
class PageSwitch extends StatelessWidget {
  const PageSwitch({super.key, required this.switchKey, required this.child});

  final Object switchKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : Motion.slow,
      reverseDuration: reduced ? Duration.zero : Motion.base,
      switchInCurve: Motion.out,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final leaving = animation.status == AnimationStatus.reverse;
            final dy = (1 - animation.value) * (leaving ? -6 : Motion.travel);
            return Transform.translate(offset: Offset(0, dy), child: child);
          },
        ),
      ),
      child: KeyedSubtree(key: ValueKey(switchKey), child: child),
    );
  }
}

/// Paints one rounded highlight behind the row that [SlidingHighlight.keyOf]
/// is attached to, and springs it to the next row when [activeId] changes.
/// Hidden while no row inside carries the key.
class SlidingHighlight extends StatefulWidget {
  const SlidingHighlight({
    super.key,
    required this.activeId,
    required this.color,
    required this.radius,
    required this.child,
  });

  final Object? activeId;
  final Color color;
  final BorderRadius radius;
  final Widget child;

  /// The key the active row wraps itself in, or null outside a highlight.
  static GlobalKey? keyOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_HighlightKey>()?.rowKey;

  @override
  State<SlidingHighlight> createState() => _SlidingHighlightState();
}

class _SlidingHighlightState extends State<SlidingHighlight> {
  final _rowKey = GlobalKey();
  Rect? _rect;
  Object? _measuredFor;
  bool _spring = false;

  void _measure() {
    if (!mounted) return;
    final host = context.findRenderObject() as RenderBox?;
    final row = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    final rect = host == null || row == null || !row.attached
        ? null
        : row.localToGlobal(Offset.zero, ancestor: host) & row.size;
    // Spring only when the active row changed; resizes and first placement jump.
    final spring =
        _rect != null && rect != null && _measuredFor != widget.activeId;
    _measuredFor = widget.activeId;
    if (rect == _rect) return;
    setState(() {
      _rect = rect;
      _spring = spring;
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final rect = _rect;
    return _HighlightKey(
      rowKey: _rowKey,
      child: Stack(
        children: [
          if (rect != null)
            AnimatedPositioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              duration: _spring && !Motion.reduced(context)
                  ? Motion.springDuration
                  : Duration.zero,
              curve: Motion.spring,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: widget.radius,
                ),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _HighlightKey extends InheritedWidget {
  const _HighlightKey({required this.rowKey, required super.child});

  final GlobalKey rowKey;

  @override
  bool updateShouldNotify(_HighlightKey oldWidget) =>
      rowKey != oldWidget.rowKey;
}

/// Shakes [child] sideways once when [NudgeState.nudge] is called, e.g. on
/// an invalid form submit.
class Nudge extends StatefulWidget {
  const Nudge({super.key, required this.child});

  final Widget child;

  @override
  State<Nudge> createState() => NudgeState();
}

class NudgeState extends State<Nudge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  static final _dx = TweenSequence<double>([
    for (final (a, b) in const [
      (0.0, -4.0),
      (-4.0, 4.0),
      (4.0, -2.0),
      (-2.0, 0.0),
    ])
      TweenSequenceItem(
        tween: Tween(begin: a, end: b),
        weight: 1,
      ),
  ]).chain(CurveTween(curve: Curves.easeOut));

  void nudge() {
    if (!Motion.reduced(context)) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => Transform.translate(
        offset: Offset(_dx.evaluate(_controller), 0),
        child: child,
      ),
    );
  }
}

/// [text] with a strike line that grows across it, left to right, when
/// [struck] turns true (and shrinks back when it turns false). Replaces a
/// `TextDecoration.lineThrough`, so the line follows each wrapped line.
class AnimatedStrike extends StatelessWidget {
  const AnimatedStrike(
    this.text, {
    super.key,
    required this.struck,
    required this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final bool struck;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      style: style,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(end: struck ? 1 : 0),
      duration: Motion.reduced(context) ? Duration.zero : Motion.slow,
      curve: Motion.out,
      child: label,
      builder: (context, t, child) => t == 0
          ? child!
          : CustomPaint(
              foregroundPainter: _StrikePainter(
                text: text,
                style: DefaultTextStyle.of(context).style.merge(style),
                maxLines: maxLines,
                ellipsis: overflow == TextOverflow.ellipsis,
                direction: Directionality.of(context),
                scaler: MediaQuery.textScalerOf(context),
                progress: t,
              ),
              child: child,
            ),
    );
  }
}

class _StrikePainter extends CustomPainter {
  _StrikePainter({
    required this.text,
    required this.style,
    required this.maxLines,
    required this.ellipsis,
    required this.direction,
    required this.scaler,
    required this.progress,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;
  final bool ellipsis;
  final TextDirection direction;
  final TextScaler scaler;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      ellipsis: ellipsis ? '\u2026' : null,
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: size.width);
    final lines = painter.computeLineMetrics();
    final total = lines.fold<double>(0, (sum, l) => sum + l.width);
    var budget = total * progress;
    final paint = Paint()
      ..color = style.color ?? const Color(0xFF000000)
      ..strokeWidth = 1.5;
    for (final l in lines) {
      if (budget <= 0) break;
      final w = math.min(l.width, budget);
      final y = l.baseline - l.ascent * 0.32;
      canvas.drawLine(Offset(l.left, y), Offset(l.left + w, y), paint);
      budget -= w;
    }
    painter.dispose();
  }

  @override
  bool shouldRepaint(_StrikePainter old) =>
      old.progress != progress || old.text != text || old.style != style;
}

/// A rounded placeholder bar with a light sweeping across it, shown while
/// content loads. Static under Reduce motion.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 12});

  final double? width;
  final double height;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.onSurface.withValues(alpha: 0.08);
    final shine = scheme.onSurface.withValues(alpha: 0.14);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final x = -1.5 + 3 * _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.height / 2),
            gradient: LinearGradient(
              begin: Alignment(x - 1, 0),
              end: Alignment(x + 1, 0),
              colors: [base, shine, base],
            ),
          ),
        );
      },
    );
  }
}

/// A thin accent bar that drains from full to empty over [duration], so a
/// toast shows how long it will stay. Fills the width its parent stretches
/// it to.
class DrainBar extends StatelessWidget {
  const DrainBar({super.key, required this.duration, this.color});

  final Duration duration;

  /// Defaults to the surrounding text colour, faded.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color =
        this.color ??
        (DefaultTextStyle.of(context).style.color ?? Colors.white).withValues(
          alpha: 0.6,
        );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: duration,
      // Scaled, not FractionallySizedBox: that divides its intrinsic width
      // by the factor, which reaches 0 inside the toast's IntrinsicWidth.
      builder: (context, v, bar) => Transform.scale(
        scaleX: v,
        alignment: Alignment.centerLeft,
        child: bar,
      ),
      child: SizedBox(height: 2, child: ColoredBox(color: color)),
    );
  }
}

/// Wraps the whole app: when the theme's brightness flips, the new theme
/// grows as a circle from the last tap, over a snapshot of the old one.
/// Put it in `MaterialApp.builder` (with `themeAnimationDuration` zero so
/// the snapshot is the old theme, not a blend).
class ThemeReveal extends StatefulWidget {
  const ThemeReveal({super.key, required this.child});

  final Widget child;

  @override
  State<ThemeReveal> createState() => _ThemeRevealState();
}

class _ThemeRevealState extends State<ThemeReveal>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: Motion.reveal)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _clear();
        });
  Brightness? _brightness;
  Offset? _lastTap;
  Offset _origin = Offset.zero;
  ui.Image? _old;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    // Runs before the subtree rebuilds, so the boundary still holds the old frame.
    if (_brightness != null && brightness != _brightness) _capture();
    _brightness = brightness;
  }

  void _capture() {
    final boundary =
        _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null ||
        !boundary.hasSize ||
        (kDebugMode && boundary.debugNeedsPaint) ||
        Motion.reduced(context)) {
      return;
    }
    _old?.dispose();
    _old = boundary.toImageSync(
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    _origin = _lastTap ?? boundary.size.center(Offset.zero);
    _controller.forward(from: 0);
  }

  void _clear() {
    setState(() {
      _old?.dispose();
      _old = null;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _old?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _lastTap = e.localPosition,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(key: _boundary, child: widget.child),
          if (old != null)
            IgnorePointer(
              child: CustomPaint(
                painter: _RevealPainter(old, _origin, _controller),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints the old theme's snapshot everywhere outside a circle that grows
/// from [origin] until it covers the screen.
class _RevealPainter extends CustomPainter {
  _RevealPainter(this.image, this.origin, this.progress)
    : super(repaint: progress);

  final ui.Image image;
  final Offset origin;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final far = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - origin).distance).reduce(math.max);
    final r = far * Motion.out.transform(progress.value);
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addOval(Rect.fromCircle(center: origin, radius: r)),
    );
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RevealPainter old) =>
      old.image != image || old.origin != origin;
}

/// An AnimatedSwitcher transition for small popups (toasts): fades in while
/// rising 8px and growing from 98%.
Widget popTransition(Widget child, Animation<double> animation) {
  final curved = CurvedAnimation(parent: animation, curve: Motion.out);
  return FadeTransition(
    opacity: curved,
    child: AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, 8 * (1 - curved.value)),
        child: Transform.scale(scale: 0.98 + 0.02 * curved.value, child: child),
      ),
    ),
  );
}

/// True for an item created in the last two seconds, so its row grows in.
bool isJustAdded(DateTime createdAt) =>
    DateTime.now().difference(createdAt) < const Duration(seconds: 2);
