import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_config.dart';
import '../providers/projects_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/brand_mark.dart';
import '../widgets/brand_splash.dart';
import 'app_shell.dart';
import 'login_screen.dart';

/// Shown on launch: the animated ProCheck Teranov logo (see [BrandSplash],
/// held until its animation has finished so it is never cut off halfway; ~1 s
/// with reduced motion), then hands off
/// to [AppShell] (or [LoginScreen], when this build is configured for
/// Supabase and nobody's signed in yet — see [isSupabaseConfigured]). Hive
/// is already initialized by the time this appears (awaited in main()
/// before runApp), so this is purely a branding beat.
///
/// When signed in, it also waits for both notifiers' [profileReady] future
/// before handing off — otherwise a task/project created in the instant
/// after launch would be stamped with a blank owner/department (see
/// [TasksNotifier]/[ProjectsNotifier]) and never sync. Capped at 5 seconds
/// so a slow/offline profile fetch doesn't strand the user on the splash
/// screen; local-only creation still works once in the app shell.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  late final bool _reduceMotion;

  @override
  void initState() {
    super.initState();
    _reduceMotion = ref.read(settingsProvider).reduceMotion;
    final hold = _reduceMotion
        ? const Duration(milliseconds: 1100)
        : BrandSplash.duration;
    Timer(hold, () async {
      if (!mounted) return;
      final needsSignIn =
          isSupabaseConfigured && supabase.auth.currentSession == null;
      if (!needsSignIn && isSupabaseConfigured) {
        await Future.wait([
          ref.read(tasksProvider.notifier).profileReady,
          ref.read(projectsProvider.notifier).profileReady,
        ]).timeout(const Duration(seconds: 5), onTimeout: () => const []);
      }
      if (!mounted) return;
      // A short cross-fade, as the logo package's splash fades out (.25 s).
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 250),
          pageBuilder: (_, _, _) =>
              needsSignIn ? const LoginScreen() : const AppShell(),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        _reduceMotion || MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: BrandColors.of(context).bg,
      body: Center(child: BrandSplash(reduceMotion: reduceMotion)),
    );
  }
}
