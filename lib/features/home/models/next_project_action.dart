import 'package:twmt/i18n/strings.g.dart';

enum NextProjectAction {
  toReview,
  translate,
  readyToCompile,
  continueWork;

  static NextProjectAction fromStats({
    required int translatedPct,
    required int needsReview,
    required bool packGenerated,
  }) {
    if (needsReview > 0) return NextProjectAction.toReview;
    if (translatedPct == 0) return NextProjectAction.translate;
    if (translatedPct >= 100 && !packGenerated) {
      return NextProjectAction.readyToCompile;
    }
    return NextProjectAction.continueWork;
  }

  String get label => switch (this) {
        NextProjectAction.toReview => t.home.nextAction.toReview,
        NextProjectAction.translate => t.home.nextAction.translate,
        NextProjectAction.readyToCompile => t.home.nextAction.readyToCompile,
        NextProjectAction.continueWork => t.home.nextAction.kContinue,
      };
}
