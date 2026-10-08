import 'dart:async';

import 'package:flutter/material.dart';

import '../data/supabase_config.dart';
import '../widgets/app_logo.dart';
import 'app_shell.dart';
import 'login_screen.dart';

/// Shown briefly on launch: just the logo and the app name, then hands off
/// to [AppShell] (or [LoginScreen], when this build is configured for
/// Supabase and nobody's signed in yet — see [isSupabaseConfigured]). Hive
/// is already initialized by the time this appears (awaited in main()
/// before runApp), so this is purely a branding beat.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      final needsSignIn =
          isSupabaseConfigured && supabase.auth.currentSession == null;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              needsSignIn ? const LoginScreen() : const AppShell(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 96),
            const SizedBox(height: 20),
            Text(
              'ProCheck',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
