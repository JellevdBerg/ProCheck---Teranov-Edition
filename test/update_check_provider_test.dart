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
}
