import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:procheck/theme/motion.dart';
import 'package:procheck/theme/nocturne_theme.dart';
import 'package:procheck/widgets/motion_widgets.dart';
import 'package:procheck/widgets/nocturne/nocturne_widgets.dart';

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

  testWidgets('ThemeReveal covers a brightness flip, then clears', (
    tester,
  ) async {
    Widget app(Brightness b) => MaterialApp(
      theme: ThemeData(brightness: b),
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => ThemeReveal(child: child!),
      home: const Scaffold(body: Text('page')),
    );
    await tester.pumpWidget(app(Brightness.light));
    await tester.pumpWidget(app(Brightness.dark));
    await tester.pump(const Duration(milliseconds: 100));
    final reveal = find.byWidgetPredicate(
      (w) => w is CustomPaint && '${w.painter.runtimeType}' == '_RevealPainter',
    );
    expect(reveal, findsOneWidget);
    await tester.pumpAndSettle();
    expect(reveal, findsNothing);
  });

  testWidgets('a loading NocturneButton ignores taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildNocturneTheme(
          brightness: Brightness.light,
          accent: const Color(0xFF3F5BE8),
        ),
        home: Scaffold(
          body: NocturneButton(
            label: 'Sign in',
            loading: true,
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(NocturneButton));
    expect(taps, 0);
  });

  testWidgets('AnimatedStrike draws its line only once struck', (tester) async {
    Widget row(bool struck) => MaterialApp(
      home: AnimatedStrike(
        'Buy groceries',
        struck: struck,
        style: const TextStyle(),
      ),
    );
    final painted = find.descendant(
      of: find.byType(AnimatedStrike),
      matching: find.byType(CustomPaint),
    );
    await tester.pumpWidget(row(false));
    expect(painted, findsNothing);
    await tester.pumpWidget(row(true));
    await tester.pumpAndSettle();
    expect(painted, findsOneWidget);
  });
}
