/// Analysis result comparing current pack file with existing project translations
class ModUpdateAnalysis {
  /// Number of new translation keys found in the updated pack
  final int newUnitsCount;

  /// Number of translation keys removed from the updated pack
  final int removedUnitsCount;

  /// Number of translation units with modified source text
  final int modifiedUnitsCount;

  /// Total units in the current pack file
  final int totalPackUnits;

  /// Total active units in the existing project
  final int totalProjectUnits;

  const ModUpdateAnalysis({
    required this.newUnitsCount,
    required this.removedUnitsCount,
    required this.modifiedUnitsCount,
    required this.totalPackUnits,
    required this.totalProjectUnits,
  });

  /// Returns true if there are any changes detected
  bool get hasChanges =>
      newUnitsCount > 0 || removedUnitsCount > 0 || modifiedUnitsCount > 0;

  /// Returns true if there are new units to translate
  bool get hasNewUnits => newUnitsCount > 0;

  /// Returns true if some units were removed
  bool get hasRemovedUnits => removedUnitsCount > 0;

  /// Returns true if some source texts were modified
  bool get hasModifiedUnits => modifiedUnitsCount > 0;

  /// Returns a summary string of the changes
  String get summary {
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
    return parts.join(', ');
  }

  /// Empty analysis (no changes)
  static const empty = ModUpdateAnalysis(
    newUnitsCount: 0,
    removedUnitsCount: 0,
    modifiedUnitsCount: 0,
    totalPackUnits: 0,
    totalProjectUnits: 0,
  );

  @override
  String toString() =>
      'ModUpdateAnalysis(new: $newUnitsCount, removed: $removedUnitsCount, modified: $modifiedUnitsCount)';
}

