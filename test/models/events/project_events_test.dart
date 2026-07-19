import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/events/project_events.dart';

void main() {
  group('ProjectCreatedEvent', () {
    ProjectCreatedEvent makeEvent() => ProjectCreatedEvent(
          projectId: 'p1',
          projectName: 'My Project',
          gameInstallationId: 'gi1',
          targetLanguageIds: ['fr', 'de'],
        );

    test('constructs and exposes fields', () {
      final event = makeEvent();
      expect(event.projectId, 'p1');
      expect(event.projectName, 'My Project');
      expect(event.gameInstallationId, 'gi1');
      expect(event.targetLanguageIds, ['fr', 'de']);

      // Inherited from DomainEvent.now()
      expect(event.eventId, isNotEmpty);
      expect(event.timestamp, isA<DateTime>());
      expect(event.eventType, 'ProjectCreatedEvent');
      expect(event.occurredAt, event.timestamp);
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes name and language count', () {
      expect(
        makeEvent().toString(),
        'ProjectCreatedEvent(projectId: p1, name: My Project, languages: 2)',
      );
    });
  });

  group('ProjectUpdatedEvent', () {
    ProjectUpdatedEvent makeEvent() => ProjectUpdatedEvent(
          projectId: 'p1',
          projectName: 'New Name',
          description: 'desc',
          changes: {'name': 'New Name', 'batch_size': 30},
        );

    test('constructs and exposes fields', () {
      final event = makeEvent();
      expect(event.projectId, 'p1');
      expect(event.projectName, 'New Name');
      expect(event.description, 'desc');
      expect(event.changes, {'name': 'New Name', 'batch_size': 30});
    });

    test('optional fields default to null', () {
      final event = ProjectUpdatedEvent(projectId: 'p1', changes: const {});
      expect(event.projectName, isNull);
      expect(event.description, isNull);
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString joins change keys', () {
      expect(
        makeEvent().toString(),
        'ProjectUpdatedEvent(projectId: p1, changes: name, batch_size)',
      );
    });
  });

  group('ProjectLanguageProgressUpdatedEvent', () {
    ProjectLanguageProgressUpdatedEvent makeEvent({
      double oldProgress = 25.0,
      double newProgress = 75.0,
    }) =>
        ProjectLanguageProgressUpdatedEvent(
          projectLanguageId: 'pl1',
          projectId: 'p1',
          languageId: 'fr',
          oldProgress: oldProgress,
          newProgress: newProgress,
        );

    test('constructs and exposes fields', () {
      final event = makeEvent();
      expect(event.projectLanguageId, 'pl1');
      expect(event.projectId, 'p1');
      expect(event.languageId, 'fr');
      expect(event.oldProgress, 25.0);
      expect(event.newProgress, 75.0);
    });

    test('progressDelta', () {
      expect(makeEvent(oldProgress: 25.0, newProgress: 75.0).progressDelta,
          50.0);
      expect(makeEvent(oldProgress: 75.0, newProgress: 25.0).progressDelta,
          -50.0);
    });

    test('isComplete at 100 percent', () {
      expect(makeEvent(newProgress: 100.0).isComplete, isTrue);
      expect(makeEvent(newProgress: 99.9).isComplete, isFalse);
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString formats progress range', () {
      expect(
        makeEvent(oldProgress: 25.0, newProgress: 75.5).toString(),
        'ProjectLanguageProgressUpdatedEvent(projectLanguageId: pl1, '
        '25.0% -> 75.5%)',
      );
    });
  });

  group('ModUpdateDetectedEvent', () {
    ModUpdateDetectedEvent makeEvent({
      int unitsAdded = 5,
      int unitsModified = 3,
      int unitsDeleted = 1,
    }) =>
        ModUpdateDetectedEvent(
          projectId: 'p1',
          versionString: '2.0',
          unitsAdded: unitsAdded,
          unitsModified: unitsModified,
          unitsDeleted: unitsDeleted,
        );

    test('constructs and exposes fields', () {
      final event = makeEvent();
      expect(event.projectId, 'p1');
      expect(event.versionString, '2.0');
      expect(event.unitsAdded, 5);
      expect(event.unitsModified, 3);
      expect(event.unitsDeleted, 1);
    });

    test('totalChanges sums counters', () {
      expect(makeEvent().totalChanges, 9);
    });

    test('hasSignificantChanges at the 10 changes threshold', () {
      expect(
        makeEvent(unitsAdded: 5, unitsModified: 4, unitsDeleted: 1)
            .hasSignificantChanges,
        isTrue,
      );
      expect(
        makeEvent(unitsAdded: 5, unitsModified: 3, unitsDeleted: 1)
            .hasSignificantChanges,
        isFalse,
      );
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes version and change breakdown', () {
      expect(
        makeEvent().toString(),
        'ModUpdateDetectedEvent(projectId: p1, version: 2.0, '
        'changes: +5 ~3 -1)',
      );
    });
  });

  group('ProjectCompletedEvent', () {
    ProjectCompletedEvent makeEvent() => ProjectCompletedEvent(
          projectId: 'p1',
          projectName: 'My Project',
          totalUnits: 500,
          completedLanguages: 2,
          totalDuration: const Duration(hours: 3, minutes: 20),
        );

    test('constructs and exposes fields', () {
      final event = makeEvent();
      expect(event.projectId, 'p1');
      expect(event.projectName, 'My Project');
      expect(event.totalUnits, 500);
      expect(event.completedLanguages, 2);
      expect(event.totalDuration, const Duration(hours: 3, minutes: 20));
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes units, languages and hours', () {
      expect(
        makeEvent().toString(),
        'ProjectCompletedEvent(projectId: p1, name: My Project, units: 500, '
        'languages: 2, duration: 3h)',
      );
    });
  });

  group('ProjectExportedEvent', () {
    ProjectExportedEvent makeEvent() => ProjectExportedEvent(
          projectId: 'p1',
          languageId: 'fr',
          outputFilePath: 'out/pack.pack',
          exportedUnits: 250,
          format: 'pack',
        );

    test('constructs and exposes fields', () {
      final event = makeEvent();
      expect(event.projectId, 'p1');
      expect(event.languageId, 'fr');
      expect(event.outputFilePath, 'out/pack.pack');
      expect(event.exportedUnits, 250);
      expect(event.format, 'pack');
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes units, format and path', () {
      expect(
        makeEvent().toString(),
        'ProjectExportedEvent(projectId: p1, units: 250, format: pack, '
        'path: out/pack.pack)',
      );
    });
  });

  group('DomainEvent basics through ProjectEvent', () {
    test('unique eventIds across instances', () {
      final a = ProjectCreatedEvent(
        projectId: 'p1',
        projectName: 'n',
        gameInstallationId: 'gi',
        targetLanguageIds: const [],
      );
      final b = ProjectCreatedEvent(
        projectId: 'p1',
        projectName: 'n',
        gameInstallationId: 'gi',
        targetLanguageIds: const [],
      );
      expect(a.eventId, isNot(b.eventId));
    });
  });
}
