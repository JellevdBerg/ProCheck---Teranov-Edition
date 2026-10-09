// Self-review screenshots: renders the app with seeded data at several window
// sizes in both themes into `.screenshots/`. Skipped unless SCREENSHOTS=1:
//   SCREENSHOTS=1 flutter test test/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:procheck/data/hive_setup.dart';
import 'package:procheck/data/test_data_seed.dart';
import 'package:procheck/main.dart';
import 'package:procheck/providers/projects_provider.dart';
import 'package:procheck/providers/settings_provider.dart';
import 'package:procheck/providers/tasks_provider.dart';
import 'package:procheck/screens/app_screen.dart';

void main() {
  final enabled = Platform.environment['SCREENSHOTS'] == '1';
  late Directory tempDir;

  setUpAll(() async {
    if (!enabled) return;
    tempDir = await Directory.systemTemp.createTemp('procheck_shots_');
    await setUpHive(testDirectoryPath: tempDir.path);
    // flutter test renders every font as blocks unless loaded explicitly.
    Future<void> load(String family, List<String> paths) async {
      final loader = FontLoader(family);
      for (final path in paths) {
        loader.addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      }
      await loader.load();
    }

    await load('IBMPlexSans', [
      'assets/fonts/IBMPlexSans-Regular.ttf',
      'assets/fonts/IBMPlexSans-Medium.ttf',
      'assets/fonts/IBMPlexSans-SemiBold.ttf',
    ]);
    await load('MaterialIcons', [
      'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  });

  const sizes = {'narrow': Size(720, 900), 'wide': Size(2200, 1200)};
  const screens = [
    AppScreen.projects,
    AppScreen.today,
    AppScreen.dashboard,
    AppScreen.calendar,
    AppScreen.templates,
    AppScreen.settings,
  ];
  final only = Platform.environment['SHOT_SIZES']?.split(',');
  final extra = {
    for (final e in (only ?? const <String>[]))
      if (e.contains('x'))
        e: Size(
          double.parse(e.split('x')[0]),
          double.parse(e.split('x')[1]),
        ),
  };

  for (final entry in {...sizes, ...extra}.entries) {
    for (final dark in [false, true]) {
      for (final screen in screens) {
        testWidgets(
          '${screen.name} ${dark ? 'dark' : 'light'} ${entry.key}',
          (tester) async {
            tester.view.physicalSize = entry.value;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);

            final container = ProviderContainer();
            addTearDown(container.dispose);
            final seed = buildTestData();
            container.read(projectsProvider.notifier).restoreAll(seed.projects);
            container.read(tasksProvider.notifier).restoreAll(seed.tasks);
            final settings = container.read(settingsProvider.notifier);
            settings.setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);

            final key = GlobalKey();
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: RepaintBoundary(key: key, child: const ProcheckApp()),
              ),
            );
            await tester.pump(const Duration(milliseconds: 1200));
            await tester.pumpAndSettle();
            await tester.tap(find.text(screen.name[0].toUpperCase() + screen.name.substring(1)).first);
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);

            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory('.screenshots')..createSync();
              File(
                '${dir.path}/${screen.name}_${dark ? 'dark' : 'light'}_${entry.key}.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
            });
          },
          skip: !enabled,
        );
      }
    }
  }
}
