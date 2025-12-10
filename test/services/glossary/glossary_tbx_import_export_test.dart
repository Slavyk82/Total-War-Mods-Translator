import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/glossary_import_export_service.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';

// Mock classes
class MockGlossaryRepository extends Mock implements GlossaryRepository {}

class MockGlossaryService extends Mock implements IGlossaryService {}

void main() {
  late GlossaryImportExportService service;
  late MockGlossaryRepository mockRepository;
  late MockGlossaryService mockGlossaryService;

  setUp(() {
    mockRepository = MockGlossaryRepository();
    mockGlossaryService = MockGlossaryService();
    service = GlossaryImportExportService(mockRepository, mockGlossaryService);

    // Register fallback values for mocktail
    registerFallbackValue(GlossaryEntry(
      id: 'test',
      glossaryId: 'test',
      targetLanguageCode: 'fr',
      sourceTerm: 'test',
      targetTerm: 'test',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ));
  });

  group('TBX Export', () {
    test('should export glossary entries to TBX format', () async {
      // Arrange
      final glossaryId = 'test-glossary-id';
      final testGlossary = Glossary(
        id: glossaryId,
        name: 'Test Glossary',
        description: 'Test description',
        isGlobal: false,
        entryCount: 2,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final entries = [
        GlossaryEntry(
          id: 'entry-1',
          glossaryId: glossaryId,
          targetLanguageCode: 'fr',
          sourceTerm: 'file',
          targetTerm: 'fichier',
          caseSensitive: false,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
        GlossaryEntry(
          id: 'entry-2',
          glossaryId: glossaryId,
          targetLanguageCode: 'fr',
          sourceTerm: 'battle',
          targetTerm: 'bataille',
          caseSensitive: true,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
      ];

      when(() => mockRepository.getGlossaryById(glossaryId))
          .thenAnswer((_) async => testGlossary);

      when(() => mockRepository.getEntriesByGlossary(
            glossaryId: glossaryId,
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => entries);

      // Create temp file path
      final tempDir = Directory.systemTemp.createTempSync('tbx_test');
      final filePath = '${tempDir.path}/test_export.tbx';

      try {
        // Act
        final result = await service.exportToTbx(
          glossaryId: glossaryId,
          filePath: filePath,
        );

        // Assert
        expect(result.isOk, true);
        expect(result.unwrap(), 2);

        // Verify file was created
        final file = File(filePath);
        expect(await file.exists(), true);

        // Verify file content
        final content = await file.readAsString();
        expect(content, contains('<?xml version="1.0" encoding="UTF-8"?>'));
        expect(content, contains('<martif type="TBX"'));
        expect(content, contains('Test Glossary'));
        expect(content, contains('<term>file</term>'));
        expect(content, contains('<term>fichier</term>'));
        expect(content, contains('<term>battle</term>'));
        expect(content, contains('<term>bataille</term>'));
        expect(content, contains('Case-sensitive matching'));
      } finally {
        // Cleanup
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should handle empty glossary export', () async {
      // Arrange
      final glossaryId = 'empty-glossary-id';
      final testGlossary = Glossary(
        id: glossaryId,
        name: 'Empty Glossary',
        isGlobal: false,
        entryCount: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      when(() => mockRepository.getGlossaryById(glossaryId))
          .thenAnswer((_) async => testGlossary);

      when(() => mockRepository.getEntriesByGlossary(
            glossaryId: glossaryId,
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => []);

      final tempDir = Directory.systemTemp.createTempSync('tbx_test');
      final filePath = '${tempDir.path}/empty_export.tbx';

      try {
        // Act
        final result = await service.exportToTbx(
          glossaryId: glossaryId,
          filePath: filePath,
        );

        // Assert
        expect(result.isOk, true);
        expect(result.unwrap(), 0);
      } finally {
        // Cleanup
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should return error for non-existent glossary', () async {
      // Arrange
      final glossaryId = 'non-existent-id';
      when(() => mockRepository.getGlossaryById(glossaryId))
          .thenAnswer((_) async => null);

      final tempDir = Directory.systemTemp.createTempSync('tbx_test');
      final filePath = '${tempDir.path}/error_export.tbx';

      try {
        // Act
        final result = await service.exportToTbx(
          glossaryId: glossaryId,
          filePath: filePath,
        );

        // Assert
        expect(result.isErr, true);
        expect(result.error, isA<GlossaryNotFoundException>());
      } finally {
        // Cleanup
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('TBX Import', () {
    test('should import glossary entries from TBX file', () async {
      // Arrange
      final glossaryId = 'test-glossary-id';
      final testGlossary = Glossary(
        id: glossaryId,
        name: 'Test Glossary',
        isGlobal: false,
        entryCount: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      when(() => mockRepository.getGlossaryById(glossaryId))
          .thenAnswer((_) async => testGlossary);

      when(() => mockRepository.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
          )).thenAnswer((_) async => null);

      when(() => mockGlossaryService.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).thenAnswer((_) async => Ok(GlossaryEntry(
            id: 'new-entry',
            glossaryId: glossaryId,
            targetLanguageCode: 'fr',
            sourceTerm: 'test',
            targetTerm: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          )));

      // Use the sample TBX file
      final filePath = 'test/fixtures/sample_glossary.tbx';

      // Act
      final result = await service.importFromTbx(
        glossaryId: glossaryId,
        filePath: filePath,
      );

      // Assert
      expect(result.isOk, true);
      // The sample file has 5 entries
      expect(result.unwrap(), 5);

      // Verify addEntry was called for each entry
      verify(() => mockGlossaryService.addEntry(
            glossaryId: glossaryId,
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).called(5);
    });

    test('should skip duplicate entries when skipDuplicates is true', () async {
      // Arrange
      final glossaryId = 'test-glossary-id';
      final testGlossary = Glossary(
        id: glossaryId,
        name: 'Test Glossary',
        isGlobal: false,
        entryCount: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      when(() => mockRepository.getGlossaryById(glossaryId))
          .thenAnswer((_) async => testGlossary);

      // Simulate duplicate entry for first term
      var callCount = 0;
      when(() => mockRepository.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
          )).thenAnswer((_) async {
        callCount++;
        // First call returns a duplicate, rest return null
        if (callCount == 1) {
          return GlossaryEntry(
            id: 'duplicate',
            glossaryId: glossaryId,
            targetLanguageCode: 'fr',
            sourceTerm: 'file',
            targetTerm: 'fichier',
            createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
        }
        return null;
      });

      when(() => mockGlossaryService.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).thenAnswer((_) async => Ok(GlossaryEntry(
            id: 'new-entry',
            glossaryId: glossaryId,
            targetLanguageCode: 'fr',
            sourceTerm: 'test',
            targetTerm: 'test',
            createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          )));

      final filePath = 'test/fixtures/sample_glossary.tbx';

      // Act
      final result = await service.importFromTbx(
        glossaryId: glossaryId,
        filePath: filePath,
        skipDuplicates: true,
      );

      // Assert
      expect(result.isOk, true);
      // Should import 4 entries (5 total - 1 duplicate)
      expect(result.unwrap(), 4);

      // Verify addEntry was called 4 times (not 5)
      verify(() => mockGlossaryService.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).called(4);
    });

    test('should return error for non-existent file', () async {
      // Arrange
      final glossaryId = 'test-glossary-id';
      final testGlossary = Glossary(
        id: glossaryId,
        name: 'Test Glossary',
        isGlobal: false,
        entryCount: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      when(() => mockRepository.getGlossaryById(glossaryId))
          .thenAnswer((_) async => testGlossary);

      final filePath = 'non_existent_file.tbx';

      // Act
      final result = await service.importFromTbx(
        glossaryId: glossaryId,
        filePath: filePath,
      );

      // Assert
      expect(result.isErr, true);
      expect(result.error, isA<GlossaryFileException>());
    });

    test('should return error for invalid XML', () async {
      // Arrange
      final glossaryId = 'test-glossary-id';
      final testGlossary = Glossary(
        id: glossaryId,
        name: 'Test Glossary',
        isGlobal: false,
        entryCount: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      when(() => mockRepository.getGlossaryById(glossaryId))
          .thenAnswer((_) async => testGlossary);

      // Create temp file with invalid XML
      final tempDir = Directory.systemTemp.createTempSync('tbx_test');
      final filePath = '${tempDir.path}/invalid.tbx';
      await File(filePath).writeAsString('This is not valid XML');

      try {
        // Act
        final result = await service.importFromTbx(
          glossaryId: glossaryId,
          filePath: filePath,
        );

        // Assert
        expect(result.isErr, true);
        expect(result.error, isA<GlossaryFileException>());
      } finally {
        // Cleanup
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should return error for invalid TBX structure', () async {
      // Arrange
      final glossaryId = 'test-glossary-id';
      final testGlossary = Glossary(
        id: glossaryId,
        name: 'Test Glossary',
        isGlobal: false,
        entryCount: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      when(() => mockRepository.getGlossaryById(glossaryId))
          .thenAnswer((_) async => testGlossary);

      // Create temp file with valid XML but invalid TBX structure
      final tempDir = Directory.systemTemp.createTempSync('tbx_test');
      final filePath = '${tempDir.path}/invalid_tbx.tbx';
      await File(filePath).writeAsString(
          '<?xml version="1.0"?><root><element>content</element></root>');

      try {
        // Act
        final result = await service.importFromTbx(
          glossaryId: glossaryId,
          filePath: filePath,
        );

        // Assert
        expect(result.isErr, true);
        expect(result.error, isA<GlossaryFileException>());
        expect(result.error.message, contains('missing martif'));
      } finally {
        // Cleanup
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('TBX Round-trip', () {
    test('should export and re-import entries correctly', () async {
      // Arrange
      final exportGlossaryId = 'export-glossary';
      final importGlossaryId = 'import-glossary';

      final exportGlossary = Glossary(
        id: exportGlossaryId,
        name: 'Export Glossary',
        isGlobal: false,
        entryCount: 2,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final importGlossary = Glossary(
        id: importGlossaryId,
        name: 'Import Glossary',
        isGlobal: false,
        entryCount: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final exportEntries = [
        GlossaryEntry(
          id: 'entry-1',
          glossaryId: exportGlossaryId,
          targetLanguageCode: 'fr',
          sourceTerm: 'test',
          targetTerm: 'test',
          caseSensitive: true,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
      ];

      // Setup export mocks
      when(() => mockRepository.getGlossaryById(exportGlossaryId))
          .thenAnswer((_) async => exportGlossary);

      when(() => mockRepository.getEntriesByGlossary(
            glossaryId: exportGlossaryId,
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => exportEntries);

      // Setup import mocks
      when(() => mockRepository.getGlossaryById(importGlossaryId))
          .thenAnswer((_) async => importGlossary);

      when(() => mockRepository.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
          )).thenAnswer((_) async => null);

      when(() => mockGlossaryService.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).thenAnswer((_) async => Ok(exportEntries.first));

      final tempDir = Directory.systemTemp.createTempSync('tbx_test');
      final filePath = '${tempDir.path}/roundtrip.tbx';

      try {
        // Act - Export
        final exportResult = await service.exportToTbx(
          glossaryId: exportGlossaryId,
          filePath: filePath,
        );

        expect(exportResult.isOk, true);

        // Act - Import
        final importResult = await service.importFromTbx(
          glossaryId: importGlossaryId,
          filePath: filePath,
        );

        // Assert
        expect(importResult.isOk, true);
        expect(importResult.unwrap(), 1);

        // Verify the entry was added with correct values
        verify(() => mockGlossaryService.addEntry(
              glossaryId: importGlossaryId,
              targetLanguageCode: 'fr',
              sourceTerm: 'test',
              targetTerm: 'test',
              caseSensitive: true,
            )).called(1);
      } finally {
        // Cleanup
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
