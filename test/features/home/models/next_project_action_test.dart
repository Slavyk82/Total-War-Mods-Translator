import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/home/models/next_project_action.dart';

void main() {
  group('NextProjectAction.fromStats', () {
    test('returns toReview when needsReview > 0', () {
      final action = NextProjectAction.fromStats(
        translatedPct: 50,
        needsReview: 3,
        packGenerated: false,
      );
      expect(action, NextProjectAction.toReview);
    });

    test('returns translate when translatedPct is 0', () {
      final action = NextProjectAction.fromStats(
        translatedPct: 0,
        needsReview: 0,
        packGenerated: false,
      );
      expect(action, NextProjectAction.translate);
    });

    test('returns readyToCompile when 100% and pack not generated', () {
      final action = NextProjectAction.fromStats(
        translatedPct: 100,
        needsReview: 0,
        packGenerated: false,
      );
      expect(action, NextProjectAction.readyToCompile);
    });

    test('returns continueWork when 100% and pack already generated', () {
      final action = NextProjectAction.fromStats(
        translatedPct: 100,
        needsReview: 0,
        packGenerated: true,
      );
      expect(action, NextProjectAction.continueWork);
    });

    test('returns continueWork when progress is partial (50%)', () {
      final action = NextProjectAction.fromStats(
        translatedPct: 50,
        needsReview: 0,
        packGenerated: false,
      );
      expect(action, NextProjectAction.continueWork);
    });
  });
}
