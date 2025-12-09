import 'detected_mod.dart';

/// Result of scanning mods from Workshop folder.
///
/// Includes the list of detected mods and metadata about changes applied.
class ModScanResult {
  /// List of detected mods from the scan.
  final List<DetectedMod> mods;

  /// True if any translation statistics changed during the scan.
  ///
  /// This happens when:
  /// - New translation units were added to existing projects
  /// - Source texts were updated and translations were reset to pending
  final bool translationStatsChanged;

  const ModScanResult({
    required this.mods,
    this.translationStatsChanged = false,
  });

  /// Creates an empty result.
  static const empty = ModScanResult(mods: []);
}

