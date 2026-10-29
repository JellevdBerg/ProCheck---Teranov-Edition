import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/app_messenger.dart';
import 'data/hive_setup.dart';
import 'data/notification_service.dart';
import 'data/supabase_config.dart';
import 'providers/settings_provider.dart';
import 'screens/splash_screen.dart';
import 'theme/nocturne_theme.dart';
import 'widgets/motion_widgets.dart';

/// The default [MaterialScrollBehavior] only lets touch/stylus pointers
/// drag-to-scroll — a mouse click-and-drag is deliberately excluded, since
/// on most scrollables that would fight with text selection. This app
/// leans on drag-to-scroll for its horizontally-scrolling project grid
/// (see ProjectsScreen), which has no selectable text to conflict with, so
/// mouse is added back in for every scrollable.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setUpHive();
  await setUpSupabase();
  await NotificationService.instance.initialize();
  runApp(const ProviderScope(child: ProcheckApp()));
}

class ProcheckApp extends ConsumerWidget {
  const ProcheckApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final accent = settings.accentColor;
    return MaterialApp(
      title: 'ProCheck',
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildNocturneTheme(brightness: Brightness.light, accent: accent),
      darkTheme: buildNocturneTheme(brightness: Brightness.dark, accent: accent),
      scrollBehavior: const AppScrollBehavior(),
      // ThemeReveal animates the switch; a blend here would spoil its snapshot.
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => ThemeReveal(child: child!),
      home: const SplashScreen(),
    );
  }
}
