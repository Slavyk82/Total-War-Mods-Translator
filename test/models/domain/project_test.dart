import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/project.dart';

void main() {
  Project makeProject({
    String id = 'p-1',
    String name = 'My Project',
    String? modSteamId,
    String? modVersion,
    String gameInstallationId = 'gi-1',
    String? sourceFilePath,
    String? outputFilePath,
    int? lastUpdateCheck,
    int? sourceModUpdated,
    int batchSize = 25,
    int parallelBatches = 3,
    String? customPrompt,
    int createdAt = 100,
    int updatedAt = 200,
    int? completedAt,
    String? metadata,
    bool hasModUpdateImpact = false,
    String projectType = 'mod',
    String? sourceLanguageCode,
    String? publishedSteamId,
    int? publishedAt,
  }) {
    return Project(
      id: id,
      name: name,
      modSteamId: modSteamId,
      modVersion: modVersion,
      gameInstallationId: gameInstallationId,
      sourceFilePath: sourceFilePath,
      outputFilePath: outputFilePath,
      lastUpdateCheck: lastUpdateCheck,
      sourceModUpdated: sourceModUpdated,
      batchSize: batchSize,
      parallelBatches: parallelBatches,
      customPrompt: customPrompt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      completedAt: completedAt,
      metadata: metadata,
      hasModUpdateImpact: hasModUpdateImpact,
      projectType: projectType,
      sourceLanguageCode: sourceLanguageCode,
      publishedSteamId: publishedSteamId,
      publishedAt: publishedAt,
    );
  }

  group('constructor defaults', () {
    test('uses default values for optional fields', () {
      const project = Project(
        id: 'id',
        name: 'n',
        gameInstallationId: 'gi',
        createdAt: 1,
        updatedAt: 2,
      );
      expect(project.batchSize, 25);
      expect(project.parallelBatches, 3);
      expect(project.hasModUpdateImpact, isFalse);
      expect(project.projectType, 'mod');
      expect(project.modSteamId, isNull);
      expect(project.completedAt, isNull);
    });
  });

  group('boolean getters', () {
    test('hasSourceFile', () {
      expect(makeProject(sourceFilePath: 'a/b.pack').hasSourceFile, isTrue);
      expect(makeProject(sourceFilePath: null).hasSourceFile, isFalse);
      expect(makeProject(sourceFilePath: '').hasSourceFile, isFalse);
    });

    test('hasOutputPath', () {
      expect(makeProject(outputFilePath: 'out/dir').hasOutputPath, isTrue);
      expect(makeProject(outputFilePath: null).hasOutputPath, isFalse);
      expect(makeProject(outputFilePath: '').hasOutputPath, isFalse);
    });

    test('isFromSteamWorkshop', () {
      expect(makeProject(modSteamId: '123456').isFromSteamWorkshop, isTrue);
      expect(makeProject(modSteamId: null).isFromSteamWorkshop, isFalse);
      expect(makeProject(modSteamId: '').isFromSteamWorkshop, isFalse);
    });

    test('isGameTranslation / isModTranslation', () {
      final game = makeProject(projectType: 'game');
      expect(game.isGameTranslation, isTrue);
      expect(game.isModTranslation, isFalse);

      final mod = makeProject(projectType: 'mod');
      expect(mod.isGameTranslation, isFalse);
      expect(mod.isModTranslation, isTrue);
    });
  });

  group('needsUpdateCheck', () {
    test('is true when never checked', () {
      expect(makeProject(lastUpdateCheck: null).needsUpdateCheck, isTrue);
    });

    test('is false when checked recently', () {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(makeProject(lastUpdateCheck: nowSec).needsUpdateCheck, isFalse);
    });

    test('is true when checked more than a day ago', () {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(
        makeProject(lastUpdateCheck: nowSec - 2 * 86400).needsUpdateCheck,
        isTrue,
      );
    });
  });

  group('metadata getters', () {
    test('parsedMetadata is null for null metadata', () {
      expect(makeProject(metadata: null).parsedMetadata, isNull);
    });

    test('parsedMetadata is null for invalid JSON', () {
      expect(makeProject(metadata: 'not json').parsedMetadata, isNull);
    });

    test('parsedMetadata parses valid JSON', () {
      final project = makeProject(
        metadata: '{"mod_title":"Cool Mod","mod_image_url":"http://img"}',
      );
      expect(project.parsedMetadata, isNotNull);
      expect(project.parsedMetadata!.modTitle, 'Cool Mod');
    });

    test('displayName uses metadata modTitle when available', () {
      final project = makeProject(
        name: 'fallback',
        metadata: '{"mod_title":"Cool Mod"}',
      );
      expect(project.displayName, 'Cool Mod');
    });

    test('displayName falls back to name without metadata', () {
      expect(makeProject(name: 'fallback').displayName, 'fallback');
    });

    test('imageUrl comes from metadata, null otherwise', () {
      expect(
        makeProject(metadata: '{"mod_image_url":"http://img"}').imageUrl,
        'http://img',
      );
      expect(makeProject(metadata: null).imageUrl, isNull);
    });
  });

  group('copyWith', () {
    final base = makeProject(
      id: 'a',
      name: 'n',
      modSteamId: 'steam',
      modVersion: 'v1',
      gameInstallationId: 'gi',
      sourceFilePath: 'src',
      outputFilePath: 'out',
      lastUpdateCheck: 10,
      sourceModUpdated: 20,
      batchSize: 30,
      parallelBatches: 2,
      customPrompt: 'prompt',
      createdAt: 100,
      updatedAt: 200,
      completedAt: 300,
      metadata: '{}',
      hasModUpdateImpact: true,
      projectType: 'mod',
      sourceLanguageCode: 'en',
      publishedSteamId: 'pub',
      publishedAt: 400,
    );

    test('no-arg copyWith equals original', () {
      expect(base.copyWith(), base);
    });

    test('overrides each field', () {
      expect(base.copyWith(id: 'z').id, 'z');
      expect(base.copyWith(name: 'z').name, 'z');
      expect(base.copyWith(modSteamId: 'z').modSteamId, 'z');
      expect(base.copyWith(modVersion: 'z').modVersion, 'z');
      expect(base.copyWith(gameInstallationId: 'z').gameInstallationId, 'z');
      expect(base.copyWith(sourceFilePath: 'z').sourceFilePath, 'z');
      expect(base.copyWith(outputFilePath: 'z').outputFilePath, 'z');
      expect(base.copyWith(lastUpdateCheck: 99).lastUpdateCheck, 99);
      expect(base.copyWith(sourceModUpdated: 99).sourceModUpdated, 99);
      expect(base.copyWith(batchSize: 99).batchSize, 99);
      expect(base.copyWith(parallelBatches: 5).parallelBatches, 5);
      expect(base.copyWith(customPrompt: 'z').customPrompt, 'z');
      expect(base.copyWith(createdAt: 99).createdAt, 99);
      expect(base.copyWith(updatedAt: 999).updatedAt, 999);
      expect(base.copyWith(completedAt: 999).completedAt, 999);
      expect(base.copyWith(metadata: '{"a":1}').metadata, '{"a":1}');
      expect(
        base.copyWith(hasModUpdateImpact: false).hasModUpdateImpact,
        isFalse,
      );
      expect(base.copyWith(projectType: 'game').projectType, 'game');
      expect(base.copyWith(sourceLanguageCode: 'fr').sourceLanguageCode, 'fr');
      expect(base.copyWith(publishedSteamId: 'z').publishedSteamId, 'z');
      expect(base.copyWith(publishedAt: 999).publishedAt, 999);
    });

    test('unset fields fall back to current values', () {
      final copy = base.copyWith(name: 'other');
      expect(copy.id, base.id);
      expect(copy.modSteamId, base.modSteamId);
      expect(copy.gameInstallationId, base.gameInstallationId);
      expect(copy.batchSize, base.batchSize);
      expect(copy.hasModUpdateImpact, base.hasModUpdateImpact);
      expect(copy.projectType, base.projectType);
      expect(copy.publishedAt, base.publishedAt);
    });
  });

  group('JSON', () {
    final full = makeProject(
      id: 'a',
      name: 'n',
      modSteamId: 'steam',
      modVersion: 'v1',
      gameInstallationId: 'gi',
      sourceFilePath: 'src',
      outputFilePath: 'out',
      lastUpdateCheck: 10,
      sourceModUpdated: 20,
      batchSize: 30,
      parallelBatches: 2,
      customPrompt: 'prompt',
      createdAt: 100,
      updatedAt: 200,
      completedAt: 300,
      metadata: '{}',
      hasModUpdateImpact: true,
      projectType: 'game',
      sourceLanguageCode: 'en',
      publishedSteamId: 'pub',
      publishedAt: 400,
    );

    test('toJson uses snake_case keys and serializes bool as int', () {
      final json = full.toJson();
      expect(json['id'], 'a');
      expect(json['mod_steam_id'], 'steam');
      expect(json['game_installation_id'], 'gi');
      expect(json['batch_size'], 30);
      expect(json['parallel_batches'], 2);
      expect(json['has_mod_update_impact'], 1);
      expect(json['project_type'], 'game');
      expect(json['source_language_code'], 'en');
      expect(json['published_steam_id'], 'pub');
      expect(json['published_at'], 400);
    });

    test('toJson serializes false hasModUpdateImpact as 0', () {
      expect(
        makeProject(hasModUpdateImpact: false).toJson()['has_mod_update_impact'],
        0,
      );
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(full.toJson());
      final decoded =
          Project.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, full);
    });

    test('fromJson applies defaults for missing optional fields', () {
      final decoded = Project.fromJson({
        'id': 'a',
        'name': 'n',
        'game_installation_id': 'gi',
        'created_at': 1,
        'updated_at': 2,
      });
      expect(decoded.batchSize, 25);
      expect(decoded.parallelBatches, 3);
      expect(decoded.hasModUpdateImpact, isFalse);
      expect(decoded.projectType, 'mod');
    });

    test('fromJson decodes has_mod_update_impact from int/bool/null', () {
      Project decode(dynamic raw) => Project.fromJson({
            'id': 'a',
            'name': 'n',
            'game_installation_id': 'gi',
            'created_at': 1,
            'updated_at': 2,
            'has_mod_update_impact': raw,
          });
      expect(decode(1).hasModUpdateImpact, isTrue);
      expect(decode(0).hasModUpdateImpact, isFalse);
      expect(decode(true).hasModUpdateImpact, isTrue);
      expect(decode(false).hasModUpdateImpact, isFalse);
      expect(decode(null).hasModUpdateImpact, isFalse);
      // Unsupported types coerce to false rather than throwing
      expect(decode('yes').hasModUpdateImpact, isFalse);
    });
  });

  group('equality and hashCode', () {
    final a = makeProject(
      id: 'a',
      modSteamId: 'steam',
      metadata: '{}',
      hasModUpdateImpact: true,
      publishedSteamId: 'pub',
    );

    test('identical instance is equal', () {
      expect(a == a, isTrue);
    });

    test('equal field-for-field copies are equal with same hashCode', () {
      final b = a.copyWith();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs when any field differs', () {
      expect(a == a.copyWith(id: 'z'), isFalse);
      expect(a == a.copyWith(name: 'z'), isFalse);
      expect(a == a.copyWith(modSteamId: 'z'), isFalse);
      expect(a == a.copyWith(gameInstallationId: 'z'), isFalse);
      expect(a == a.copyWith(batchSize: 99), isFalse);
      expect(a == a.copyWith(hasModUpdateImpact: false), isFalse);
      expect(a == a.copyWith(projectType: 'game'), isFalse);
      expect(a == a.copyWith(publishedSteamId: 'z'), isFalse);
      expect(a == a.copyWith(publishedAt: 999), isFalse);
    });

    test('is not equal to a different type', () {
      expect(a == Object(), isFalse);
    });
  });

  group('toString', () {
    test('includes id, name, type and gameInstallationId', () {
      final project = makeProject(
        id: 'a',
        name: 'n',
        projectType: 'mod',
        gameInstallationId: 'gi',
      );
      expect(
        project.toString(),
        'Project(id: a, name: n, type: mod, gameInstallationId: gi)',
      );
    });
  });
}
