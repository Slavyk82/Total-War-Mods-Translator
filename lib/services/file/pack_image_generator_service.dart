import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/i_pack_image_generator_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Service for generating pack images with language flag overlays
///
/// Creates Steam Workshop preview images for translation packs by overlaying
/// the target language's flag on the original mod image.
class PackImageGeneratorService implements IPackImageGeneratorService {
  final LoggingService _logger;

  /// Flag size as percentage of image width (30% = 0.3)
  static const double _flagSizeRatio = 0.30;

  /// Margin from edge in pixels
  static const int _flagMargin = 10;

  PackImageGeneratorService({LoggingService? logger})
      : _logger = logger ?? LoggingService.instance;

  @override
  Future<Result<String?, FileServiceException>> ensurePackImage({
    required String packFileName,
    required String gameDataPath,
    required String languageCode,
    String? modImageUrl,
    String? localModImagePath,
    required bool generateImage,
    bool useAppIcon = false,
  }) async {
    // Skip if generation is disabled
    if (!generateImage) {
      return const Ok(null);
    }

    try {
      // Calculate output image path
      final imageFileName = _buildImageFileName(packFileName);
      final imagePath = path.join(gameDataPath, imageFileName);

      // Check if image already exists
      if (await File(imagePath).exists()) {
        _logger.info('Pack image already exists, skipping generation', {
          'path': imagePath,
        });
        return Ok(imagePath);
      }

      // Load source image (app icon or mod image)
      img.Image? sourceImageResult;
      if (useAppIcon) {
        sourceImageResult = await _loadAppIcon();
      } else {
        sourceImageResult = await _loadSourceImage(
          modImageUrl: modImageUrl,
          localModImagePath: localModImagePath,
        );
        // Fallback to app icon if mod image is not available
        if (sourceImageResult == null) {
          _logger.info('Mod image not available, falling back to app icon');
          sourceImageResult = await _loadAppIcon();
        }
      }

      if (sourceImageResult == null) {
        _logger.warning('No source image available for pack image generation');
        return const Ok(null);
      }

      // Load language flag
      final flagResult = await _loadFlag(languageCode);
      if (flagResult == null) {
        _logger.warning('Flag not found for language: $languageCode');
        return const Ok(null);
      }

      // Generate composite image
      final compositeImage = _overlayFlag(sourceImageResult, flagResult);

      // Save the result
      await _saveImage(compositeImage, imagePath);

      _logger.info('Pack image generated successfully', {
        'path': imagePath,
        'languageCode': languageCode,
      });

      return Ok(imagePath);
    } catch (e, stackTrace) {
      _logger.error('Failed to generate pack image', e, stackTrace);
      // Don't fail the export, just log the error
      return const Ok(null);
    }
  }

  /// Build image filename from pack filename
  ///
  /// Replaces .pack extension with .png
  String _buildImageFileName(String packFileName) {
    if (packFileName.toLowerCase().endsWith('.pack')) {
      return '${packFileName.substring(0, packFileName.length - 5)}.png';
    }
    return '$packFileName.png';
  }

  /// Load source mod image from URL or local path
  Future<img.Image?> _loadSourceImage({
    String? modImageUrl,
    String? localModImagePath,
  }) async {
    // Try modImageUrl (could be HTTP URL or local path)
    if (modImageUrl != null && modImageUrl.isNotEmpty) {
      // Check if it's a local file path (Windows drive letter or UNC path)
      if (_isLocalPath(modImageUrl)) {
        final localImage = await _loadImageFromFile(modImageUrl);
        if (localImage != null) return localImage;
      } else {
        // It's an HTTP/HTTPS URL
        try {
          final response = await http.get(Uri.parse(modImageUrl));
          if (response.statusCode == 200) {
            final image = img.decodeImage(response.bodyBytes);
            if (image != null) {
              return image;
            }
          }
        } catch (e) {
          _logger.warning('Failed to download mod image from URL', {
            'url': modImageUrl,
            'error': e.toString(),
          });
        }
      }
    }

    // Try explicit local path
    if (localModImagePath != null && localModImagePath.isNotEmpty) {
      final localImage = await _loadImageFromFile(localModImagePath);
      if (localImage != null) return localImage;
    }

    return null;
  }

  /// Check if a path is a local file path (not a URL)
  bool _isLocalPath(String path) {
    // Windows drive letter (e.g., C:\, D:\)
    if (path.length >= 2 && path[1] == ':') return true;
    // UNC path (e.g., \\server\share)
    if (path.startsWith(r'\\')) return true;
    // Unix absolute path
    if (path.startsWith('/') && !path.startsWith('//')) return true;
    return false;
  }

