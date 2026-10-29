import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:procheck/theme/motion.dart';
import 'package:procheck/widgets/motion_widgets.dart';

void main() {
  test('the spring overshoots about 9% and lands on 1', () {
    final samples = [
      for (var i = 0; i <= 100; i++) Motion.spring.transform(i / 100),
    ];
    final peak = samples.reduce((a, b) => a > b ? a : b);
    expect(peak, closeTo(1.09, 0.02));
    expect(samples.last, 1);
    expect((samples[98] - 1).abs(), lessThan(0.01));
  });

  testWidgets('StaggerIn fades its row in and finishes fully visible', (
    tester,
  ) async {
    Motion.screenShownAt = DateTime.now();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: StaggerIn(index: 2, child: Text('row')),
      ),
    );
    double opacity() => tester
        .widget<FadeTransition>(find.byType(FadeTransition))
        .opacity
        .value;
    expect(opacity(), 0);
    await tester.pumpAndSettle();
    expect(opacity(), 1);
  });
}
