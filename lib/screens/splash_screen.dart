import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/supabase_config.dart';
import '../providers/projects_provider.dart';
import '../providers/tasks_provider.dart';
import '../widgets/app_logo.dart';
import 'app_shell.dart';
import 'login_screen.dart';

/// Shown briefly on launch: just the logo and the app name, then hands off
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
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1100), () async {
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => needsSignIn ? const LoginScreen() : const AppShell(),
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
            Text('ProCheck', style: theme.textTheme.headlineMedium),
          ],
        ),
      ),
    );
  }
}
