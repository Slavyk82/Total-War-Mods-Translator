import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final db = await databaseFactory.openDatabase(
    r'C:\Users\JMP\AppData\Roaming\com.github.slavyk82\twmt\twmt.db',
    options: OpenDatabaseOptions(readOnly: true),
  );

  // Find the project_language with ~628 units
  print('=== Finding project_language with ~628 units ===');
  final plResult = await db.rawQuery('''
    SELECT pl.id, p.name, COUNT(*) as cnt
    FROM project_languages pl
    INNER JOIN projects p ON pl.project_id = p.id
    INNER JOIN translation_versions tv ON tv.project_language_id = pl.id
    INNER JOIN translation_units tu ON tv.unit_id = tu.id
    WHERE tu.is_obsolete = 0
    GROUP BY pl.id, p.name
    HAVING cnt BETWEEN 620 AND 640
    ORDER BY cnt DESC
  ''');

  if (plResult.isEmpty) {
    print('No project found with ~628 units');
    await db.close();
    return;
  }

  // Print all matches
  for (final row in plResult) {
    print('Found: ${row['name']} with ${row['cnt']} units');
  }

  final projectLanguageId = plResult.first['id'] as String;
  final projectName = plResult.first['name'] as String;
  print('\nAnalyzing: $projectName');
  print('Project Language ID: $projectLanguageId');

  // Run the EXACT query from getLanguageStatistics
  print('\n=== Exact getLanguageStatistics query ===');
  final statsResult = await db.rawQuery('''
    SELECT
      COUNT(CASE WHEN tv.status = 'translated' THEN 1 END) as translated_count,
      COUNT(CASE WHEN tv.status IN ('pending', 'translating') THEN 1 END) as pending_count,
      COUNT(CASE WHEN tv.status IN ('approved', 'reviewed') THEN 1 END) as validated_count,
      COUNT(CASE WHEN tv.status = 'needs_review' THEN 1 END) as error_count
    FROM translation_versions tv
    INNER JOIN translation_units tu ON tv.unit_id = tu.id
    WHERE tv.project_language_id = ?
      AND tu.is_obsolete = 0
  ''', [projectLanguageId]);

  final stats = statsResult.first;
  print('Translated: ${stats['translated_count']}');
  print('Pending: ${stats['pending_count']}');
  print('Validated: ${stats['validated_count']}');
  print('Error: ${stats['error_count']}');

  // Check how totalUnits is calculated in the provider
  print('\n=== Total units calculation (like provider) ===');
  final projectResult = await db.rawQuery('''
    SELECT p.id FROM project_languages pl
    INNER JOIN projects p ON pl.project_id = p.id
    WHERE pl.id = ?
  ''', [projectLanguageId]);
  final projectId = projectResult.first['id'] as String;

  final unitsResult = await db.rawQuery('''
    SELECT COUNT(*) as count FROM translation_units
    WHERE project_id = ? AND is_obsolete = 0
  ''', [projectId]);
  print('Total units (non-obsolete): ${unitsResult.first['count']}');

  // Check if there are any orphaned versions (versions without matching units)
  print('\n=== Checking for orphaned/mismatched data ===');
  final orphanCheck = await db.rawQuery('''
    SELECT COUNT(*) as count
    FROM translation_versions tv
    LEFT JOIN translation_units tu ON tv.unit_id = tu.id
    WHERE tv.project_language_id = ?
      AND (tu.id IS NULL OR tu.is_obsolete = 1)
  ''', [projectLanguageId]);
  print('Versions with obsolete/missing units: ${orphanCheck.first['count']}');

  // Check if there might be units without versions
  print('\n=== Units WITHOUT versions ===');
  final noVersions = await db.rawQuery('''
    SELECT COUNT(*) as count
    FROM translation_units tu
    WHERE tu.project_id = ?
      AND tu.is_obsolete = 0
      AND NOT EXISTS (
        SELECT 1 FROM translation_versions tv
        WHERE tv.unit_id = tu.id AND tv.project_language_id = ?
      )
  ''', [projectId, projectLanguageId]);
  print('Units without versions: ${noVersions.first['count']}');

  // Double check - count versions directly
  print('\n=== Direct version count ===');
  final directCount = await db.rawQuery('''
    SELECT COUNT(*) as total,
           COUNT(CASE WHEN status = 'translated' THEN 1 END) as translated
    FROM translation_versions
    WHERE project_language_id = ?
  ''', [projectLanguageId]);
  print('Total versions: ${directCount.first['total']}');
  print('Translated versions: ${directCount.first['translated']}');

  // Check obsolete units count
  print('\n=== Obsolete units check ===');
  final obsoleteUnits = await db.rawQuery('''
    SELECT
      COUNT(*) as total_units,
      COUNT(CASE WHEN is_obsolete = 1 THEN 1 END) as obsolete_count,
      COUNT(CASE WHEN is_obsolete = 0 THEN 1 END) as active_count
    FROM translation_units
    WHERE project_id = ?
  ''', [projectId]);
  print('Total units (all): ${obsoleteUnits.first['total_units']}');
  print('Obsolete: ${obsoleteUnits.first['obsolete_count']}');
  print('Active: ${obsoleteUnits.first['active_count']}');

  // Check versions for obsolete units
  print('\n=== Versions linked to obsolete units ===');
  final versionsForObsolete = await db.rawQuery('''
    SELECT COUNT(*) as count,
           COUNT(CASE WHEN tv.status = 'translated' THEN 1 END) as translated
    FROM translation_versions tv
    INNER JOIN translation_units tu ON tv.unit_id = tu.id
    WHERE tv.project_language_id = ?
      AND tu.is_obsolete = 1
  ''', [projectLanguageId]);
  print('Versions for obsolete units: ${versionsForObsolete.first['count']}');
  print('Of which translated: ${versionsForObsolete.first['translated']}');

  // List ALL projects with their counts
  print('\n=== All projects with French language ===');
  final allProjects = await db.rawQuery('''
    SELECT
      p.name,
      COUNT(DISTINCT tu.id) as total_units,
      COUNT(DISTINCT CASE WHEN tu.is_obsolete = 0 THEN tu.id END) as active_units,
      SUM(CASE WHEN tv.status = 'translated' AND tu.is_obsolete = 0 THEN 1 ELSE 0 END) as translated_active,
      SUM(CASE WHEN tv.status = 'pending' AND tu.is_obsolete = 0 THEN 1 ELSE 0 END) as pending_active
    FROM projects p
    INNER JOIN translation_units tu ON tu.project_id = p.id
    INNER JOIN project_languages pl ON pl.project_id = p.id
    LEFT JOIN translation_versions tv ON tv.unit_id = tu.id AND tv.project_language_id = pl.id
    INNER JOIN languages l ON pl.language_id = l.id
    WHERE l.code = 'fr'
    GROUP BY p.name
    ORDER BY active_units DESC
    LIMIT 10
  ''');
  for (final row in allProjects) {
    print('${row['name']}:');
    print('  Total units: ${row['total_units']} (active: ${row['active_units']})');
    print('  Translated (active): ${row['translated_active']}');
    print('  Pending (active): ${row['pending_active']}');
  }

  await db.close();
}
