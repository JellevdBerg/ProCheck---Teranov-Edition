import 'package:flutter/material.dart';

import '../theme/nocturne_theme.dart';
import '../widgets/panel/panel.dart';

/// A blank engraved plate: icon + message shown when a screen has nothing to
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
        padding: const EdgeInsets.all(32),
        child: DecoratedBox(
          decoration: panelDecoration(context, depth: PanelDepth.recessed),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: t.neutral600),
                const SizedBox(height: 14),
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
