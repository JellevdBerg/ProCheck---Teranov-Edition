import 'package:flutter/material.dart';

import '../theme/nocturne_theme.dart';
import '../widgets/panel/panel.dart';

/// A quiet bordered panel: icon + message shown when a screen has nothing to
/// display.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.nocturne;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NocturneSpace.s4),
        child: DecoratedBox(
          decoration: panelDecoration(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NocturneSpace.s6,
              vertical: NocturneSpace.s6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 40, color: t.neutral600),
                const SizedBox(height: NocturneSpace.s3),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: t.neutral500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
