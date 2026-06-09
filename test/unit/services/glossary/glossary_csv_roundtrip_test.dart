import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/glossary_export_service.dart';
import 'package:twmt/services/glossary/glossary_import_service.dart';
import 'package:twmt/services/glossary/glossary_service_impl.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/shared/logging_service.dart';

import '../../../helpers/test_database.dart';

/// Round-trip tests proving export -> import is lossless for fields that
/// contain CSV special characters (comma, double-quote). These exercise the
/// RFC-4180 quoting (export) and quote-aware parsing (import) added to fix the
/// two data-integrity bugs where commas/quotes corrupted glossary CSVs.
void main() {
  late Database db;
  late GlossaryRepository repository;
  late GlossaryServiceImpl glossaryService;
  late GlossaryExportService exportService;
  late GlossaryImportService importService;
  late Directory tempDir;

  const targetLanguageCode = 'fr';

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = GlossaryRepository(logger: LoggingService.instance);
    glossaryService =
        GlossaryServiceImpl(repository: repository, logger: LoggingService.instance);
    exportService =
        GlossaryExportService(repository, logger: LoggingService.instance);
    importService = GlossaryImportService(
      repository,
      glossaryService,
      logger: LoggingService.instance,
    );
    tempDir = await Directory.systemTemp.createTemp('glossary_csv_roundtrip');
  });

  tearDown(() async {
    await TestDatabase.close(db);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<Glossary> seedGlossary(String id, {required String gameCode}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final glossary = Glossary(
      id: id,
      name: 'Roundtrip $id',
      // schema enforces UNIQUE(game_code, target_language_id); source and dest
      // glossaries must differ on game_code to coexist.
      gameCode: gameCode,
      targetLanguageId: 'lang_fr',
      createdAt: now,
      updatedAt: now,
    );
    await repository.insertGlossary(glossary);
    return glossary;
  }

  /// Export [sourceGlossaryId] to a temp CSV, then import it into
  /// [destGlossaryId], returning the imported entries keyed by source term.
  Future<Map<String, ({String target, String? notes})>> roundTrip({
    required String sourceGlossaryId,
    required String destGlossaryId,
  }) async {
    final csvPath = '${tempDir.path}/glossary.csv';

    final exportResult = await exportService.exportToCsv(
      glossaryId: sourceGlossaryId,
      filePath: csvPath,
      targetLanguageCode: targetLanguageCode,
    );
    expect(exportResult.isOk, isTrue,
        reason: 'export should succeed: $exportResult');

    final importResult = await importService.importFromCsv(
      glossaryId: destGlossaryId,
      filePath: csvPath,
      targetLanguageCode: targetLanguageCode,
      skipDuplicates: false,
    );
    expect(importResult.isOk, isTrue,
        reason: 'import should succeed: $importResult');

    final imported = await repository.getEntriesByGlossary(
      glossaryId: destGlossaryId,
      targetLanguageCode: targetLanguageCode,
    );

    return {
      for (final e in imported)
        e.sourceTerm: (target: e.targetTerm, notes: e.notes),
    };
  }

  test('a source term containing a comma survives export -> import', () async {
    await seedGlossary('g-src', gameCode: 'wh3');
    await seedGlossary('g-dst', gameCode: 'wh2');

    final added = await glossaryService.addEntry(
      glossaryId: 'g-src',
      targetLanguageCode: targetLanguageCode,
      sourceTerm: 'Empire, The',
      targetTerm: 'Empire',
    );
    expect(added.isOk, isTrue);

    final result = await roundTrip(
      sourceGlossaryId: 'g-src',
      destGlossaryId: 'g-dst',
    );

    expect(result.containsKey('Empire, The'), isTrue,
        reason: 'comma in source term must not split into extra columns');
    expect(result['Empire, The']!.target, equals('Empire'));
  });

  test('a target term containing a double-quote survives export -> import',
      () async {
    await seedGlossary('g-src', gameCode: 'wh3');
    await seedGlossary('g-dst', gameCode: 'wh2');

    await glossaryService.addEntry(
      glossaryId: 'g-src',
      targetLanguageCode: targetLanguageCode,
      sourceTerm: 'TheQuoted',
      targetTerm: 'Le "Quoted"',
    );

    final result = await roundTrip(
      sourceGlossaryId: 'g-src',
      destGlossaryId: 'g-dst',
    );

    expect(result.containsKey('TheQuoted'), isTrue);
    expect(result['TheQuoted']!.target, equals('Le "Quoted"'),
        reason: 'embedded double-quotes must be unescaped back to a single "');
  });

  test('a note containing a comma survives export -> import', () async {
    await seedGlossary('g-src', gameCode: 'wh3');
    await seedGlossary('g-dst', gameCode: 'wh2');

    await glossaryService.addEntry(
      glossaryId: 'g-src',
      targetLanguageCode: targetLanguageCode,
      sourceTerm: 'Faction',
      targetTerm: 'Faction',
      notes: 'Use formal tone, plural form, and keep capitalization',
    );

    final result = await roundTrip(
      sourceGlossaryId: 'g-src',
      destGlossaryId: 'g-dst',
    );

    expect(result.containsKey('Faction'), isTrue);
    expect(
      result['Faction']!.notes,
      equals('Use formal tone, plural form, and keep capitalization'),
      reason: 'comma in notes must round-trip identically',
    );
  });
}
