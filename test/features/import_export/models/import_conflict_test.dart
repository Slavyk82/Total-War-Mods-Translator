import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/import_export/models/import_conflict.dart';

/// Unit tests for [ImportConflict], [ConflictTranslation], the
/// [ConflictResolution] enum and [ConflictResolutions] (json_serializable).
/// Covers the `isResolved` getter, `getResolution`/`setResolution` lookup
/// logic, `copyWith`, and nested JSON round-trips. None of these classes
/// override `==`, so JSON assertions compare field-by-field.
void main() {
  ConflictTranslation existing() => const ConflictTranslation(
        sourceText: 'Hello',
        translatedText: 'Salut',
        status: 'translated',
        updatedAt: 1700000000,
        changedBy: 'User',
        notes: 'a note',
      );

  ConflictTranslation imported() => const ConflictTranslation(
        sourceText: 'Hello',
        translatedText: 'Bonjour',
      );

  ImportConflict conflict({
    String key = 'KEY_1',
    bool sourceTextDiffers = false,
    ConflictResolution? resolution,
  }) {
    return ImportConflict(
      key: key,
      existingData: existing(),
      importedData: imported(),
      sourceTextDiffers: sourceTextDiffers,
      resolution: resolution,
    );
  }

  group('ConflictResolution enum', () {
    test('has three values with expected JSON encodings', () {
      expect(ConflictResolution.values, hasLength(3));
      for (final entry in {
        'keep_existing': ConflictResolution.keepExisting,
        'use_imported': ConflictResolution.useImported,
        'merge': ConflictResolution.merge,
      }.entries) {
        final decoded = ImportConflict.fromJson({
          'key': 'k',
          'existing_data': const <String, dynamic>{},
          'imported_data': const <String, dynamic>{},
          'resolution': entry.key,
        });
        expect(decoded.resolution, entry.value);
      }
    });
  });

  group('ImportConflict', () {
    test('constructor defaults sourceTextDiffers=false, resolution=null', () {
      final c = ImportConflict(
        key: 'k',
        existingData: existing(),
        importedData: imported(),
      );
      expect(c.sourceTextDiffers, isFalse);
      expect(c.resolution, isNull);
    });

    test('isResolved reflects whether a resolution is set', () {
      expect(conflict().isResolved, isFalse);
      expect(
        conflict(resolution: ConflictResolution.useImported).isResolved,
        isTrue,
      );
    });

    test('copyWith overrides each field', () {
      final base = conflict();
      expect(base.copyWith(key: 'other').key, 'other');
      expect(base.copyWith(sourceTextDiffers: true).sourceTextDiffers, isTrue);
      expect(
        base.copyWith(resolution: ConflictResolution.merge).resolution,
        ConflictResolution.merge,
      );
      final newExisting = existing().copyWith(status: 'pending');
      expect(base.copyWith(existingData: newExisting).existingData.status,
          'pending');
      final newImported = imported().copyWith(translatedText: 'Coucou');
      expect(base.copyWith(importedData: newImported).importedData.translatedText,
          'Coucou');
    });

    test('copyWith with no args preserves values', () {
      final base = conflict(sourceTextDiffers: true);
      final copy = base.copyWith();
      expect(copy.key, base.key);
      expect(copy.sourceTextDiffers, isTrue);
      expect(copy.existingData.translatedText, base.existingData.translatedText);
    });

    test('JSON round-trips including nested translation data', () {
      final original = conflict(
        sourceTextDiffers: true,
        resolution: ConflictResolution.useImported,
      );
      final json = original.toJson();
      expect(json['key'], 'KEY_1');
      expect(json['source_text_differs'], isTrue);
      expect(json['resolution'], 'use_imported');
      final decoded = ImportConflict.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(decoded.key, original.key);
      expect(decoded.sourceTextDiffers, isTrue);
      expect(decoded.resolution, ConflictResolution.useImported);
      expect(decoded.existingData.sourceText, 'Hello');
      expect(decoded.existingData.translatedText, 'Salut');
      expect(decoded.existingData.status, 'translated');
      expect(decoded.existingData.updatedAt, 1700000000);
      expect(decoded.existingData.changedBy, 'User');
      expect(decoded.existingData.notes, 'a note');
      expect(decoded.importedData.translatedText, 'Bonjour');
    });

    test('fromJson null resolution stays null', () {
      final decoded = ImportConflict.fromJson({
        'key': 'k',
        'existing_data': const <String, dynamic>{},
        'imported_data': const <String, dynamic>{},
      });
      expect(decoded.resolution, isNull);
      expect(decoded.sourceTextDiffers, isFalse);
    });
  });

  group('ConflictTranslation', () {
    test('all fields default to null', () {
      const t = ConflictTranslation();
      expect(t.sourceText, isNull);
      expect(t.translatedText, isNull);
      expect(t.status, isNull);
      expect(t.updatedAt, isNull);
      expect(t.changedBy, isNull);
      expect(t.notes, isNull);
    });

    test('copyWith overrides each field', () {
      const base = ConflictTranslation();
      expect(base.copyWith(sourceText: 's').sourceText, 's');
      expect(base.copyWith(translatedText: 't').translatedText, 't');
      expect(base.copyWith(status: 'translated').status, 'translated');
      expect(base.copyWith(updatedAt: 42).updatedAt, 42);
      expect(base.copyWith(changedBy: 'LLM').changedBy, 'LLM');
      expect(base.copyWith(notes: 'n').notes, 'n');
    });

    test('JSON round-trips', () {
      final original = existing();
      final decoded = ConflictTranslation.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.sourceText, original.sourceText);
      expect(decoded.translatedText, original.translatedText);
      expect(decoded.status, original.status);
      expect(decoded.updatedAt, original.updatedAt);
      expect(decoded.changedBy, original.changedBy);
      expect(decoded.notes, original.notes);
    });
  });

  group('ConflictResolutions', () {
    test('constructor defaults empty resolutions and null default', () {
      const r = ConflictResolutions();
      expect(r.resolutions, isEmpty);
      expect(r.defaultResolution, isNull);
    });

    group('getResolution', () {
      test('returns the per-key resolution when present', () {
        const r = ConflictResolutions(
          resolutions: {'K1': ConflictResolution.useImported},
        );
        expect(r.getResolution('K1'), ConflictResolution.useImported);
      });

      test('falls back to the default resolution for an unknown key', () {
        const r = ConflictResolutions(
          resolutions: {'K1': ConflictResolution.useImported},
          defaultResolution: ConflictResolution.keepExisting,
        );
        expect(r.getResolution('OTHER'), ConflictResolution.keepExisting);
      });

      test('returns null when neither key nor default is present', () {
        const r = ConflictResolutions();
        expect(r.getResolution('missing'), isNull);
      });
    });

    group('setResolution', () {
      test('adds a new key without mutating the original', () {
        const original = ConflictResolutions();
        final updated =
            original.setResolution('K1', ConflictResolution.merge);
        expect(updated.getResolution('K1'), ConflictResolution.merge);
        // Original is untouched (immutability).
        expect(original.resolutions, isEmpty);
      });

      test('overwrites an existing key and preserves the default', () {
        const original = ConflictResolutions(
          resolutions: {'K1': ConflictResolution.keepExisting},
          defaultResolution: ConflictResolution.useImported,
        );
        final updated =
            original.setResolution('K1', ConflictResolution.merge);
        expect(updated.getResolution('K1'), ConflictResolution.merge);
        expect(updated.defaultResolution, ConflictResolution.useImported);
      });
    });

    group('copyWith', () {
      test('overrides each field', () {
        const base = ConflictResolutions();
        expect(
          base.copyWith(
            resolutions: const {'K1': ConflictResolution.merge},
          ).resolutions,
          const {'K1': ConflictResolution.merge},
        );
        expect(
          base
              .copyWith(defaultResolution: ConflictResolution.keepExisting)
              .defaultResolution,
          ConflictResolution.keepExisting,
        );
      });

      test('with no args preserves values', () {
        const base = ConflictResolutions(
          resolutions: {'K1': ConflictResolution.useImported},
          defaultResolution: ConflictResolution.merge,
        );
        final copy = base.copyWith();
        expect(copy.resolutions, base.resolutions);
        expect(copy.defaultResolution, base.defaultResolution);
      });
    });

    test('JSON round-trips', () {
      const original = ConflictResolutions(
        resolutions: {
          'K1': ConflictResolution.useImported,
          'K2': ConflictResolution.keepExisting,
        },
        defaultResolution: ConflictResolution.merge,
      );
      final json = original.toJson();
      expect((json['resolutions'] as Map)['K1'], 'use_imported');
      expect(json['default_resolution'], 'merge');
      final decoded = ConflictResolutions.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(decoded.resolutions['K1'], ConflictResolution.useImported);
      expect(decoded.resolutions['K2'], ConflictResolution.keepExisting);
      expect(decoded.defaultResolution, ConflictResolution.merge);
    });

    test('fromJson applies defaults for missing fields', () {
      final decoded = ConflictResolutions.fromJson(const {});
      expect(decoded.resolutions, isEmpty);
      expect(decoded.defaultResolution, isNull);
    });
  });
}
