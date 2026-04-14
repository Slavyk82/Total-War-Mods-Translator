import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';

/// Combined view of translation unit and its version for display in DataGrid
class TranslationRow {
  final TranslationUnit unit;
  final TranslationVersion version;

  const TranslationRow({
    required this.unit,
    required this.version,
  });

  String get id => unit.id;
  String get key => unit.key;
  String get sourceText => unit.sourceText;
  String? get translatedText => version.translatedText;
  TranslationVersionStatus get status => version.status;
  TranslationSource get translationSource => version.translationSource;
  bool get isManuallyEdited => version.isManuallyEdited;
  bool get hasValidationIssues => version.hasValidationIssues;
  String? get sourceLocFile => unit.sourceLocFile;

  TranslationRow copyWith({
    TranslationUnit? unit,
    TranslationVersion? version,
  }) {
    return TranslationRow(
      unit: unit ?? this.unit,
      version: version ?? this.version,
    );
  }
}

/// Type of TM source for filtering
enum TmSourceType {
  exactMatch,
  fuzzyMatch,
  llm,
  manual,
  none,
}

/// Statistics for the current translation session
class EditorStats {
  final int totalUnits;
  final int pendingCount;
  final int translatedCount;
  final int needsReviewCount;
  final double completionPercentage;

  const EditorStats({
    required this.totalUnits,
    required this.pendingCount,
    required this.translatedCount,
    required this.needsReviewCount,
    required this.completionPercentage,
  });

  static EditorStats empty() {
    return const EditorStats(
      totalUnits: 0,
      pendingCount: 0,
      translatedCount: 0,
      needsReviewCount: 0,
      completionPercentage: 0.0,
    );
  }
}

/// Get the TM source type from a translation row based on translation source field
TmSourceType getTmSourceType(TranslationRow row) {
  if (row.isManuallyEdited) return TmSourceType.manual;

  // Use explicit translation source field
  switch (row.translationSource) {
    case TranslationSource.tmExact:
      return TmSourceType.exactMatch;
    case TranslationSource.tmFuzzy:
      return TmSourceType.fuzzyMatch;
    case TranslationSource.llm:
      return TmSourceType.llm;
    case TranslationSource.manual:
      return TmSourceType.manual;
    case TranslationSource.unknown:
      return TmSourceType.none;
  }
}

/// Parse status string to enum
TranslationVersionStatus parseStatus(String status) {
  switch (status) {
    case 'pending':
      return TranslationVersionStatus.pending;
    case 'translated':
      return TranslationVersionStatus.translated;
    case 'needs_review':
    case 'needsReview':
      return TranslationVersionStatus.needsReview;
    default:
      return TranslationVersionStatus.pending;
  }
}

/// Parse translation source string to enum
TranslationSource parseTranslationSource(String? source) {
  if (source == null) return TranslationSource.unknown;
  switch (source) {
    case 'manual':
      return TranslationSource.manual;
    case 'tm_exact':
      return TranslationSource.tmExact;
    case 'tm_fuzzy':
      return TranslationSource.tmFuzzy;
    case 'llm':
      return TranslationSource.llm;
    default:
      return TranslationSource.unknown;
  }
}
