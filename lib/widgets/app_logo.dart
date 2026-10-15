import 'package:flutter/material.dart';

import 'brand_mark.dart';

/// The ProCheck logo mark (see [BrandMark]).
///
/// Used both in the sidebar (small) and on the login screen (larger) — just
/// at different sizes.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => BrandMark(size: size);
}
