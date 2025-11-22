import 'domain_event.dart';

/// Event emitted when a translation is added to Translation Memory
class TranslationAddedToTmEvent extends DomainEvent {
  final String versionId;
  final String unitId;
  final String tmId;
  final String sourceText;
  final String translatedText;
  final String targetLanguageId;
  final String gameContext;
  final double? qualityScore;

  TranslationAddedToTmEvent({
    required this.versionId,
    required this.unitId,
    required this.tmId,
    required this.sourceText,
    required this.translatedText,
    required this.targetLanguageId,
    required this.gameContext,
    this.qualityScore,
  }) : super.now();
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'TranslationAddedToTmEvent(versionId: $versionId, tmId: $tmId, '
      'context: $gameContext, quality: ${qualityScore?.toStringAsFixed(2) ?? "N/A"})';
}

/// Event emitted when a new translation memory entry is added
class TmEntryAddedEvent extends DomainEvent {
  final String tmId;
  final String sourceHash;
  final String targetLanguageId;
  final String gameContext;
  final double? qualityScore;

  TmEntryAddedEvent({
    required this.tmId,
    required this.sourceHash,
    required this.targetLanguageId,
    required this.gameContext,
    this.qualityScore,
  }) : super.now();
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'TmEntryAddedEvent(tmId: $tmId, context: $gameContext, '
      'quality: ${qualityScore?.toStringAsFixed(2) ?? "N/A"})';
}

/// Event emitted when a TM match is found and used
class TmMatchFoundEvent extends DomainEvent {
  final String tmId;
  final String versionId;
  final String unitId;
  final double matchConfidence;
  final bool isExactMatch;
  final String sourceText;

  TmMatchFoundEvent({
    required this.tmId,
    required this.versionId,
    required this.unitId,
    required this.matchConfidence,
    required this.sourceText,
  })  : isExactMatch = matchConfidence >= 0.99,
        super.now();

  bool get isFuzzyMatch => !isExactMatch;
  String get matchType => isExactMatch ? 'exact' : 'fuzzy';
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'TmMatchFoundEvent(tmId: $tmId, versionId: $versionId, '
      'match: $matchType (${(matchConfidence * 100).toStringAsFixed(1)}%))';
}

/// Event emitted when a TM entry is updated (quality, usage count)
class TmEntryUpdatedEvent extends DomainEvent {
  final String tmId;
  final int newUsageCount;
  final double? newQualityScore;
  final String updateReason;

  TmEntryUpdatedEvent({
    required this.tmId,
    required this.newUsageCount,
    this.newQualityScore,
    required this.updateReason,
  }) : super.now();
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'TmEntryUpdatedEvent(tmId: $tmId, usage: $newUsageCount, '
      'quality: ${newQualityScore?.toStringAsFixed(2) ?? "N/A"}, '
      'reason: $updateReason)';
}

/// Event emitted when TM provides suggestions for a translation unit
class TmSuggestionsProvidedEvent extends DomainEvent {
  final String unitId;
  final String sourceText;
  final List<TmSuggestion> suggestions;

  TmSuggestionsProvidedEvent({
    required this.unitId,
    required this.sourceText,
    required this.suggestions,
  }) : super.now();

  int get suggestionCount => suggestions.length;
  bool get hasExactMatch => suggestions.any((s) => s.isExactMatch);
  TmSuggestion? get bestMatch => suggestions.isEmpty ? null : suggestions.first;
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'TmSuggestionsProvidedEvent(unitId: $unitId, suggestions: $suggestionCount, '
      'hasExact: $hasExactMatch)';
}

/// Data class for TM suggestions
class TmSuggestion {
  final String tmId;
  final String translatedText;
  final double matchConfidence;
  final double? qualityScore;
  final int usageCount;

  const TmSuggestion({
    required this.tmId,
    required this.translatedText,
    required this.matchConfidence,
    this.qualityScore,
    required this.usageCount,
  });

  bool get isExactMatch => matchConfidence >= 0.99;
  bool get isHighQuality => qualityScore != null && qualityScore! >= 0.8;
  bool get isFrequentlyUsed => usageCount >= 5;
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'TmSuggestion(match: ${(matchConfidence * 100).toStringAsFixed(1)}%, '
      'quality: ${qualityScore?.toStringAsFixed(2) ?? "N/A"}, '
      'usage: $usageCount)';
}

/// Event emitted when TM cache is rebuilt
class TmCacheRebuiltEvent extends DomainEvent {
  final int totalEntries;
  final int gameContextsCount;
  final Duration rebuildDuration;

  TmCacheRebuiltEvent({
    required this.totalEntries,
    required this.gameContextsCount,
    required this.rebuildDuration,
  }) : super.now();
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'TmCacheRebuiltEvent(entries: $totalEntries, contexts: $gameContextsCount, '
      'duration: ${rebuildDuration.inMilliseconds}ms)';
}
