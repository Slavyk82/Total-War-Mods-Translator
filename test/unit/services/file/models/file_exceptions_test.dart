import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';

void main() {
  test('FileServiceException carries its message', () {
    const e = FileServiceException('boom');
    expect(e.message, 'boom');
  });

  test('FileNotFoundException exposes the path in toString', () {
    const e = FileNotFoundException('missing', 'C:/a.loc');
    expect(e.filePath, 'C:/a.loc');
    expect(e.toString(), contains('C:/a.loc'));
  });

  test('FileAccessDeniedException exposes path + access type', () {
    const e = FileAccessDeniedException('denied', 'C:/a.loc', 'write');
    expect(e.accessType, 'write');
    expect(e.toString(), allOf(contains('C:/a.loc'), contains('write')));
  });

  test('FileEncodingException exposes expected/detected encodings', () {
    const e = FileEncodingException('bad', 'f.loc',
        expectedEncoding: 'utf-8', detectedEncoding: 'utf-16');
    expect(e.expectedEncoding, 'utf-8');
    expect(e.toString(), contains('utf-16'));
  });

  test('FileFormatException exposes format + line', () {
    const e = FileFormatException('bad', 'f.loc', expectedFormat: 'tsv', lineNumber: 3);
    expect(e.lineNumber, 3);
    expect(e.toString(), contains('tsv'));
  });

  test('FileParsingException exposes line + raw content', () {
    const e = FileParsingException('parse', 'f.loc', lineNumber: 2, rawLine: 'x\ty');
    expect(e.rawLine, 'x\ty');
    expect(e.toString(), contains('parse'));
  });

  test('FileWriteException exposes bytesWritten', () {
    const e = FileWriteException('write', 'f.loc', bytesWritten: 128);
    expect(e.bytesWritten, 128);
    expect(e.toString(), contains('128'));
  });

  test('FileValidationException exposes the error list', () {
    const e = FileValidationException('invalid', 'f.loc', ['a', 'b']);
    expect(e.validationErrors, ['a', 'b']);
    expect(e.toString(), contains('2'));
  });

  test('ImportException exposes source + format + count', () {
    const e = ImportException('fail', 'in.csv', 'CSV', entriesImported: 5);
    expect(e.format, 'CSV');
    expect(e.toString(), allOf(contains('in.csv'), contains('5')));
  });

  test('ExportException exposes destination + format + count', () {
    const e = ExportException('fail', 'out.csv', 'CSV', entriesExported: 9);
    expect(e.destinationPath, 'out.csv');
    expect(e.toString(), contains('9'));
  });

  test('FileWatchException exposes the watch path', () {
    const e = FileWatchException('watch', 'C:/dir');
    expect(e.watchPath, 'C:/dir');
    expect(e.toString(), contains('C:/dir'));
  });
}
