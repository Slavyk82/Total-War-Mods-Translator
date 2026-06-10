import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';

import '../../../helpers/fakes/fake_logger.dart';
import '../../../helpers/test_database.dart';

/// Regression tests for the TMX persist path storing raw xml:lang codes
/// (e.g. 'en', 'fr-FR') into translation_memory.source_language_id /
/// target_language_id, which are FKs to languages(id) with ids of the
/// form 'lang_xx'. With PRAGMA foreign_keys = ON (production behavior),
/// every such insert fails and the whole TMX import returns Err.
void main() {
  late Database db;
  late TranslationMemoryRepository repo;
  late TmxService service;

  setUp(() async {
    // Keep schema.sql seed data: the languages table must contain the
    // production 'lang_xx' rows for FK validation to be meaningful.
    db = await TestDatabase.openMigrated(clearSeeds: false);
    // TestDatabase disables FK enforcement for legacy repo tests;
    // re-enable it to mirror production (database_service.dart runs
    // PRAGMA foreign_keys = ON on every connection).
    await db.execute('PRAGMA foreign_keys = ON');

    repo = TranslationMemoryRepository();
    service = TmxService(
      repository: repo,
      normalizer: TextNormalizer(),
      logger: FakeLogger(),
    );
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  Future<List<Map<String, Object?>>> tmRows() =>
      db.query('translation_memory', orderBy: 'source_text');

  test(
      'persists entries with raw TMX codes (en, fr-FR) by normalizing '
      'them to canonical lang_xx ids', () async {
    final result = await service.persistTmxEntries(
      entries: const [
        TmxEntry(
          sourceLanguage: 'en',
          targetLanguage: 'fr-FR',
          sourceText: 'Hello world',
          targetText: 'Bonjour le monde',
        ),
      ],
    );

    expect(result.isOk, isTrue,
        reason: 'import must not fail on FK violation: $result');
    expect(result.unwrap(), 1);

    final rows = await tmRows();
    expect(rows, hasLength(1));
    expect(rows.single['source_language_id'], 'lang_en');
    expect(rows.single['target_language_id'], 'lang_fr');
    expect(rows.single['translated_text'], 'Bonjour le monde');
  });

  test(
      'accepts codes already in lang_xx form and uppercase bare codes '
      '(idempotent, case-insensitive)', () async {
    final result = await service.persistTmxEntries(
      entries: const [
        TmxEntry(
          sourceLanguage: 'LANG_EN',
          targetLanguage: 'FR',
          sourceText: 'Cheese',
          targetText: 'Fromage',
        ),
      ],
    );

    expect(result.isOk, isTrue, reason: '$result');
    expect(result.unwrap(), 1);

    final rows = await tmRows();
    expect(rows, hasLength(1));
    expect(rows.single['source_language_id'], 'lang_en');
    expect(rows.single['target_language_id'], 'lang_fr');
  });

  test(
      'skips entries whose language maps to no row in languages instead '
      'of inserting an FK-violating row', () async {
    final result = await service.persistTmxEntries(
      entries: const [
        TmxEntry(
          sourceLanguage: 'en',
          targetLanguage: 'fr',
          sourceText: 'Valid entry',
          targetText: 'Entree valide',
        ),
        TmxEntry(
          sourceLanguage: 'en',
          targetLanguage: 'xx-XX', // no lang_xx row seeded
          sourceText: 'Unknown target language',
          targetText: 'whatever',
        ),
      ],
    );

    expect(result.isOk, isTrue,
        reason: 'unknown language must be skipped, not fail import: $result');
    expect(result.unwrap(), 1, reason: 'only the valid entry is persisted');

    final rows = await tmRows();
    expect(rows, hasLength(1));
    expect(rows.single['source_text'], 'Valid entry');
  });

  test(
      'resolves a custom language (non lang_xx id) through its code, '
      'including regional variants', () async {
    // Custom languages get UUID ids (see language_settings_providers.dart),
    // so id != 'lang_<code>' for them.
    await db.insert('languages', {
      'id': 'b2a7c5be-0000-4000-8000-000000000001',
      'code': 'pl',
      'name': 'Polish',
      'native_name': 'Polski',
      'is_active': 1,
      'is_custom': 1,
    });

    final result = await service.persistTmxEntries(
      entries: const [
        TmxEntry(
          sourceLanguage: 'en-US',
          targetLanguage: 'pl-PL',
          sourceText: 'Sword',
          targetText: 'Miecz',
        ),
      ],
    );

    expect(result.isOk, isTrue, reason: '$result');
    expect(result.unwrap(), 1);

    final rows = await tmRows();
    expect(rows, hasLength(1));
    expect(rows.single['source_language_id'], 'lang_en');
    expect(rows.single['target_language_id'],
        'b2a7c5be-0000-4000-8000-000000000001');
  });
}
