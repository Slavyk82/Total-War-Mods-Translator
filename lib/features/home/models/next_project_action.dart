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
        NextProjectAction.toReview => 'To review',
        NextProjectAction.translate => 'Translate',
        NextProjectAction.readyToCompile => 'Ready to compile',
        NextProjectAction.continueWork => 'Continue',
      };
}
