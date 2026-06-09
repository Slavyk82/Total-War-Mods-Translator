import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/services/rpfm/rpfm_cli_manager.dart';

void main() {
  group('isSafeExtractionTarget (zip-slip guard)', () {
    const outputDir = r'C:\output\dir';

    test('allows a normal nested entry', () {
      expect(isSafeExtractionTarget(outputDir, 'rpfm_cli.exe'), isTrue);
    });

    test('allows a deeper nested entry', () {
      expect(
        isSafeExtractionTarget(outputDir, path.join('sub', 'folder', 'file.dll')),
        isTrue,
      );
    });

    test('rejects a parent-traversal entry (../escape)', () {
      expect(
        isSafeExtractionTarget(outputDir, path.join('..', 'escape.exe')),
        isFalse,
      );
    });

    test('rejects a Windows-style traversal entry', () {
      expect(
        isSafeExtractionTarget(outputDir, r'..\..\Windows\System32\evil.exe'),
        isFalse,
      );
    });

    test('rejects a POSIX-style traversal entry', () {
      expect(
        isSafeExtractionTarget(outputDir, '../../etc/passwd'),
        isFalse,
      );
    });

    test('rejects an absolute Windows path', () {
      expect(
        isSafeExtractionTarget(outputDir, r'C:\Windows\System32\evil.exe'),
        isFalse,
      );
    });

    test('rejects the output directory itself (no nested entry)', () {
      expect(isSafeExtractionTarget(outputDir, '.'), isFalse);
    });
  });
}