  /// Load image from local file
  Future<img.Image?> _loadImageFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final image = img.decodeImage(bytes);
        if (image != null) {
          return image;
        }
      } else {
        _logger.warning('Local image file does not exist', {'path': filePath});
      }
    } catch (e) {
      _logger.warning('Failed to load mod image from local path', {
        'path': filePath,
        'error': e.toString(),
      });
    }
    return null;
  }

  /// Load TWMT app icon from assets
  Future<img.Image?> _loadAppIcon() async {
    try {
      const assetPath = 'assets/twmt_icon.png';
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      return img.decodePng(bytes);
    } catch (e) {
      _logger.warning('Failed to load app icon asset', {
        'error': e.toString(),
      });
      return null;
    }
  }

  /// Load language flag from assets
  Future<img.Image?> _loadFlag(String languageCode) async {
    try {
      final assetPath = 'assets/flags/${languageCode.toLowerCase()}.png';
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      return img.decodePng(bytes);
    } catch (e) {
      _logger.warning('Failed to load flag asset', {
        'languageCode': languageCode,
        'error': e.toString(),
      });
      return null;
    }
  }

  /// Overlay flag on source image
  ///
  /// Places the flag in the top-right corner with specified margin.
  /// Flag is resized to 30% of the source image width.
  /// Creates a new RGBA image to ensure color support regardless of source format.
  img.Image _overlayFlag(img.Image source, img.Image flag) {
    // Calculate flag size (30% of source width)
    final targetFlagWidth = (source.width * _flagSizeRatio).round();
    final aspectRatio = flag.height / flag.width;
    final targetFlagHeight = (targetFlagWidth * aspectRatio).round();

    // Resize flag
    final resizedFlag = img.copyResize(
      flag,
      width: targetFlagWidth,
      height: targetFlagHeight,
      interpolation: img.Interpolation.linear,
    );

    // Calculate position (top-right corner with margin)
    final x = source.width - resizedFlag.width - _flagMargin;
    final y = _flagMargin;

    // Create new RGBA image to ensure full color support
    // (some source images may have limited color formats like indexed palette)
    final result = img.Image(
      width: source.width,
      height: source.height,
      numChannels: 4,
    );

    // Copy source pixels to result
    for (var sy = 0; sy < source.height; sy++) {
      for (var sx = 0; sx < source.width; sx++) {
        final pixel = source.getPixel(sx, sy);
        result.setPixelRgba(
          sx,
          sy,
          pixel.r.toInt(),
          pixel.g.toInt(),
          pixel.b.toInt(),
          pixel.a.toInt(),
        );
      }
    }

    // Draw flag onto result with alpha blending
    for (var fy = 0; fy < resizedFlag.height; fy++) {
      for (var fx = 0; fx < resizedFlag.width; fx++) {
        final destX = x + fx;
        final destY = y + fy;

        // Skip if outside bounds
        if (destX < 0 ||
            destX >= result.width ||
            destY < 0 ||
            destY >= result.height) {
          continue;
        }

        final flagPixel = resizedFlag.getPixel(fx, fy);
        final flagAlpha = flagPixel.a.toDouble() / 255.0;

        // Skip fully transparent pixels
        if (flagAlpha == 0) continue;

        final flagR = flagPixel.r.toInt();
        final flagG = flagPixel.g.toInt();
        final flagB = flagPixel.b.toInt();

        if (flagAlpha >= 1.0) {
          // Fully opaque - copy the pixel directly
          result.setPixelRgba(destX, destY, flagR, flagG, flagB, 255);
        } else {
          // Alpha blend with existing pixel
          final srcPixel = result.getPixel(destX, destY);
          final srcR = srcPixel.r.toInt();
          final srcG = srcPixel.g.toInt();
          final srcB = srcPixel.b.toInt();
          final r = (flagR * flagAlpha + srcR * (1 - flagAlpha)).round();
          final g = (flagG * flagAlpha + srcG * (1 - flagAlpha)).round();
          final b = (flagB * flagAlpha + srcB * (1 - flagAlpha)).round();
          result.setPixelRgba(destX, destY, r, g, b, 255);
        }
      }
    }

    return result;
  }

  /// Save image to file
  Future<void> _saveImage(img.Image image, String outputPath) async {
    final bytes = img.encodePng(image);
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }
}
