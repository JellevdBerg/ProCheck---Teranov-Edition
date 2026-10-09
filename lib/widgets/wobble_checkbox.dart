import 'package:flutter/material.dart';

import '../theme/nocturne_theme.dart';
import 'panel/panel.dart';

/// The check-off control: a toggle switch with a lamp, snapping with a
/// slight overshoot when its value flips. Still a real [Checkbox] underneath
/// (transparent, scaled up to the switch's size) so tap, keyboard, focus and
/// semantics behave exactly as before; the switch is only the picture.
/// The overshoot is skipped when [reduceMotion] is set, matching the rest
/// of the app.
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
  static const _w = 38.0;
  static const _h = 22.0;

  // Plays for the full [WobbleCheckbox.duration] on every flip: a small
  // housing "settle" after the knob snaps. Also what keeps frames coming
  // until anything sequenced on that duration has fired.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WobbleCheckbox.duration,
  );

  late final Animation<double> _settle = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.95), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.03), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.03, end: 1.0), weight: 2),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

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
    final value = widget.value;
    final reduceMotion = widget.reduceMotion;
    final t = context.nocturne;
    final accent = context.nocturneAccent;
    final knobColor = value ? Color.lerp(t.surface, accent, 0.35)! : t.surface;

    return SizedBox(
      width: _w + 6,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) =>
                  Transform.scale(scale: _settle.value, child: child),
              child: Container(
                width: _w,
                height: _h,
                padding: const EdgeInsets.all(2),
                decoration: panelDecoration(
                  context,
                  depth: PanelDepth.recessed,
                  radius: 4,
                ),
                child: Stack(
                  children: [
                    // The lamp sits opposite the knob, in the exposed half.
                    AnimatedAlign(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 140),
                      alignment: value
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: IndicatorLamp(on: value, size: 7),
                      ),
                    ),
                    AnimatedAlign(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      curve: Curves.easeOutBack,
                      alignment: value
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 17,
                        height: _h - 6,
                        decoration: panelDecoration(
                          context,
                          radius: 3,
                          fill: knobColor,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < 3; i++) ...[
                              if (i > 0) const SizedBox(width: 2),
                              Container(
                                width: 1.5,
                                height: 8,
                                color: t.neutral700,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Invisible but fully functional: hit target, focus ring, semantics.
          Transform.scale(
            scale: 2.0,
            child: Checkbox(
              value: value,
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
