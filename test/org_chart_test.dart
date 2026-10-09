import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:procheck/data/hive_setup.dart';
import 'package:procheck/models/department.dart';
import 'package:procheck/models/department_role.dart';
import 'package:procheck/models/profile.dart';
import 'package:procheck/providers/department_members_provider.dart';
import 'package:procheck/providers/departments_provider.dart';
import 'package:procheck/providers/roles_provider.dart';
import 'package:procheck/screens/org_chart_screen.dart';
import 'package:procheck/theme/nocturne_theme.dart';

void main() {
  late Directory tempDir;
  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('procheck_org_');
    await setUpHive(testDirectoryPath: tempDir.path);
    if (Platform.environment['SCREENSHOTS'] == '1') {
      final loader = FontLoader('IBMPlexSans');
      for (final f in ['Regular', 'Medium', 'SemiBold']) {
        loader.addFont(Future.value(ByteData.sublistView(
            File('assets/fonts/IBMPlexSans-$f.ttf').readAsBytesSync())));
      }
      await loader.load();
    }
  });

  final depts = [
    const Department(id: 'op', name: 'Operator', isOperator: true, isIt: false),
    const Department(id: 'it', name: 'IT', isOperator: false, isIt: true),
    for (var i = 0; i < 5; i++)
      Department(id: 'd$i', name: ['Stats', 'Finance', 'Legal', 'Data', 'HR'][i], isOperator: false, isIt: false),
  ];
  final people = [
    const Profile(id: 'u0', email: 'a', username: 'boss', displayName: 'The Operator', role: UserRole.manager, departmentId: 'op'),
    for (var i = 0; i < 6; i++)
      Profile(id: 'it$i', email: 'a', username: 'it$i', displayName: 'IT Person $i', role: i < 2 ? UserRole.manager : UserRole.member, departmentId: 'it'),
    for (var d = 0; d < 5; d++)
      for (var i = 0; i < 4 + d * 3; i++)
        Profile(id: 'p$d-$i', email: 'a', username: 'u$d$i', displayName: 'Person $d.$i', role: i == 0 ? UserRole.manager : UserRole.member, departmentId: 'd$d', customRoleId: i == 1 ? 'r1' : null, createdAt: DateTime(2026, 1, 5)),
  ];

  for (final dark in [false, true]) {
    for (final size in const [Size(900, 700), Size(360, 700)]) {
      testWidgets('org chart ${dark ? 'dark' : 'light'} ${size.width.toInt()}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        final key = GlobalKey();
        await tester.pumpWidget(ProviderScope(
          overrides: [
            departmentsProvider.overrideWith((ref) async => depts),
            departmentMembersProvider.overrideWith((ref) async => people),
            departmentRolesProvider.overrideWith((ref) async => const [
              DepartmentRole(id: 'r1', departmentId: 'd0', name: 'Senior', createProjects: true),
            ]),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: buildNocturneTheme(
                  brightness: dark ? Brightness.dark : Brightness.light,
                  accent: nocturneAccentPalette.first),
              home: const OrgChartScreen(),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        // hover a person: the detail card appears
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);
        await gesture.moveTo(Offset(size.width / 2, size.height / 2));
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (Platform.environment['SCREENSHOTS'] == '1') {
          await tester.runAsync(() async {
            final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final img = await b.toImage();
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            final dir = Directory('.screenshots')..createSync();
            File('${dir.path}/org_${dark ? 'dark' : 'light'}_${size.width.toInt()}.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
      });
    }
  }
}
