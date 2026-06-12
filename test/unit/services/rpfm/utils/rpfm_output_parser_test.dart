import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/rpfm/utils/rpfm_output_parser.dart';

void main() {
  group('parseFileList', () {
    test('returns trimmed non-empty, non-comment lines', () {
      final files = RpfmOutputParser.parseFileList(
          '  /a/x.loc \n\n# comment\n/b/y.txt\n');
      expect(files, ['/a/x.loc', '/b/y.txt']);
    });

    test('returns empty for blank output', () {
      expect(RpfmOutputParser.parseFileList('   '), isEmpty);
    });
  });

  group('parseProgress', () {
    test('extracts a current/total ratio', () {
      expect(RpfmOutputParser.parseProgress('Extracting: 50/100'), 0.5);
    });

    test('returns null when no ratio is present', () {
      expect(RpfmOutputParser.parseProgress('working...'), isNull);
    });
  });

  group('parseErrorMessage', () {
    test('strips known prefixes and returns the first line', () {
      expect(RpfmOutputParser.parseErrorMessage('Error: disk full\ndetails'),
          'disk full');
      expect(RpfmOutputParser.parseErrorMessage('   '), 'Unknown error');
    });
  });

  group('isSuccess / isCancelled', () {
    test('non-zero exit code is never success', () {
      expect(RpfmOutputParser.isSuccess('done', 1), isFalse);
    });

    test('success/error keywords decide a zero-exit result', () {
      expect(RpfmOutputParser.isSuccess('Operation complete', 0), isTrue);
      expect(RpfmOutputParser.isSuccess('fatal error occurred', 0), isFalse);
      expect(RpfmOutputParser.isSuccess('quiet output', 0), isTrue);
    });

    test('isCancelled detects SIGINT and keywords', () {
      expect(RpfmOutputParser.isCancelled('', 130), isTrue);
      expect(RpfmOutputParser.isCancelled('operation aborted', 0), isTrue);
      expect(RpfmOutputParser.isCancelled('all good', 0), isFalse);
    });
  });

  group('parsePackInfo', () {
    test('parses file count, size and version', () {
      final info = RpfmOutputParser.parsePackInfo(
          'Files: 42\nSize: 1024 bytes\nVersion: 3');
      expect(info, isNotNull);
      expect(info!['fileCount'], 42);
      expect(info['sizeBytes'], 1024);
      expect(info['formatVersion'], 3);
    });

    test('returns null when nothing matches', () {
      expect(RpfmOutputParser.parsePackInfo('no useful data'), isNull);
    });
  });

  group('loc-file helpers + path + version + timeout', () {
    final files = ['a.loc', 'b.txt', 'c.LOC', 'd.dat'];

    test('counts and filters .loc files case-insensitively', () {
      expect(RpfmOutputParser.countLocalizationFiles(files), 2);
      expect(RpfmOutputParser.filterLocalizationFiles(files), ['a.loc', 'c.LOC']);
    });

    test('normalizePath converts backslashes', () {
      expect(RpfmOutputParser.normalizePath(r'C:\a\b.loc'), 'C:/a/b.loc');
    });

    test('parseVersion extracts a semantic version', () {
      expect(RpfmOutputParser.parseVersion('rpfm_cli 4.2.1'), '4.2.1');
      expect(RpfmOutputParser.parseVersion('no version'), isNull);
    });

    test('calculateTimeout scales with size and has a floor', () {
      expect(RpfmOutputParser.calculateTimeout(0), 30); // floor
      expect(RpfmOutputParser.calculateTimeout(100 * 1024 * 1024), 90); // +60
    });
  });
}
