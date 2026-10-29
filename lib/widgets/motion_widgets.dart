import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Fades and slides [child] up into place, [index] steps of [Motion.stagger]
/// after the screen appears. Rows past the first dozen, and rows built well
/// after the screen changed (scrolling, new items), show at once.
class StaggerIn extends StatefulWidget {
  const StaggerIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final i = widget.index;
    final fresh =
        DateTime.now().difference(Motion.screenShownAt) < StaggerIn._window;
    if (i >= StaggerIn._maxStaggered || !fresh || Motion.reduced(context)) {
      return;
    }
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
    return FadeTransition(
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
