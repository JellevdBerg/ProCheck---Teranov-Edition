import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:procheck/data/hive_setup.dart';
import 'package:procheck/models/department.dart';
import 'package:procheck/models/profile.dart';
import 'package:procheck/providers/department_members_provider.dart';
import 'package:procheck/providers/departments_provider.dart';
import 'package:procheck/providers/task_templates_provider.dart';
import 'package:procheck/screens/admin_screen.dart';
import 'package:procheck/screens/settings_screen.dart';
import 'package:procheck/screens/task_template_editor_screen.dart';
import 'package:procheck/screens/team_screen.dart';
import 'package:procheck/screens/templates_screen.dart';
import 'package:procheck/theme/nocturne_theme.dart';

/// Pumps each restyled screen across the supported widths in both themes and
/// asserts nothing overflowed (overflow errors surface as exceptions).
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('procheck_layout_');
    await setUpHive(testDirectoryPath: tempDir.path);
    SharedPreferences.setMockInitialValues({});
    // Admin reads `supabase.auth.currentUser`; a client with a dummy URL is
    // enough (no network call is made, so nobody is signed in).
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows keeps the Hive files locked; the OS temp dir cleans up.
    }
  });

  const departments = [
    Department(id: 'd1', name: 'Operator', isOperator: true, isIt: false),
    Department(id: 'd2', name: 'IT', isOperator: false, isIt: true),
    Department(
      id: 'd3',
      name: 'A department with a rather long name to test ellipsis',
      isOperator: false,
      isIt: false,
    ),
  ];
  const people = [
    Profile(
      id: 'p1',
      email: 'a@procheck.local',
      username: 'a_very_long_username_for_layout',
      displayName: 'Alexandria Montgomery-Featherstonehaugh the Third',
      role: UserRole.manager,
      departmentId: 'd3',
    ),
    Profile(
      id: 'p2',
      email: 'b@procheck.local',
      username: 'b',
      displayName: 'Bo',
      role: UserRole.member,
      departmentId: 'd2',
    ),
    Profile(
      id: 'p3',
      email: 'c@procheck.local',
      username: 'c',
      displayName: 'Cy',
      role: UserRole.member,
    ),
  ];

  const widths = [360.0, 720.0, 1280.0, 2000.0, 2560.0];

  final screens = <String, Widget Function()>{
    'settings': () => const SettingsScreen(),
    'admin': () => const AdminScreen(),
    'team': () => const TeamScreen(),
    'templates': () => const TemplatesScreen(),
    'template editor': () => const TaskTemplateEditorScreen(),
  };

  for (final entry in screens.entries) {
    for (final brightness in Brightness.values) {
      for (final width in widths) {
        testWidgets('${entry.key} at $width (${brightness.name})', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                departmentsProvider.overrideWith((ref) async => departments),
                departmentMembersProvider.overrideWith((ref) async => people),
                isOperatorProvider.overrideWith((ref) async => true),
              ],
              child: MaterialApp(
                theme: buildNocturneTheme(
                  brightness: brightness,
                  accent: nocturneAccentPalette.first,
                ),
                home: Scaffold(body: entry.value()),
              ),
            ),
          );
          if (entry.key == 'templates') {
            final container = ProviderScope.containerOf(
              tester.element(find.byType(Scaffold)),
            );
            final notifier = container.read(taskTemplatesProvider.notifier);
            notifier.addTemplate(
              'A template with a very long name that has to wrap or ellipsize',
              ['one', 'two'],
            );
            notifier.addTemplate('Short', []);
          }
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
