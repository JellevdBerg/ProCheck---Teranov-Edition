import 'package:flutter_test/flutter_test.dart';
import 'package:procheck/data/update_installer.dart';
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

  group('update assets', () {
    test('picks this platform zip and the checksums file', () {
      final picked = pickReleaseAssets([
        {'name': 'procheck-macos-v1.2.0.zip', 'browser_download_url': 'm'},
        {'name': 'procheck-windows-v1.2.0.zip', 'browser_download_url': 'w'},
        {'name': 'SHA256SUMS.txt', 'browser_download_url': 's'},
      ], 'windows');
      expect(picked.name, 'procheck-windows-v1.2.0.zip');
      expect(picked.url, 'w');
      expect(picked.checksums, 's');
    });

    test('missing assets yield nulls', () {
      final picked = pickReleaseAssets(null, 'windows');
      expect(picked.url, isNull);
      expect(picked.checksums, isNull);
    });

    test('finds a zip hash in SHA256SUMS.txt, case-insensitively', () {
      const sums = 'ABC123  procheck-windows-v1.2.0.zip\r\n'
          'def456  procheck-macos-v1.2.0.zip\n';
      expect(expectedHashFor(sums, 'procheck-windows-v1.2.0.zip'), 'abc123');
      expect(expectedHashFor(sums, 'procheck-linux-v1.2.0.zip'), isNull);
    });
  });
}
