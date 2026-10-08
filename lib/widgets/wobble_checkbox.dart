import 'package:flutter/material.dart';

/// A [Checkbox] that plays a quick squash-and-tilt wobble whenever its value
/// flips, as a bit of satisfying feedback for checking off a task. Skipped
/// entirely when [reduceMotion] is set, matching the rest of the app.
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

  /// How long the wobble takes to play out. Exposed so other widgets that
  /// need to sequence something after the bounce (e.g. auto-removing a
  /// completed standalone task) can wait for the same duration rather than
  /// guessing at a matching one of their own.
  static const duration = Duration(milliseconds: 350);

  @override
  State<WobbleCheckbox> createState() => _WobbleCheckboxState();
}

class _WobbleCheckboxState extends State<WobbleCheckbox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WobbleCheckbox.duration,
  );

  late final Animation<double> _wobble = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.15), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -0.15, end: 0.12), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.12, end: -0.06), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -0.06, end: 0.0), weight: 1),
  // Industrial Skeuomorphism retune: a snappier mechanical-click curve than
  // the original plain ease-out, same duration. Not `easeOutBack` —
  // shortcut: that curve overshoots past t=1.0, which `TweenSequence`
  // asserts against (it isn't a `Tween`-only-safe curve), so a true
  // spring-overshoot feel here would need rebuilding this as nested plain
  // `Tween`s instead of one `TweenSequence`; upgrade this if that's wanted.
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart));

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.95), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 2),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart));

  @override
  void didUpdateWidget(covariant WobbleCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !widget.reduceMotion) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final checkbox = Checkbox(value: widget.value, onChanged: widget.onChanged);
    if (widget.reduceMotion) return checkbox;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.rotate(
        angle: _wobble.value,
        child: Transform.scale(scale: _scale.value, child: child),
      ),
      child: checkbox,
    );
  }
}
