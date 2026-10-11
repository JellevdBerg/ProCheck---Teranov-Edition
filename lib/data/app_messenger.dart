import 'package:flutter/material.dart';

/// Lets a Riverpod notifier (no [BuildContext] of its own) surface a toast
/// when a write it fired off in the background gets rejected by the
/// server — e.g. an RLS policy refusing a sync. Wired into [MaterialApp] in
/// main.dart.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showSyncFailureToast(String message) {
  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(content: Text(message)),
  );
}
