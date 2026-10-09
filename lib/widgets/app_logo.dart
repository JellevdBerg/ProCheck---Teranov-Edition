import 'package:flutter/material.dart';

import 'panel/panel.dart';

/// The ProCheck logo mark, rendered from the app's icon asset, set in a small
/// raised bezel so its dark tile stays visible on the graphite finish.
///
/// Used both in the [HomeScreen] app bar (small) and on the splash screen
/// (large) — just at different sizes. The bezel is drawn inside [size].
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    final inset = size * 0.08;
    return DecoratedBox(
      decoration: panelDecoration(context, radius: size * 0.22),
      child: Padding(
        padding: EdgeInsets.all(inset),
        child: Image.asset(
          'assets/icon/procheck_logo.png',
          width: size - inset * 2,
          height: size - inset * 2,
        ),
      ),
    );
  }
}
