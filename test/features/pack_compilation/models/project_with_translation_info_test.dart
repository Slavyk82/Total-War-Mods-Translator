import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/models/project_with_translation_info.dart';
import 'package:twmt/models/domain/project.dart';

void main() {
  Project project() => Project(
        id: 'p1',
        name: 'My Project',
        gameInstallationId: 'g1',
        createdAt: 1,
        updatedAt: 1,
      );

  test('exposes project identity fields', () {
    final info = ProjectWithTranslationInfo(project: project());
    expect(info.id, 'p1');
    expect(info.displayName, project().displayName);
    expect(info.imageUrl, project().imageUrl);
  });

  test('defaults unit counts to zero', () {
    final info = ProjectWithTranslationInfo(project: project());
    expect(info.totalUnits, 0);
    expect(info.translatedUnits, 0);
    expect(info.progressPercent, 0.0);
  });

  test('progressPercent is the translated/total ratio as a percentage', () {
    final info = ProjectWithTranslationInfo(
      project: project(),
      totalUnits: 200,
      translatedUnits: 50,
    );
    expect(info.progressPercent, 25.0);
  });

  test('progressPercent is 0 when there are no units', () {
    final info = ProjectWithTranslationInfo(
      project: project(),
      totalUnits: 0,
      translatedUnits: 5,
    );
    expect(info.progressPercent, 0.0);
  });
}
