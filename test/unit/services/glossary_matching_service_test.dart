import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/glossary_matching_service.dart';
import 'package:twmt/services/glossary/models/glossary.dart';

// Mock class
class MockGlossaryRepository extends Mock implements GlossaryRepository {}

void main() {
  late GlossaryMatchingService service;
  late MockGlossaryRepository mockRepository;

  setUp(() {
    mockRepository = MockGlossaryRepository();
    service = GlossaryMatchingService(mockRepository);
  });

  // Helper function to create test glossary entries
  GlossaryEntry createTestEntry({
    String id = 'entry-1',
    String glossaryId = 'glossary-1',
    String sourceTerm = 'test',
    String targetTerm = 'test_fr',
    String targetLanguageCode = 'fr',
    bool caseSensitive = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return GlossaryEntry(
      id: id,
      glossaryId: glossaryId,
      targetLanguageCode: targetLanguageCode,
      sourceTerm: sourceTerm,
      targetTerm: targetTerm,
      caseSensitive: caseSensitive,
      createdAt: now,
      updatedAt: now,
    );
  }

  // Helper function to create test glossary
  Glossary createTestGlossary({
    String id = 'glossary-1',
    String name = 'Test Glossary',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return Glossary(
      id: id,
      name: name,
      isGlobal: true,
      targetLanguageId: 'fr',
      createdAt: now,
      updatedAt: now,
    );
  }

  group('GlossaryMatchingService', () {
    // =========================================================================
    // findMatchingTerms
    // =========================================================================
    group('findMatchingTerms', () {
      test('should return matching terms when found in source text', () async {
        // Arrange
        final glossary = createTestGlossary();
        final entry = createTestEntry(
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
        );

        when(() => mockRepository.getAllGlossaries(
              gameInstallationId: any(named: 'gameInstallationId'),
              includeUniversal: true,
            )).thenAnswer((_) async => [glossary]);

        when(() => mockRepository.getEntriesByGlossary(
              glossaryId: glossary.id,
              targetLanguageCode: 'fr',
            )).thenAnswer((_) async => [entry]);

        when(() => mockRepository.incrementUsageCount(any()))
            .thenAnswer((_) async {});

        // Act
        final result = await service.findMatchingTerms(
          sourceText: 'The cavalry unit attacked.',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value.length, 1);
        expect(result.value.first.sourceTerm, 'cavalry');
        verify(() => mockRepository.incrementUsageCount([entry.id])).called(1);
      });

      test('should return empty list when no terms match', () async {
        // Arrange
        final glossary = createTestGlossary();
        final entry = createTestEntry(
          sourceTerm: 'infantry',
          targetTerm: 'infanterie',
        );

        when(() => mockRepository.getAllGlossaries(
              gameInstallationId: any(named: 'gameInstallationId'),
              includeUniversal: true,
            )).thenAnswer((_) async => [glossary]);

        when(() => mockRepository.getEntriesByGlossary(
              glossaryId: glossary.id,
              targetLanguageCode: 'fr',
            )).thenAnswer((_) async => [entry]);

        // Act
        final result = await service.findMatchingTerms(
          sourceText: 'The cavalry unit attacked.',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value.isEmpty, true);
        verifyNever(() => mockRepository.incrementUsageCount(any()));
      });

      test('should use specific glossary IDs when provided', () async {
        // Arrange
        final glossary = createTestGlossary(id: 'specific-glossary');
        final entry = createTestEntry(
          glossaryId: 'specific-glossary',
          sourceTerm: 'archer',
          targetTerm: 'archer',
        );

        when(() => mockRepository.getGlossariesByIds(['specific-glossary']))
            .thenAnswer((_) async => [glossary]);

        when(() => mockRepository.getEntriesByGlossary(
              glossaryId: glossary.id,
              targetLanguageCode: 'fr',
            )).thenAnswer((_) async => [entry]);

        when(() => mockRepository.incrementUsageCount(any()))
            .thenAnswer((_) async {});

        // Act
        final result = await service.findMatchingTerms(
          sourceText: 'The archer unit.',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
          glossaryIds: ['specific-glossary'],
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value.length, 1);
        verify(() => mockRepository.getGlossariesByIds(['specific-glossary'])).called(1);
      });

      test('should handle database exception gracefully', () async {
        // Arrange
        when(() => mockRepository.getAllGlossaries(
              gameInstallationId: any(named: 'gameInstallationId'),
              includeUniversal: true,
            )).thenThrow(Exception('Database error'));

        // Act
        final result = await service.findMatchingTerms(
          sourceText: 'Test text',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        // Assert
        expect(result.isErr, true);
        expect(result.error.message, contains('Failed to find matching terms'));
      });

      test('should handle multiple matching terms', () async {
        // Arrange
        final glossary = createTestGlossary();
        final entries = [
          createTestEntry(
            id: 'entry-1',
            sourceTerm: 'cavalry',
            targetTerm: 'cavalerie',
          ),
          createTestEntry(
            id: 'entry-2',
            sourceTerm: 'infantry',
            targetTerm: 'infanterie',
          ),
        ];

        when(() => mockRepository.getAllGlossaries(
              gameInstallationId: any(named: 'gameInstallationId'),
              includeUniversal: true,
            )).thenAnswer((_) async => [glossary]);

        when(() => mockRepository.getEntriesByGlossary(
              glossaryId: glossary.id,
              targetLanguageCode: 'fr',
            )).thenAnswer((_) async => entries);

        when(() => mockRepository.incrementUsageCount(any()))
            .thenAnswer((_) async {});

        // Act
        final result = await service.findMatchingTerms(
          sourceText: 'The cavalry and infantry units attacked.',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value.length, 2);
      });
    });

    // =========================================================================
    // applySubstitutions
    // =========================================================================
    group('applySubstitutions', () {
      test('should apply substitutions to target text', () async {
        // Arrange
        final glossary = createTestGlossary();
        final entry = createTestEntry(
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
        );

        when(() => mockRepository.getAllGlossaries(
              gameInstallationId: any(named: 'gameInstallationId'),
              includeUniversal: true,
            )).thenAnswer((_) async => [glossary]);

        when(() => mockRepository.getEntriesByGlossary(
              glossaryId: glossary.id,
              targetLanguageCode: 'fr',
            )).thenAnswer((_) async => [entry]);

        when(() => mockRepository.incrementUsageCount(any()))
            .thenAnswer((_) async {});

        // Act
        final result = await service.applySubstitutions(
          sourceText: 'The cavalry unit attacked.',
          targetText: 'The cavalry unit attacked.',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value, contains('cavalerie'));
      });

      test('should return original text when no matches found', () async {
        // Arrange
        final glossary = createTestGlossary();

        when(() => mockRepository.getAllGlossaries(
              gameInstallationId: any(named: 'gameInstallationId'),
              includeUniversal: true,
            )).thenAnswer((_) async => [glossary]);

        when(() => mockRepository.getEntriesByGlossary(
              glossaryId: glossary.id,
              targetLanguageCode: 'fr',
            )).thenAnswer((_) async => []);

        // Act
        final result = await service.applySubstitutions(
          sourceText: 'Original text.',
          targetText: 'Texte original.',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value, 'Texte original.');
      });

      test('should handle database exception gracefully', () async {
        // Arrange
        when(() => mockRepository.getAllGlossaries(
              gameInstallationId: any(named: 'gameInstallationId'),
              includeUniversal: true,
            )).thenThrow(Exception('Database error'));

        // Act
        final result = await service.applySubstitutions(
          sourceText: 'Test source',
          targetText: 'Test target',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        // Assert
        expect(result.isErr, true);
        expect(result.error.message, contains('Failed to apply substitutions'));
      });
    });

    // =========================================================================
    // checkConsistency
    // =========================================================================
    group('checkConsistency', () {
      test('should return empty list when translation is consistent', () async {
        // Arrange
        final glossary = createTestGlossary();
        final entry = createTestEntry(
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
        );

        when(() => mockRepository.getAllGlossaries(
              gameInstallationId: any(named: 'gameInstallationId'),
              includeUniversal: true,
            )).thenAnswer((_) async => [glossary]);

        when(() => mockRepository.getEntriesByGlossary(
              glossaryId: glossary.id,
              targetLanguageCode: 'fr',
            )).thenAnswer((_) async => [entry]);

        when(() => mockRepository.incrementUsageCount(any()))
            .thenAnswer((_) async {});

        // Act
        final result = await service.checkConsistency(
          sourceText: 'The cavalry unit attacked.',
          targetText: "L'unite de cavalerie a attaque.",
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value.isEmpty, true);
      });

      test('should return inconsistencies when term not found in target', () async {
        // Arrange
        final glossary = createTestGlossary();
        final entry = createTestEntry(
          sourceTerm: 'cavalry',
          targetTerm: 'cavalerie',
        );

        when(() => mockRepository.getAllGlossaries(
              gameInstallationId: any(named: 'gameInstallationId'),
              includeUniversal: true,
            )).thenAnswer((_) async => [glossary]);

        when(() => mockRepository.getEntriesByGlossary(
              glossaryId: glossary.id,
              targetLanguageCode: 'fr',
            )).thenAnswer((_) async => [entry]);

        when(() => mockRepository.incrementUsageCount(any()))
            .thenAnswer((_) async {});

        // Act
        final result = await service.checkConsistency(
          sourceText: 'The cavalry unit attacked.',
          targetText: "L'unite de cheval a attaque.",
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value.isNotEmpty, true);
        expect(result.value.first, contains('cavalry'));
        expect(result.value.first, contains('cavalerie'));
      });

      test('should be case-insensitive when checking consistency', () async {
        // Arrange
        final glossary = createTestGlossary();
        final entry = createTestEntry(
          sourceTerm: 'Cavalry',
          targetTerm: 'Cavalerie',
          caseSensitive: false,
        );

        when(() => mockRepository.getAllGlossaries(
              gameInstallationId: any(named: 'gameInstallationId'),
              includeUniversal: true,
            )).thenAnswer((_) async => [glossary]);

        when(() => mockRepository.getEntriesByGlossary(
              glossaryId: glossary.id,
              targetLanguageCode: 'fr',
            )).thenAnswer((_) async => [entry]);

        when(() => mockRepository.incrementUsageCount(any()))
            .thenAnswer((_) async {});

        // Act
        final result = await service.checkConsistency(
          sourceText: 'The CAVALRY unit attacked.',
          targetText: "L'unite de CAVALERIE a attaque.",
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value.isEmpty, true);
      });

      test('should handle database exception gracefully', () async {
        // Arrange
        when(() => mockRepository.getAllGlossaries(
              gameInstallationId: any(named: 'gameInstallationId'),
              includeUniversal: true,
            )).thenThrow(Exception('Database error'));

        // Act
        final result = await service.checkConsistency(
          sourceText: 'Test source',
          targetText: 'Test target',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        // Assert
        expect(result.isErr, true);
        // Error is propagated from findMatchingTerms which wraps the database error
        expect(result.error.message, contains('Failed to find matching terms'));
      });

      test('should return empty list when no glossary entries exist', () async {
        // Arrange
        final glossary = createTestGlossary();

        when(() => mockRepository.getAllGlossaries(
              gameInstallationId: any(named: 'gameInstallationId'),
              includeUniversal: true,
            )).thenAnswer((_) async => [glossary]);

        when(() => mockRepository.getEntriesByGlossary(
              glossaryId: glossary.id,
              targetLanguageCode: 'fr',
            )).thenAnswer((_) async => []);

        // Act
        final result = await service.checkConsistency(
          sourceText: 'Any text here.',
          targetText: 'Texte ici.',
          sourceLanguageCode: 'en',
          targetLanguageCode: 'fr',
        );

        // Assert
        expect(result.isOk, true);
        expect(result.value.isEmpty, true);
      });
    });
  });
}
