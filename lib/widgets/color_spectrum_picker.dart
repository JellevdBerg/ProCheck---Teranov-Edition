import 'package:flutter/material.dart';

import '../theme/nocturne_theme.dart';
import 'nocturne/nocturne_widgets.dart';

/// A spectrum + hue-slider color picker, with an optional hex field for
/// entering an exact value. Replaces the old hex-only dialog; same
/// `showCustomColorDialog` entry point and return type so call sites don't
/// need to change.
Future<Color?> showCustomColorDialog(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    builder: (context) => _ColorPickerDialog(initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hexController = TextEditingController(
    text: _hexOf(_hsv.toColor()),
  );
  late final FocusNode _hexFocusNode = FocusNode()
    ..addListener(() {
      // Normalize/resync the field once the user taps away from a partial
      // or invalid edit, rather than leaving stale text behind.
      if (!_hexFocusNode.hasFocus) _hexController.text = _hexOf(_hsv.toColor());
    });

  @override
  void dispose() {
    _hexController.dispose();
    _hexFocusNode.dispose();
    super.dispose();
  }

  static String _hexOf(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  void _updateFromSpectrum(double saturation, double value) {
    setState(() {
      _hsv = _hsv.withSaturation(saturation).withValue(value);
      _hexController.text = _hexOf(_hsv.toColor());
    });
  }

  void _updateHue(double hue) {
    setState(() {
      _hsv = _hsv.withHue(hue);
      _hexController.text = _hexOf(_hsv.toColor());
    });
  }

  void _updateFromHex(String input) {
    var hex = input.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return;
    setState(() => _hsv = HSVColor.fromColor(Color(parsed)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    final color = _hsv.toColor();

    return AlertDialog(
      title: const Text('Custom accent color'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1.6,
              child: _SaturationValueField(
                hsv: _hsv,
                onChanged: _updateFromSpectrum,
              ),
            ),
            const SizedBox(height: NocturneSpace.s3),
            _HueSlider(hue: _hsv.hue, onChanged: _updateHue),
            const SizedBox(height: NocturneSpace.s3),
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: tokens.borderStrong),
                  ),
                ),
                const SizedBox(width: NocturneSpace.s2),
                Expanded(
                  child: TextField(
                    controller: _hexController,
                    focusNode: _hexFocusNode,
                    decoration: const InputDecoration(
                      labelText: 'Hex',
                      hintText: '#3F5BE8',
                      isDense: true,
                    ),
                    onSubmitted: _updateFromHex,
                    onEditingComplete: () =>
                        _updateFromHex(_hexController.text),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        NocturneButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        NocturneButton(
          label: 'Use color',
          variant: NocturneButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(color),
        ),
      ],
    );
  }
}

/// The saturation/value spectrum field for a fixed hue — horizontal drag
/// picks saturation, vertical drag picks value (brightness), with white
/// fading in from the left and black fading in from the bottom, same as any
/// standard OS color picker's spectrum square.
class _SaturationValueField extends StatelessWidget {
  const _SaturationValueField({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final void Function(double saturation, double value) onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void handle(Offset local) {
          final saturation = (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
          final value = 1 - (local.dy / constraints.maxHeight).clamp(0.0, 1.0);
          onChanged(saturation, value);
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(NocturneRadius.md),
          child: GestureDetector(
            onPanDown: (d) => handle(d.localPosition),
            onPanUpdate: (d) => handle(d.localPosition),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.white, Color(0x00FFFFFF)],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Colors.black],
                    ),
                  ),
                ),
                Positioned(
                  left: hsv.saturation * constraints.maxWidth - 9,
                  top: (1 - hsv.value) * constraints.maxHeight - 9,
                  child: _PickerDot(color: hsv.toColor()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The hue slider — drag anywhere along it to pick a hue (0-360); the fill
/// stays the full rainbow sweep regardless of the current saturation/value
/// so the track reads as a fixed reference, not a to-be-filled bar.
class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  static final _sweepColors = [
    for (var deg = 0; deg <= 360; deg += 30)
      HSVColor.fromAHSV(1, deg.toDouble() % 360, 1, 1).toColor(),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void handle(Offset local) {
          final fraction = (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
          onChanged(fraction * 360);
        }

        return SizedBox(
          height: 24,
          child: GestureDetector(
            onPanDown: (d) => handle(d.localPosition),
            onPanUpdate: (d) => handle(d.localPosition),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(NocturneRadius.md),
                  child: Container(
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: _sweepColors),
                    ),
                  ),
                ),
                Positioned(
                  left: (hue / 360) * constraints.maxWidth - 9,
                  top: 3,
                  child: _PickerDot(
                    color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The small ring-and-fill indicator shared by both the spectrum field and
/// the hue slider — a white ring reads on any fill color, dark or light.
class _PickerDot extends StatelessWidget {
  const _PickerDot({required this.color, this.size = 18});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Flat: a white ring with a hairline dark outer edge so it reads on any
    // fill, light or dark (no shadow).
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x66000000)),
        ),
        child: Container(
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    );
  }
}
