import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockRepo extends Mock implements TranslationMemoryRepository {}

void main() {
  late _MockRepo repo;
  late TmxService service;
  late Directory tmpDir;
  late int originalCap;

  setUp(() {
    repo = _MockRepo();
    service = TmxService(
      repository: repo,
      normalizer: TextNormalizer(),
      logger: FakeLogger(),
    );
    tmpDir = Directory.systemTemp.createTempSync('tmx_size_test_');
    // Lower the cap to keep the test fixture small (1 KiB) while still
    // exercising the fail-fast path.
    originalCap = TmxService.maxImportBytes;
    TmxService.maxImportBytes = 1024;
  });

  tearDown(() {
    TmxService.maxImportBytes = originalCap;
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('rejects TMX file larger than maxImportBytes', () async {
    final path = p.join(tmpDir.path, 'huge.tmx');
    final file = File(path);
    final cap = TmxService.maxImportBytes;
    // Write a file that is slightly larger than the cap.
    file.writeAsStringSync('<tmx>${'a' * (cap + 1)}</tmx>');

    final result = await service.importFromTmx(filePath: path);

    expect(result.isErr, true,
        reason: 'oversized TMX file must be rejected before parsing');
    final err = result.unwrapErr();
    expect(err.filePath, path);
    expect(err.message, contains('exceeds'));
  });

  test('accepts TMX file at or below maxImportBytes boundary', () async {
    final path = p.join(tmpDir.path, 'small.tmx');
    final file = File(path);
    // A minimal valid TMX document well under the cap.
    file.writeAsStringSync(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<tmx version="1.4">'
      '<header srclang="en" creationtool="TWMT" creationtoolversion="1.0" '
      'datatype="plaintext" segtype="sentence" adminlang="en" '
      'o-tmf="TWMT"/>'
      '<body></body>'
      '</tmx>',
    );

    final result = await service.importFromTmx(filePath: path);

    expect(result.isOk, true,
        reason: 'a well-formed TMX under the cap should parse');
  });
}
