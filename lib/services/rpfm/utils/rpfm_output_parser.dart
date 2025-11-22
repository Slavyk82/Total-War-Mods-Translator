/// Parser for RPFM-CLI output
///
/// Parses stdout/stderr from RPFM-CLI commands to extract useful information
class RpfmOutputParser {
  /// Parse file list from RPFM list output
  ///
  /// RPFM list output format:
  /// ```
  /// /path/to/file1.loc
  /// /path/to/file2.txt
  /// /path/to/folder/file3.dat
  /// ```
  static List<String> parseFileList(String output) {
    if (output.trim().isEmpty) return [];

    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();
  }

  /// Parse extraction progress from RPFM output
  ///
  /// Looks for progress indicators like "Extracting: 50/100"
  static double? parseProgress(String output) {
    final progressRegex = RegExp(r'(\d+)/(\d+)');
    final match = progressRegex.firstMatch(output);

    if (match != null) {
      final current = int.parse(match.group(1)!);
      final total = int.parse(match.group(2)!);
      if (total > 0) {
        return current / total;
      }
    }

    return null;
  }

  /// Extract error message from RPFM stderr
  ///
  /// Cleans up common RPFM error prefixes
  static String parseErrorMessage(String stderr) {
    if (stderr.trim().isEmpty) return 'Unknown error';

    // Remove common prefixes
    var message = stderr
        .replaceFirst(RegExp(r'^Error:\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^RPFM:\s*', caseSensitive: false), '')
        .trim();

    // Return first line if multi-line
    final lines = message.split('\n').where((l) => l.trim().isNotEmpty);
    return lines.isNotEmpty ? lines.first : 'Unknown error';
  }

  /// Check if output indicates success
  static bool isSuccess(String output, int exitCode) {
    if (exitCode != 0) return false;

    final lowerOutput = output.toLowerCase();

    // Check for success indicators
    if (lowerOutput.contains('success') ||
        lowerOutput.contains('complete') ||
        lowerOutput.contains('done')) {
      return true;
    }

    // Check for error indicators
    if (lowerOutput.contains('error') ||
        lowerOutput.contains('failed') ||
        lowerOutput.contains('exception')) {
      return false;
    }

    // If exit code is 0 and no errors, assume success
    return true;
  }

  /// Parse pack file metadata from RPFM info output
  static Map<String, dynamic>? parsePackInfo(String output) {
    final result = <String, dynamic>{};

    // Parse file count
    final fileCountMatch =
        RegExp(r'Files?:\s*(\d+)', caseSensitive: false).firstMatch(output);
    if (fileCountMatch != null) {
      result['fileCount'] = int.parse(fileCountMatch.group(1)!);
    }

    // Parse size
    final sizeMatch = RegExp(r'Size:\s*(\d+)\s*(?:bytes|B)?',
            caseSensitive: false)
        .firstMatch(output);
    if (sizeMatch != null) {
      result['sizeBytes'] = int.parse(sizeMatch.group(1)!);
    }

    // Parse version
    final versionMatch =
        RegExp(r'Version:\s*(\d+)', caseSensitive: false).firstMatch(output);
    if (versionMatch != null) {
      result['formatVersion'] = int.parse(versionMatch.group(1)!);
    }

    return result.isNotEmpty ? result : null;
  }

  /// Count localization files in file list
  static int countLocalizationFiles(List<String> files) {
    return files.where((f) => f.toLowerCase().endsWith('.loc')).length;
  }

  /// Filter localization files from file list
  static List<String> filterLocalizationFiles(List<String> files) {
    return files
        .where((f) => f.toLowerCase().endsWith('.loc'))
        .toList();
  }

  /// Normalize file path separators to forward slashes
  static String normalizePath(String path) {
    return path.replaceAll(r'\', '/');
  }

  /// Parse version string from RPFM --version output
  ///
  /// Expected format: "rpfm_cli 4.0.0" or similar
  static String? parseVersion(String output) {
    final versionMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(output);
    return versionMatch?.group(1);
  }

  /// Check if operation was cancelled
  static bool isCancelled(String output, int exitCode) {
    if (exitCode == 130) return true; // SIGINT

    final lowerOutput = output.toLowerCase();
    return lowerOutput.contains('cancel') ||
        lowerOutput.contains('abort') ||
        lowerOutput.contains('interrupt');
  }

  /// Estimate timeout in seconds based on file size
  ///
  /// Rule: 1 minute per 100MB, minimum 30 seconds
  static int calculateTimeout(int sizeBytes) {
    const baseSec = 30;
    const secPer100MB = 60;

    final sizeMB = sizeBytes / (1024 * 1024);
    final timeoutSec = baseSec + (sizeMB / 100 * secPer100MB).ceil();

    return timeoutSec;
  }
}
