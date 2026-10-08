import 'dart:async';

import 'package:flutter/material.dart';

import '../data/supabase_config.dart';
import '../theme/nocturne_theme.dart';
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

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _BrandBackdrop(),
          Center(
            child: FadeTransition(
              opacity: _controller,
              child: ScaleTransition(
                scale: Tween(
                  begin: 0.94,
                  end: 1.0,
                ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLogo(size: 96),
                    const SizedBox(height: 20),
                    Text(
                      'ProCheck',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet radial vignette behind the brand mark — built from the theme's
/// own neutral ramp (never the accent, which is reserved for interactive
/// elements) so it reads as a deliberate backdrop rather than a flat
/// `Scaffold` background, and stays correct whatever accent the user picks.
class _BrandBackdrop extends StatelessWidget {
  const _BrandBackdrop();

  @override
  Widget build(BuildContext context) {
    final tokens = context.nocturne;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 1.2,
          colors: [tokens.surface, tokens.bg],
        ),
      ),
    );
  }
}
