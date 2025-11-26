import 'dart:io';
import 'package:path/path.dart' as path;

/// Utility class for finding mod preview images in Workshop directories.
///
/// Searches for images in a specific priority order:
/// 1. Image with same name as pack file (e.g., my_mod.jpg for my_mod.pack)
/// 2. preview.* files
/// 3. Any image file in the directory
class ModImageFinder {
  /// Supported image file extensions.
  static const List<String> imageExtensions = ['.jpg', '.jpeg', '.png'];

  /// Find mod preview image in the mod directory.
  ///
  /// [modDir] - The mod's Workshop directory
  /// [packFileName] - Base name of the pack file (without extension)
  ///
  /// Returns the path to the found image, or null if no image found.
  static Future<String?> findModImage(
    Directory modDir,
    String packFileName,
  ) async {
    // 1. First, check for image with same name as .pack file
    for (final ext in imageExtensions) {
      final imagePath = path.join(modDir.path, '$packFileName$ext');
      if (await File(imagePath).exists()) {
        return imagePath;
      }
    }

    // 2. If not found, try preview.*
    for (final ext in imageExtensions) {
      final imagePath = path.join(modDir.path, 'preview$ext');
      if (await File(imagePath).exists()) {
        return imagePath;
      }
    }

    // 3. If still not found, try to find any image file
    final imageFiles = await modDir
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where(
            (file) => imageExtensions.any((ext) => file.path.toLowerCase().endsWith(ext)))
        .toList();

    if (imageFiles.isNotEmpty) {
      return imageFiles.first.path;
    }

    return null;
  }
}
