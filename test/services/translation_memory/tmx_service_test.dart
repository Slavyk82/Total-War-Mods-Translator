import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';
import 'package:twmt/services/shared/logging_service.dart';

class MockTranslationMemoryRepository extends Mock
    implements TranslationMemoryRepository {}

class MockTextNormalizer extends Mock implements TextNormalizer {}

class MockLoggingService extends Mock implements LoggingService {}

void main() {
  late TmxService tmxService;
  late MockTranslationMemoryRepository mockRepository;
  late MockTextNormalizer mockNormalizer;
  late MockLoggingService mockLogger;

  setUp(() {
    mockRepository = MockTranslationMemoryRepository();
    mockNormalizer = MockTextNormalizer();
    mockLogger = MockLoggingService();

    tmxService = TmxService(
      repository: mockRepository,
      normalizer: mockNormalizer,
      logger: mockLogger,
    );

    // Setup default mock responses
    when(() => mockLogger.info(any(), any())).thenReturn(null);
    when(() => mockLogger.debug(any(), any())).thenReturn(null);
    when(() => mockLogger.warning(any(), any())).thenReturn(null);
    when(() => mockLogger.error(any(), any(), any())).thenReturn(null);
  });

  group('TMX Export', () {
    test('should export entries to TMX format', () async {
      // Arrange
      final entries = [
        TranslationMemoryEntry(
          id: '1',
          sourceText: 'Open File',
          translatedText: 'Ouvrir le fichier',
          targetLanguageId: 'fr',
          sourceHash: 'hash1',
          qualityScore: 0.95,
          usageCount: 15,
          gameContext: 'UI',
          createdAt: 1234567890,
          lastUsedAt: 1234567890,
          updatedAt: 1234567890,
        ),
        TranslationMemoryEntry(
          id: '2',
          sourceText: 'Save File',
          translatedText: 'Enregistrer le fichier',
          targetLanguageId: 'fr',
          sourceHash: 'hash2',
          qualityScore: 0.92,
          usageCount: 10,
          createdAt: 1234567890,
          lastUsedAt: 1234567890,
          updatedAt: 1234567890,
        ),
      ];

      final tempDir = Directory.systemTemp.createTempSync('tmx_test_');
      final outputPath = '${tempDir.path}/test_output.tmx';

      // Act
      final result = await tmxService.exportToTmx(
        filePath: outputPath,
        entries: entries,
        sourceLanguage: 'en',
        targetLanguage: 'fr',
      );

      // Assert
      expect(result.isOk, true);

      // Verify file was created
      final file = File(outputPath);
      expect(await file.exists(), true);

      // Verify TMX structure
      final content = await file.readAsString();
      expect(content, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(content, contains('<tmx version="1.4">'));
      expect(content, contains('creationtool="TWMT"'));
      expect(content, contains('srclang="en"'));
      expect(content, contains('<tu>'));
      expect(content, contains('Open File'));
      expect(content, contains('Ouvrir le fichier'));
      expect(content, contains('Save File'));
      expect(content, contains('Enregistrer le fichier'));
      expect(content, contains('x-quality-score'));
      expect(content, contains('x-usage-count'));
      expect(content, contains('x-game-context'));

      // Cleanup
      await tempDir.delete(recursive: true);
    });

    test('should handle empty entries list', () async {
      // Arrange
      final tempDir = Directory.systemTemp.createTempSync('tmx_test_');
      final outputPath = '${tempDir.path}/test_empty.tmx';

      // Act
      final result = await tmxService.exportToTmx(
        filePath: outputPath,
        entries: [],
        sourceLanguage: 'en',
        targetLanguage: 'fr',
      );

      // Assert
      expect(result.isOk, true);

      // Verify file structure
      final file = File(outputPath);
      expect(await file.exists(), true);

      final content = await file.readAsString();
      expect(content, contains('<tmx version="1.4">'));
      // Body can be either <body></body> or <body/>
      expect(content, anyOf(contains('<body>'), contains('<body/>')));

      // Cleanup
      await tempDir.delete(recursive: true);
    });
  });

  group('TMX Import', () {
    test('should import entries from valid TMX file', () async {
      // Arrange
      final tmxContent = '''<?xml version="1.0" encoding="UTF-8"?>
<tmx version="1.4">
  <header
    creationtool="TWMT"
    creationtoolversion="1.0"
    datatype="plaintext"
    segtype="sentence"
    adminlang="en"
    srclang="en"
    o-tmf="TWMT"/>
  <body>
    <tu>
      <prop type="x-quality-score">0.95</prop>
      <prop type="x-usage-count">15</prop>
      <prop type="x-game-context">UI</prop>
      <tuv xml:lang="en">
        <seg>Open File</seg>
      </tuv>
      <tuv xml:lang="fr">
        <seg>Ouvrir le fichier</seg>
      </tuv>
    </tu>
    <tu>
      <prop type="x-quality-score">0.92</prop>
      <prop type="x-usage-count">10</prop>
      <tuv xml:lang="en">
        <seg>Save File</seg>
      </tuv>
      <tuv xml:lang="fr">
        <seg>Enregistrer le fichier</seg>
      </tuv>
    </tu>
  </body>
</tmx>''';

      final tempDir = Directory.systemTemp.createTempSync('tmx_test_');
      final inputPath = '${tempDir.path}/test_input.tmx';
      await File(inputPath).writeAsString(tmxContent);

      // Act
      final result = await tmxService.importFromTmx(filePath: inputPath);

      // Assert
      expect(result.isOk, true);

      final entries = result.value;
      expect(entries.length, 2);

      // Verify first entry
      expect(entries[0].sourceLanguage, 'en');
      expect(entries[0].targetLanguage, 'fr');
      expect(entries[0].sourceText, 'Open File');
      expect(entries[0].targetText, 'Ouvrir le fichier');
      expect(entries[0].qualityScore, 0.95);
      expect(entries[0].usageCount, 15);
      expect(entries[0].gameContext, 'UI');

      // Verify second entry
      expect(entries[1].sourceLanguage, 'en');
      expect(entries[1].targetLanguage, 'fr');
      expect(entries[1].sourceText, 'Save File');
      expect(entries[1].targetText, 'Enregistrer le fichier');
      expect(entries[1].qualityScore, 0.92);
      expect(entries[1].usageCount, 10);
      expect(entries[1].gameContext, null);

      // Cleanup
      await tempDir.delete(recursive: true);
    });

    test('should return error for non-existent file', () async {
      // Act
      final result = await tmxService.importFromTmx(
        filePath: '/non/existent/file.tmx',
      );

      // Assert
      expect(result.isErr, true);
      expect(result.error.message, contains('not found'));
    });

    test('should return error for invalid TMX structure', () async {
      // Arrange
      final invalidTmx = '''<?xml version="1.0" encoding="UTF-8"?>
<invalid>
  <notTmx>Invalid</notTmx>
</invalid>''';

      final tempDir = Directory.systemTemp.createTempSync('tmx_test_');
      final inputPath = '${tempDir.path}/invalid.tmx';
      await File(inputPath).writeAsString(invalidTmx);

      // Act
      final result = await tmxService.importFromTmx(filePath: inputPath);

      // Assert
      expect(result.isErr, true);
      expect(result.error.message, contains('Invalid TMX file'));

      // Cleanup
      await tempDir.delete(recursive: true);
    });

    test('should skip incomplete translation units', () async {
      // Arrange
      final tmxWithIncomplete = '''<?xml version="1.0" encoding="UTF-8"?>
<tmx version="1.4">
  <header srclang="en"/>
  <body>
    <tu>
      <tuv xml:lang="en">
        <seg>Complete Entry</seg>
      </tuv>
      <tuv xml:lang="fr">
        <seg>Entrée complète</seg>
      </tuv>
    </tu>
    <tu>
      <tuv xml:lang="en">
        <seg>Incomplete Entry - Missing Target</seg>
      </tuv>
    </tu>
  </body>
</tmx>''';

      final tempDir = Directory.systemTemp.createTempSync('tmx_test_');
      final inputPath = '${tempDir.path}/incomplete.tmx';
      await File(inputPath).writeAsString(tmxWithIncomplete);

      // Act
      final result = await tmxService.importFromTmx(filePath: inputPath);

      // Assert
      expect(result.isOk, true);
      expect(result.value.length, 1); // Only complete entry
      expect(result.value[0].sourceText, 'Complete Entry');

      // Cleanup
      await tempDir.delete(recursive: true);
    });
  });

  group('TMX Round-trip', () {
    test('should maintain data integrity in export-import cycle', () async {
      // Arrange
      final originalEntries = [
        TranslationMemoryEntry(
          id: '1',
          sourceText: 'Test Source',
          translatedText: 'Test Target',
          targetLanguageId: 'de',
          sourceHash: 'hash1',
          qualityScore: 0.88,
          usageCount: 5,
          gameContext: 'narrative',
          createdAt: 1234567890,
          lastUsedAt: 1234567890,
          updatedAt: 1234567890,
        ),
      ];

      final tempDir = Directory.systemTemp.createTempSync('tmx_test_');
      final tmxPath = '${tempDir.path}/roundtrip.tmx';

      // Act - Export
      final exportResult = await tmxService.exportToTmx(
        filePath: tmxPath,
        entries: originalEntries,
        sourceLanguage: 'en',
        targetLanguage: 'de',
      );

      expect(exportResult.isOk, true);

      // Act - Import
      final importResult = await tmxService.importFromTmx(filePath: tmxPath);

      // Assert
      expect(importResult.isOk, true);

      final importedEntries = importResult.value;
      expect(importedEntries.length, 1);

      final imported = importedEntries[0];
      expect(imported.sourceText, originalEntries[0].sourceText);
      expect(imported.targetText, originalEntries[0].translatedText);
      expect(imported.targetLanguage, originalEntries[0].targetLanguageId);
      expect(imported.qualityScore, originalEntries[0].qualityScore);
      expect(imported.usageCount, originalEntries[0].usageCount);
      expect(imported.gameContext, originalEntries[0].gameContext);

      // Cleanup
      await tempDir.delete(recursive: true);
    });
  });
}
