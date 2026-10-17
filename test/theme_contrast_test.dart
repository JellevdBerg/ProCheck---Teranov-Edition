import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:procheck/theme/nocturne_theme.dart';

void main() {
  for (final b in Brightness.values) {
    final t = b == Brightness.dark ? NocturneColors.dark : NocturneColors.light;
    test('every accent swatch holds 4.5:1 in $b', () {
      for (final swatch in nocturneAccentPalette) {
        final a = tuneAccent(swatch, b);
        expect(contrastRatio(a, t.surface), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(a, onColor(a)), greaterThanOrEqualTo(4.5));
      }
    });
    test('status colours hold 4.5:1 on bg in $b', () {
      for (final c in [t.done, t.danger, t.warn, t.low]) {
        expect(contrastRatio(c, t.bg), greaterThanOrEqualTo(4.5));
      }
    });
  }
}
