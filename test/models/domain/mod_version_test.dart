import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/mod_version.dart';

void main() {
  ModVersion makeVersion({
    String id = 'mv-1',
    String projectId = 'p-1',
    String versionString = '1.0.0',
    int? releaseDate,
    int? steamUpdateTimestamp,
    int unitsAdded = 0,
    int unitsModified = 0,
    int unitsDeleted = 0,
    bool isCurrent = true,
    int detectedAt = 100,
  }) {
    return ModVersion(
      id: id,
      projectId: projectId,
      versionString: versionString,
      releaseDate: releaseDate,
      steamUpdateTimestamp: steamUpdateTimestamp,
      unitsAdded: unitsAdded,
      unitsModified: unitsModified,
      unitsDeleted: unitsDeleted,
      isCurrent: isCurrent,
      detectedAt: detectedAt,
    );
  }

  group('constructor defaults', () {
    test('uses default values for optional fields', () {
      const version = ModVersion(
        id: 'id',
        projectId: 'p',
        versionString: '1.0',
        detectedAt: 1,
      );
      expect(version.releaseDate, isNull);
      expect(version.steamUpdateTimestamp, isNull);
      expect(version.unitsAdded, 0);
      expect(version.unitsModified, 0);
      expect(version.unitsDeleted, 0);
      expect(version.isCurrent, isTrue);
    });
  });

  group('change getters', () {
    test('isCurrentVersion mirrors isCurrent', () {
      expect(makeVersion(isCurrent: true).isCurrentVersion, isTrue);
      expect(makeVersion(isCurrent: false).isCurrentVersion, isFalse);
    });

    test('hasChanges', () {
      expect(makeVersion().hasChanges, isFalse);
      expect(makeVersion(unitsAdded: 1).hasChanges, isTrue);
      expect(makeVersion(unitsModified: 1).hasChanges, isTrue);
      expect(makeVersion(unitsDeleted: 1).hasChanges, isTrue);
    });

    test('totalChanges sums all counters', () {
      expect(
        makeVersion(unitsAdded: 2, unitsModified: 3, unitsDeleted: 4)
            .totalChanges,
        9,
      );
    });

    test('hasAdditions / hasModifications / hasDeletions', () {
      final version =
          makeVersion(unitsAdded: 1, unitsModified: 0, unitsDeleted: 0);
      expect(version.hasAdditions, isTrue);
      expect(version.hasModifications, isFalse);
      expect(version.hasDeletions, isFalse);

      expect(makeVersion(unitsModified: 2).hasModifications, isTrue);
      expect(makeVersion(unitsDeleted: 2).hasDeletions, isTrue);
    });

    test('isFromSteam / hasReleaseDate', () {
      expect(makeVersion(steamUpdateTimestamp: 1).isFromSteam, isTrue);
      expect(makeVersion(steamUpdateTimestamp: null).isFromSteam, isFalse);
      expect(makeVersion(releaseDate: 1).hasReleaseDate, isTrue);
      expect(makeVersion(releaseDate: null).hasReleaseDate, isFalse);
    });
  });

  group('changesSummary', () {
    test('returns "No changes" when there are none', () {
      expect(makeVersion().changesSummary, 'No changes');
    });

    test('includes only non-zero parts', () {
      expect(makeVersion(unitsAdded: 2).changesSummary, '+2 added');
      expect(makeVersion(unitsModified: 3).changesSummary, '~3 modified');
      expect(makeVersion(unitsDeleted: 4).changesSummary, '-4 deleted');
    });

    test('joins multiple parts with comma', () {
      expect(
        makeVersion(unitsAdded: 2, unitsModified: 3, unitsDeleted: 4)
            .changesSummary,
        '+2 added, ~3 modified, -4 deleted',
      );
    });
  });

  group('displayName', () {
    test('tags current version', () {
      expect(
        makeVersion(versionString: '1.2.3', isCurrent: true).displayName,
        '1.2.3 (Current)',
      );
    });

    test('plain version string when not current', () {
      expect(
        makeVersion(versionString: '1.2.3', isCurrent: false).displayName,
        '1.2.3',
      );
    });
  });

  group('DateTime getters', () {
    test('releaseDateAsDateTime converts unix seconds', () {
      expect(makeVersion(releaseDate: null).releaseDateAsDateTime, isNull);
      expect(
        makeVersion(releaseDate: 1000).releaseDateAsDateTime,
        DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
      );
    });

    test('steamUpdateAsDateTime converts unix seconds', () {
      expect(
        makeVersion(steamUpdateTimestamp: null).steamUpdateAsDateTime,
        isNull,
      );
      expect(
        makeVersion(steamUpdateTimestamp: 2000).steamUpdateAsDateTime,
        DateTime.fromMillisecondsSinceEpoch(2000 * 1000),
      );
    });
  });

  group('copyWith', () {
    final base = makeVersion(
      id: 'a',
      projectId: 'p',
      versionString: '1.0',
      releaseDate: 10,
      steamUpdateTimestamp: 20,
      unitsAdded: 1,
      unitsModified: 2,
      unitsDeleted: 3,
      isCurrent: true,
      detectedAt: 100,
    );

    test('no-arg copyWith equals original', () {
      expect(base.copyWith(), base);
    });

    test('overrides each field', () {
      expect(base.copyWith(id: 'z').id, 'z');
      expect(base.copyWith(projectId: 'z').projectId, 'z');
      expect(base.copyWith(versionString: '2.0').versionString, '2.0');
      expect(base.copyWith(releaseDate: 99).releaseDate, 99);
      expect(
        base.copyWith(steamUpdateTimestamp: 99).steamUpdateTimestamp,
        99,
      );
      expect(base.copyWith(unitsAdded: 9).unitsAdded, 9);
      expect(base.copyWith(unitsModified: 9).unitsModified, 9);
      expect(base.copyWith(unitsDeleted: 9).unitsDeleted, 9);
      expect(base.copyWith(isCurrent: false).isCurrent, isFalse);
      expect(base.copyWith(detectedAt: 999).detectedAt, 999);
    });

    test('unset fields fall back to current values', () {
      final copy = base.copyWith(versionString: '2.0');
      expect(copy.id, base.id);
      expect(copy.projectId, base.projectId);
      expect(copy.releaseDate, base.releaseDate);
      expect(copy.steamUpdateTimestamp, base.steamUpdateTimestamp);
      expect(copy.unitsAdded, base.unitsAdded);
      expect(copy.isCurrent, base.isCurrent);
      expect(copy.detectedAt, base.detectedAt);
    });
  });

  group('JSON', () {
    final full = makeVersion(
      id: 'a',
      projectId: 'p',
      versionString: '1.0',
      releaseDate: 10,
      steamUpdateTimestamp: 20,
      unitsAdded: 1,
      unitsModified: 2,
      unitsDeleted: 3,
      isCurrent: true,
      detectedAt: 100,
    );

    test('toJson uses snake_case keys and serializes is_current as int', () {
      final json = full.toJson();
      expect(json['id'], 'a');
      expect(json['project_id'], 'p');
      expect(json['version_string'], '1.0');
      expect(json['release_date'], 10);
      expect(json['steam_update_timestamp'], 20);
      expect(json['units_added'], 1);
      expect(json['units_modified'], 2);
      expect(json['units_deleted'], 3);
      expect(json['is_current'], 1);
      expect(json['detected_at'], 100);

      expect(makeVersion(isCurrent: false).toJson()['is_current'], 0);
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(full.toJson());
      final decoded =
          ModVersion.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, full);
    });

    test('fromJson decodes is_current from int and bool', () {
      ModVersion decode(dynamic raw) => ModVersion.fromJson({
            'id': 'a',
            'project_id': 'p',
            'version_string': '1.0',
            'detected_at': 1,
            'is_current': raw,
          });
      expect(decode(1).isCurrent, isTrue);
      expect(decode(0).isCurrent, isFalse);
      expect(decode(true).isCurrent, isTrue);
      expect(decode('1').isCurrent, isTrue);
      expect(decode('true').isCurrent, isTrue);
      expect(decode('0').isCurrent, isFalse);
    });

    test('fromJson applies defaults for missing optional fields', () {
      final decoded = ModVersion.fromJson({
        'id': 'a',
        'project_id': 'p',
        'version_string': '1.0',
        'detected_at': 1,
      });
      expect(decoded.unitsAdded, 0);
      expect(decoded.unitsModified, 0);
      expect(decoded.unitsDeleted, 0);
      expect(decoded.releaseDate, isNull);
    });
  });

  group('equality and hashCode', () {
    final a = makeVersion(
      id: 'a',
      releaseDate: 10,
      steamUpdateTimestamp: 20,
      unitsAdded: 1,
      unitsModified: 2,
      unitsDeleted: 3,
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
      expect(a == a.copyWith(projectId: 'z'), isFalse);
      expect(a == a.copyWith(versionString: '9.9'), isFalse);
      expect(a == a.copyWith(releaseDate: 99), isFalse);
      expect(a == a.copyWith(steamUpdateTimestamp: 99), isFalse);
      expect(a == a.copyWith(unitsAdded: 9), isFalse);
      expect(a == a.copyWith(unitsModified: 9), isFalse);
      expect(a == a.copyWith(unitsDeleted: 9), isFalse);
      expect(a == a.copyWith(isCurrent: false), isFalse);
      expect(a == a.copyWith(detectedAt: 999), isFalse);
    });

    test('is not equal to a different type', () {
      expect(a == Object(), isFalse);
    });
  });

  group('toString', () {
    test('includes id, versionString, isCurrent and changes summary', () {
      final version = makeVersion(
        id: 'a',
        versionString: '1.0',
        isCurrent: true,
        unitsAdded: 2,
      );
      expect(
        version.toString(),
        'ModVersion(id: a, versionString: 1.0, isCurrent: true, '
        'changes: +2 added)',
      );
    });
  });
}
