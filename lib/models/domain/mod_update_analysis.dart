/// Data for a new translation unit to be added
class NewUnitData {
  final String key;
  final String sourceText;
  final String? sourceLocFile;

  const NewUnitData({
    required this.key,
    required this.sourceText,
    this.sourceLocFile,
  });
}

/// Analysis result comparing current pack file with existing project translations
class ModUpdateAnalysis {
  /// Number of new translation keys found in the updated pack
  final int newUnitsCount;

  /// Number of translation keys removed from the updated pack
  final int removedUnitsCount;

  /// Number of translation units with modified source text
  final int modifiedUnitsCount;

  /// Number of obsolete units that reappeared in the pack
  final int reactivatedUnitsCount;

  /// Total units in the current pack file
  final int totalPackUnits;

  /// Total active units in the existing project
  final int totalProjectUnits;

  /// Keys of new units to add (present in pack but not in project)
  final List<String> newUnitKeys;

  /// Complete data for new units (key, sourceText, sourceLocFile)
  final List<NewUnitData> newUnitsData;

  /// Keys of units removed from pack (present in project but not in pack)
  final List<String> removedUnitKeys;

  /// Keys of units with modified source text
  final List<String> modifiedUnitKeys;

  /// Map of modified keys to their new source text values
  final Map<String, String> modifiedSourceTexts;

  /// Keys of obsolete units that reappeared in the pack (need reactivation)
  final List<String> reactivatedUnitKeys;

  /// Map of reactivated keys to their new source text values
  final Map<String, String> reactivatedSourceTexts;

  const ModUpdateAnalysis({
    required this.newUnitsCount,
    required this.removedUnitsCount,
    required this.modifiedUnitsCount,
    this.reactivatedUnitsCount = 0,
    required this.totalPackUnits,
    required this.totalProjectUnits,
    this.newUnitKeys = const [],
    this.newUnitsData = const [],
    this.removedUnitKeys = const [],
    this.modifiedUnitKeys = const [],
    this.modifiedSourceTexts = const {},
    this.reactivatedUnitKeys = const [],
    this.reactivatedSourceTexts = const {},
  });

  /// Returns true if there are any changes detected (including auto-applied ones)
  bool get hasChanges =>
      newUnitsCount > 0 ||
      removedUnitsCount > 0 ||
      modifiedUnitsCount > 0 ||
      reactivatedUnitsCount > 0;

  /// Returns true if there are changes that require user attention.
  /// Excludes removed and reactivated units since those are handled automatically.
  bool get hasPendingChanges => newUnitsCount > 0 || modifiedUnitsCount > 0;

  /// Returns true if there are new units to translate
  bool get hasNewUnits => newUnitsCount > 0;

  /// Returns true if some units were removed
  bool get hasRemovedUnits => removedUnitsCount > 0;

  /// Returns true if some source texts were modified
  bool get hasModifiedUnits => modifiedUnitsCount > 0;

  /// Returns true if some obsolete units were reactivated
  bool get hasReactivatedUnits => reactivatedUnitsCount > 0;

  /// Returns a summary string of the changes for display in badges.
  /// Excludes removed and reactivated units since those are auto-applied.
  String get summary {
    if (!hasPendingChanges) {
      return 'No changes';
    }

    final parts = <String>[];
    if (newUnitsCount > 0) {
      parts.add('+$newUnitsCount new');
    }
    if (modifiedUnitsCount > 0) {
      parts.add('~$modifiedUnitsCount modified');
    }
    return parts.join(', ');
  }

  /// Returns a full summary string including all changes (for logs/debug).
  String get fullSummary {
    if (!hasChanges) {
      return 'No changes';
    }

    final parts = <String>[];
    if (newUnitsCount > 0) {
      parts.add('+$newUnitsCount new');
    }
    if (removedUnitsCount > 0) {
      parts.add('-$removedUnitsCount removed');
    }
    if (modifiedUnitsCount > 0) {
      parts.add('~$modifiedUnitsCount modified');
    }
    if (reactivatedUnitsCount > 0) {
      parts.add('↩$reactivatedUnitsCount reactivated');
    }
    return parts.join(', ');
  }

  /// Empty analysis (no changes)
  static const empty = ModUpdateAnalysis(
    newUnitsCount: 0,
    removedUnitsCount: 0,
    modifiedUnitsCount: 0,
    reactivatedUnitsCount: 0,
    totalPackUnits: 0,
    totalProjectUnits: 0,
    newUnitKeys: [],
    newUnitsData: [],
    removedUnitKeys: [],
    modifiedUnitKeys: [],
    modifiedSourceTexts: {},
    reactivatedUnitKeys: [],
    reactivatedSourceTexts: {},
  );

  @override
  String toString() =>
      'ModUpdateAnalysis(new: $newUnitsCount, removed: $removedUnitsCount, modified: $modifiedUnitsCount, reactivated: $reactivatedUnitsCount)';
}

