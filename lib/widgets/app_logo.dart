import 'package:flutter/material.dart';

/// The ProCheck logo mark, rendered from the app's icon asset.
///
/// Used both in the sidebar (small) and on the splash/login screens (large)
/// — just at different sizes.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/icon/procheck_logo.png',
        width: size,
        height: size,
      ),
    );
  }
}
