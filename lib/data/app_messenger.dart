import 'package:flutter/material.dart';

import '../widgets/motion_widgets.dart';

/// Lets a Riverpod notifier (no [BuildContext] of its own) surface a toast
/// when a write it fired off in the background gets rejected by the
/// server — e.g. an RLS policy refusing a sync. Wired into [MaterialApp] in
/// main.dart.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

const _life = Duration(seconds: 4);

void showSyncFailureToast(String message) {
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          const SizedBox(height: 8),
          const DrainBar(duration: _life),
        ],
      ),
      duration: _life,
    ),
  );
}
