import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/project_publication_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late ProjectPublicationRepository repo;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = ProjectPublicationRepository();
    await db.delete('project_publication');
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('ProjectPublicationRepository', () {
    test('setPublication inserts then updates both fields on conflict',
        () async {
      final ins = await repo.setPublication('p1', 'fr', '111', 1000);
      expect(ins.isOk, isTrue);

      var rows = await db.query('project_publication');
      expect(rows, hasLength(1));
      expect(rows.first['steam_id'], '111');
      expect(rows.first['published_at'], 1000);

      final upd = await repo.setPublication('p1', 'fr', '222', 2000);
      expect(upd.isOk, isTrue);
      rows = await db.query('project_publication');
      expect(rows, hasLength(1)); // same PK -> updated, not duplicated
      expect(rows.first['steam_id'], '222');
      expect(rows.first['published_at'], 2000);
    });

    test('setSteamId preserves existing published_at', () async {
      await repo.setPublication('p1', 'fr', '111', 1000);

      final res = await repo.setSteamId('p1', 'fr', '999');
      expect(res.isOk, isTrue);

      final rows = await db.query('project_publication');
      expect(rows.first['steam_id'], '999');
      expect(rows.first['published_at'], 1000); // unchanged
    });

    test('getAll and getByProject return inserted rows', () async {
      await repo.setPublication('p1', 'fr', '111', 1000);
      await repo.setPublication('p2', 'de', '222', 2000);

      final all = await repo.getAll();
      expect(all.isOk, isTrue);
      expect(all.value, hasLength(2));

      final byProject = await repo.getByProject('p1');
      expect(byProject.isOk, isTrue);
      expect(byProject.value, hasLength(1));
      expect(byProject.value.first.steamId, '111');
      expect(byProject.value.first.languageCode, 'fr');
    });
  });
}
