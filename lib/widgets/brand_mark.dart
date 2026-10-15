import 'package:flutter/material.dart';

/// ProCheck Teranov brand colours, straight from the logo package's tokens.
class BrandColors {
  const BrandColors._({
    required this.bg,
    required this.ink,
    required this.muted,
    required this.sheenEdge,
    required this.sheenCore,
  });

  static const accent = Color(0xFF2557D6);

  static const _light = BrandColors._(
    bg: Color(0xFFF3F4F1),
    ink: Color(0xFF14171C),
    muted: Color(0xFF5A616B),
    sheenEdge: Color(0xFF6B737D),
    sheenCore: Color(0xFFC9CED4),
  );
  static const _dark = BrandColors._(
    bg: Color(0xFF14171C),
    ink: Color(0xFFECEEEA),
    muted: Color(0xFFA2A9B3),
    sheenEdge: Color(0xFF9AA1AA),
    sheenCore: Color(0xFFFFFFFF),
  );

  /// Ink = brackets and wordmark; the "on-light" files on a light theme, the
  /// "on-dark" files on a dark one.
  static BrandColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  final Color bg;
  final Color ink;
  final Color muted;
  final Color sheenEdge;
  final Color sheenCore;
}

/// The logo mark (a tick inside square brackets), drawn from the package's
/// `procheck-mark-*` / `procheck-mark-small-*` SVG geometry. Below 24 px the
/// package's thicker "small" mark is used, as its README requires.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ProCheck',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _MarkPainter(BrandColors.of(context).ink, small: size < 24),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.ink, {required this.small});

  final Color ink;
  final bool small;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48);
    final a = small ? 5.0 : 7.0; // outer bracket edge, near
    final z = small ? 43.0 : 41.0; // outer bracket edge, far
    final brackets = Path()
      ..moveTo(small ? 13 : 14, a)
      ..lineTo(a, a)
      ..lineTo(a, z)
      ..lineTo(small ? 13 : 14, z)
      ..moveTo(small ? 35 : 34, a)
      ..lineTo(z, a)
      ..lineTo(z, z)
      ..lineTo(small ? 35 : 34, z);
    final tick = small
        ? (Path()
            ..moveTo(15, 25)
            ..lineTo(21.5, 31.5)
            ..lineTo(33.5, 16))
        : (Path()
            ..moveTo(15, 24.5)
            ..lineTo(21.5, 31)
            ..lineTo(33.5, 17));
    Paint stroke(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..color = c
      ..strokeWidth = w
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = true;
    canvas.drawPath(brackets, stroke(ink, small ? 7 : 4));
    canvas.drawPath(tick, stroke(BrandColors.accent, small ? 8 : 4.5));
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.ink != ink || old.small != small;
}
