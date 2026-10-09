import 'dart:ui';

import 'package:flutter/material.dart';

/// Shows [builder]'s content as a centered rectangle over a blurred backdrop,
/// instead of the plain dim-only barrier `showDialog` normally uses. All of
/// the app's dialogs and quick-action prompts go through this so they read
/// as one consistent style.
Future<T?> showBlurredDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (context, animation, secondaryAnimation) {
      return SafeArea(
        child: Center(child: Builder(builder: builder)),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final value = Curves.easeOut.transform(animation.value);
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 3 * value, sigmaY: 3 * value),
            child: Opacity(
              opacity: value,
              child: Transform.scale(scale: 0.97 + 0.03 * value, child: child),
            ),
          );
        },
      );
    },
  );
}
