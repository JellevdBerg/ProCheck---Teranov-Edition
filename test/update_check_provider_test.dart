import 'package:flutter_test/flutter_test.dart';
import 'package:procheck/providers/update_check_provider.dart';

void main() {
  group('isNewerVersion', () {
    test('newer patch/minor/major versions are detected', () {
      expect(isNewerVersion('1.0.2', '1.0.1'), isTrue);
      expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
    });

    test('equal or older versions are not newer', () {
      expect(isNewerVersion('1.0.1', '1.0.1'), isFalse);
      expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
    });

    test('ignores build metadata and pre-release suffixes', () {
      expect(isNewerVersion('1.0.2+5', '1.0.1+9'), isTrue);
      expect(isNewerVersion('1.0.1', '1.0.1+2'), isFalse);
    });

    test('a leading "v" already stripped and missing parts default to 0', () {
      expect(isNewerVersion('1.1', '1.0.9'), isTrue);
    });
  });

  group('parseUpdateManifest', () {
    const manifest = '''
{"version":"1.2.2","notes":"Fixes",
 "windows":{"url":"https://x/w.zip","sha256":"ABC123"},
 "macos":{"url":"https://x/m.zip","sha256":"def456"}}''';

    test('returns this platform build with a lower-cased hash', () {
      final u = parseUpdateManifest(
        manifest,
        currentVersion: '1.2.1',
        platform: 'windows',
      )!;
      expect(u.version, '1.2.2');
      expect(u.assetUrl, 'https://x/w.zip');
      expect(u.sha256, 'abc123');
    });

    test('null when the installed version is current or newer', () {
      expect(
        parseUpdateManifest(manifest, currentVersion: '1.2.2', platform: 'windows'),
        isNull,
      );
    });

    test('an unsupported platform still reports the version, no asset', () {
      final u = parseUpdateManifest(
        manifest,
        currentVersion: '1.0.0',
        platform: null,
      )!;
      expect(u.assetUrl, isNull);
      expect(u.sha256, isNull);
    });

    test('a malformed manifest throws', () {
      expect(
        () => parseUpdateManifest('[]', currentVersion: '1.0.0', platform: 'windows'),
        throwsFormatException,
      );
    });
  });
}
