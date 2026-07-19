import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/compilation.dart';

void main() {
  Compilation makeCompilation({
    String id = 'c-1',
    String name = 'My Compilation',
    String prefix = '!!!_FR_',
    String packName = 'my_translations',
    String gameInstallationId = 'gi-1',
    String? languageId,
    String? lastOutputPath,
    int? lastGeneratedAt,
    String? publishedSteamId,
    int? publishedAt,
    int createdAt = 100,
    int updatedAt = 200,
  }) {
    return Compilation(
      id: id,
      name: name,
      prefix: prefix,
      packName: packName,
      gameInstallationId: gameInstallationId,
      languageId: languageId,
      lastOutputPath: lastOutputPath,
      lastGeneratedAt: lastGeneratedAt,
      publishedSteamId: publishedSteamId,
      publishedAt: publishedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  group('Compilation computed getters', () {
    test('fullPackFileName concatenates prefix and packName lowercase', () {
      final compilation = makeCompilation(
        prefix: '!!!_FR_',
        packName: 'My_Translations',
      );
      expect(compilation.fullPackFileName, '!!!_fr_my_translations.pack');
    });

    test('hasBeenGenerated', () {
      expect(makeCompilation(lastGeneratedAt: 123).hasBeenGenerated, isTrue);
      expect(makeCompilation(lastGeneratedAt: null).hasBeenGenerated, isFalse);
    });
  });

  group('Compilation copyWith', () {
    final base = makeCompilation(
      id: 'a',
      name: 'n',
      prefix: 'p_',
      packName: 'pack',
      gameInstallationId: 'gi',
      languageId: 'lang',
      lastOutputPath: 'out',
      lastGeneratedAt: 10,
      publishedSteamId: 'pub',
      publishedAt: 20,
      createdAt: 100,
      updatedAt: 200,
    );

    test('no-arg copyWith equals original', () {
      expect(base.copyWith(), base);
    });

    test('overrides each field', () {
      expect(base.copyWith(id: 'z').id, 'z');
      expect(base.copyWith(name: 'z').name, 'z');
      expect(base.copyWith(prefix: 'z_').prefix, 'z_');
      expect(base.copyWith(packName: 'z').packName, 'z');
      expect(base.copyWith(gameInstallationId: 'z').gameInstallationId, 'z');
      expect(base.copyWith(languageId: 'z').languageId, 'z');
      expect(base.copyWith(lastOutputPath: 'z').lastOutputPath, 'z');
      expect(base.copyWith(lastGeneratedAt: 99).lastGeneratedAt, 99);
      expect(base.copyWith(publishedSteamId: 'z').publishedSteamId, 'z');
      expect(base.copyWith(publishedAt: 99).publishedAt, 99);
      expect(base.copyWith(createdAt: 99).createdAt, 99);
      expect(base.copyWith(updatedAt: 999).updatedAt, 999);
    });

    test('unset fields fall back to current values', () {
      final copy = base.copyWith(name: 'other');
      expect(copy.id, base.id);
      expect(copy.prefix, base.prefix);
      expect(copy.packName, base.packName);
      expect(copy.gameInstallationId, base.gameInstallationId);
      expect(copy.languageId, base.languageId);
      expect(copy.lastOutputPath, base.lastOutputPath);
      expect(copy.lastGeneratedAt, base.lastGeneratedAt);
      expect(copy.publishedSteamId, base.publishedSteamId);
      expect(copy.publishedAt, base.publishedAt);
      expect(copy.createdAt, base.createdAt);
      expect(copy.updatedAt, base.updatedAt);
    });
  });

  group('Compilation JSON', () {
    final full = makeCompilation(
      id: 'a',
      name: 'n',
      prefix: 'p_',
      packName: 'pack',
      gameInstallationId: 'gi',
      languageId: 'lang',
      lastOutputPath: 'out',
      lastGeneratedAt: 10,
      publishedSteamId: 'pub',
      publishedAt: 20,
      createdAt: 100,
      updatedAt: 200,
    );

    test('toJson uses snake_case keys', () {
      final json = full.toJson();
      expect(json['id'], 'a');
      expect(json['name'], 'n');
      expect(json['prefix'], 'p_');
      expect(json['pack_name'], 'pack');
      expect(json['game_installation_id'], 'gi');
      expect(json['language_id'], 'lang');
      expect(json['last_output_path'], 'out');
      expect(json['last_generated_at'], 10);
      expect(json['published_steam_id'], 'pub');
      expect(json['published_at'], 20);
      expect(json['created_at'], 100);
      expect(json['updated_at'], 200);
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(full.toJson());
      final decoded =
          Compilation.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, full);
    });

    test('fromJson accepts missing optional fields', () {
      final decoded = Compilation.fromJson({
        'id': 'a',
        'name': 'n',
        'prefix': 'p_',
        'pack_name': 'pack',
        'game_installation_id': 'gi',
        'created_at': 1,
        'updated_at': 2,
      });
      expect(decoded.languageId, isNull);
      expect(decoded.lastOutputPath, isNull);
      expect(decoded.lastGeneratedAt, isNull);
      expect(decoded.publishedSteamId, isNull);
      expect(decoded.publishedAt, isNull);
    });
  });

  group('Compilation equality and hashCode', () {
    final a = makeCompilation(
      id: 'a',
      languageId: 'lang',
      lastOutputPath: 'out',
      lastGeneratedAt: 10,
      publishedSteamId: 'pub',
      publishedAt: 20,
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
      expect(a == a.copyWith(prefix: 'z_'), isFalse);
      expect(a == a.copyWith(packName: 'z'), isFalse);
      expect(a == a.copyWith(gameInstallationId: 'z'), isFalse);
      expect(a == a.copyWith(languageId: 'z'), isFalse);
      expect(a == a.copyWith(lastOutputPath: 'z'), isFalse);
      expect(a == a.copyWith(lastGeneratedAt: 99), isFalse);
      expect(a == a.copyWith(publishedSteamId: 'z'), isFalse);
      expect(a == a.copyWith(publishedAt: 99), isFalse);
      expect(a == a.copyWith(createdAt: 99), isFalse);
      expect(a == a.copyWith(updatedAt: 999), isFalse);
    });

    test('is not equal to a different type', () {
      expect(a == Object(), isFalse);
    });
  });

  group('Compilation toString', () {
    test('includes id, name and full pack filename', () {
      final compilation = makeCompilation(
        id: 'a',
        name: 'n',
        prefix: 'P_',
        packName: 'Pack',
      );
      expect(
        compilation.toString(),
        'Compilation(id: a, name: n, packName: p_pack.pack)',
      );
    });
  });

  group('CompilationProject', () {
    CompilationProject makeLink({
      String id = 'cp-1',
      String compilationId = 'c-1',
      String projectId = 'p-1',
      int sortOrder = 1,
      int addedAt = 100,
    }) {
      return CompilationProject(
        id: id,
        compilationId: compilationId,
        projectId: projectId,
        sortOrder: sortOrder,
        addedAt: addedAt,
      );
    }

    test('copyWith overrides each field and keeps the rest', () {
      final base = makeLink();
      expect(base.copyWith(), base);
      expect(base.copyWith(id: 'z').id, 'z');
      expect(base.copyWith(compilationId: 'z').compilationId, 'z');
      expect(base.copyWith(projectId: 'z').projectId, 'z');
      expect(base.copyWith(sortOrder: 9).sortOrder, 9);
      expect(base.copyWith(addedAt: 999).addedAt, 999);

      final copy = base.copyWith(sortOrder: 9);
      expect(copy.id, base.id);
      expect(copy.compilationId, base.compilationId);
      expect(copy.projectId, base.projectId);
      expect(copy.addedAt, base.addedAt);
    });

    test('JSON round-trip with snake_case keys', () {
      final link = makeLink(
        id: 'a',
        compilationId: 'c',
        projectId: 'p',
        sortOrder: 3,
        addedAt: 500,
      );
      final json = link.toJson();
      expect(json['id'], 'a');
      expect(json['compilation_id'], 'c');
      expect(json['project_id'], 'p');
      expect(json['sort_order'], 3);
      expect(json['added_at'], 500);

      final decoded = CompilationProject.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(decoded, link);
    });

    test('equality and hashCode', () {
      final a = makeLink();
      final b = a.copyWith();
      expect(a == a, isTrue);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(id: 'z'), isFalse);
      expect(a == a.copyWith(compilationId: 'z'), isFalse);
      expect(a == a.copyWith(projectId: 'z'), isFalse);
      expect(a == a.copyWith(sortOrder: 9), isFalse);
      expect(a == a.copyWith(addedAt: 999), isFalse);
      expect(a == Object(), isFalse);
    });

    test('toString includes compilationId and projectId', () {
      expect(
        makeLink(compilationId: 'c', projectId: 'p').toString(),
        'CompilationProject(compilationId: c, projectId: p)',
      );
    });
  });
}
