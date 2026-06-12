import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/i_file_service.dart';

void main() {
  FileInfo info(int sizeBytes) => FileInfo(
        path: r'C:\x\f.loc',
        name: 'f.loc',
        sizeBytes: sizeBytes,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );

  group('FileInfo.sizeFormatted', () {
    test('formats bytes', () {
      expect(info(512).sizeFormatted, '512 B');
    });

    test('formats kilobytes', () {
      expect(info(2048).sizeFormatted, '2.0 KB');
    });

    test('formats megabytes', () {
      expect(info(5 * 1024 * 1024).sizeFormatted, '5.0 MB');
    });

    test('formats gigabytes', () {
      expect(info(3 * 1024 * 1024 * 1024).sizeFormatted, '3.0 GB');
    });
  });

  test('FileInfo.toString includes name and formatted size', () {
    expect(info(1024).toString(), contains('f.loc'));
    expect(info(1024).toString(), contains('1.0 KB'));
  });

  group('FileChangeEvent', () {
    test('toString includes type and path', () {
      final e = FileChangeEvent(
        type: FileChangeType.modified,
        path: r'C:\x\f.loc',
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(e.toString(), contains('modified'));
      expect(e.toString(), contains('f.loc'));
    });

    test('exposes the change type and optional old path', () {
      final e = FileChangeEvent(
        type: FileChangeType.moved,
        path: 'new.loc',
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        oldPath: 'old.loc',
      );
      expect(e.type, FileChangeType.moved);
      expect(e.oldPath, 'old.loc');
    });
  });

  test('FileChangeType has the expected variants', () {
    expect(FileChangeType.values, hasLength(4));
    expect(
      FileChangeType.values,
      containsAll([
        FileChangeType.created,
        FileChangeType.modified,
        FileChangeType.deleted,
        FileChangeType.moved,
      ]),
    );
  });
}
