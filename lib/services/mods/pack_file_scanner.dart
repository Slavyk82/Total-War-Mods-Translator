import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:twmt/models/domain/mod_scan_cache.dart';
import 'package:twmt/repositories/mod_scan_cache_repository.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/utils/rpfm_output_parser.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/mods/utils/workshop_scan_models.dart';
import 'package:twmt/services/mods/utils/mod_image_finder.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';

/// Callback type for emitting scan log messages.
typedef ScanLogEmitter = void Function(String message, [ScanLogLevel level]);

/// Scans pack files in Workshop directories for localization content.
///
/// Handles the first phase of Workshop scanning:
/// - Collecting pack file information from mod directories
/// - Checking the scan cache to avoid redundant RPFM scans
/// - Scanning pack files for .loc files using RPFM
/// - Managing the scan cache for efficient future scans
class PackFileScanner {
  final ModScanCacheRepository _modScanCacheRepository;
  final IRpfmService _rpfmService;
  final LoggingService _logger = LoggingService.instance;
  final Uuid _uuid = const Uuid();

  PackFileScanner({
    required ModScanCacheRepository modScanCacheRepository,
    required IRpfmService rpfmService,
  })  : _modScanCacheRepository = modScanCacheRepository,
        _rpfmService = rpfmService;

  /// Collect local mod data from Workshop directories.
  ///
  /// Scans each mod directory for .pack files and checks if they contain
  /// localization files. Uses caching to avoid redundant RPFM scans.
  ///
  /// [modDirs] - List of Workshop mod directories to scan
  /// [emitLog] - Optional callback for emitting scan progress messages
  ///
  /// Returns a list of [ModLocalData] for mods containing localization files.
  Future<List<ModLocalData>> collectModData(
    List<Directory> modDirs, {
    ScanLogEmitter? emitLog,
  }) async {
    final rpfmAvailable = await _rpfmService.isRpfmAvailable();
    if (!rpfmAvailable) {
      _logger.warning('RPFM-CLI not available, cannot filter mods by loc files');
    }

    // First pass: collect all valid pack files
    final packFileInfos = await _collectPackFileInfos(modDirs);
    _logger.debug('Found ${packFileInfos.length} pack files to check');

    // Fetch cache entries for all pack files in batch
    final packFilePaths = packFileInfos.map((info) => info.packFile.path).toList();
    final cacheResult = await _modScanCacheRepository.getByPackFilePaths(packFilePaths);
    final cacheMap = cacheResult.isOk ? cacheResult.value : <String, ModScanCache>{};

    // Second pass: check cache and scan if necessary
    return _processPackFiles(
      packFileInfos,
      cacheMap,
      rpfmAvailable,
      emitLog: emitLog,
    );
  }

  /// Collect pack file information from mod directories.
  ///
  /// Iterates through Workshop directories and extracts metadata about
  /// .pack files found in each mod folder.
  Future<List<PackFileInfo>> _collectPackFileInfos(List<Directory> modDirs) async {
    final packFileInfos = <PackFileInfo>[];

    for (final modDir in modDirs) {
      final workshopId = path.basename(modDir.path);

      // Skip if not a valid Workshop ID (numeric)
      if (!_isValidWorkshopId(workshopId)) {
        continue;
      }

      // Look for .pack files in the mod directory
      final packFiles = await modDir
          .list()
          .where((entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.pack'))
          .cast<File>()
          .toList();

      if (packFiles.isEmpty) {
        _logger.debug('No .pack files found in $workshopId, skipping');
        continue;
      }

      // Use the first .pack file found
      final packFile = packFiles.first;
      final packFileName = path.basenameWithoutExtension(packFile.path);

      // Get file last modified time
      final fileStat = await packFile.stat();
      final fileLastModified = fileStat.modified.millisecondsSinceEpoch ~/ 1000;

      packFileInfos.add(PackFileInfo(
        workshopId: workshopId,
        modDir: modDir,
        packFile: packFile,
        packFileName: packFileName,
        fileLastModified: fileLastModified,
      ));
    }

    return packFileInfos;
  }

  /// Process pack files, checking cache and scanning for .loc files.
  ///
  /// For each pack file:
  /// 1. Check if valid cache entry exists
  /// 2. If cache miss or invalid, scan with RPFM
  /// 3. Update cache with scan results
  Future<List<ModLocalData>> _processPackFiles(
    List<PackFileInfo> packFileInfos,
    Map<String, ModScanCache> cacheMap,
    bool rpfmAvailable, {
    ScanLogEmitter? emitLog,
  }) async {
    final modDataList = <ModLocalData>[];
    final cacheUpdates = <ModScanCache>[];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    int cacheHits = 0, cacheMisses = 0, cacheSkipped = 0;
    int processed = 0;
    final total = packFileInfos.length;

    for (final info in packFileInfos) {
      processed++;
      final cacheEntry = cacheMap[info.packFile.path];
      bool hasLocFiles = false;

      // Check if we have a valid cache entry
      if (cacheEntry != null && cacheEntry.isValidFor(info.fileLastModified)) {
        hasLocFiles = cacheEntry.hasLocFiles;
        cacheHits++;

        if (!hasLocFiles) {
          cacheSkipped++;
          _logger.debug('Cache hit (no loc files): ${info.workshopId}');
          continue;
        }
      } else if (rpfmAvailable) {
        // Cache miss or invalidated - need to scan
        cacheMisses++;
        emitLog?.call('[$processed/$total] Scanning: ${info.packFileName}.pack');
        hasLocFiles = await _scanPackForLocFiles(info);

        // Update cache with scan result
        cacheUpdates.add(ModScanCache(
          id: cacheEntry?.id ?? _uuid.v4(),
          packFilePath: info.packFile.path,
          fileLastModified: info.fileLastModified,
          hasLocFiles: hasLocFiles,
          scannedAt: now,
        ));

        if (!hasLocFiles) {
          continue;
        }
      } else {
        // RPFM not available and no cache - skip
        continue;
      }

      // Find mod image
      final modImagePath = await ModImageFinder.findModImage(info.modDir, info.packFileName);

      modDataList.add(ModLocalData(
        workshopId: info.workshopId,
        packFile: info.packFile,
        packFileName: info.packFileName,
        modImagePath: modImagePath,
        hasLocFiles: hasLocFiles,
        fileLastModified: info.fileLastModified,
      ));
    }

    // Batch update cache entries
    if (cacheUpdates.isNotEmpty) {
      await _modScanCacheRepository.upsertBatch(cacheUpdates);
    }

    _logger.debug('Cache: hits=$cacheHits, misses=$cacheMisses, skipped=$cacheSkipped');
    if (cacheMisses > 0) {
      emitLog?.call('Cache: $cacheHits hits, $cacheMisses scans, $cacheSkipped skipped');
    }
    return modDataList;
  }

  /// Scan a pack file to check if it contains localization files.
  Future<bool> _scanPackForLocFiles(PackFileInfo info) async {
    final listResult = await _rpfmService.listPackContents(info.packFile.path);
    return listResult.when(
      ok: (files) {
        final locFiles = RpfmOutputParser.filterLocalizationFiles(files);
        final hasLocFiles = locFiles.isNotEmpty;
        if (!hasLocFiles) {
          _logger.debug(
              'No loc files in ${info.workshopId} (${info.packFileName}), skipping');
        }
        return hasLocFiles;
      },
      err: (error) {
        _logger.warning(
            'Failed to list pack contents for ${info.workshopId}: ${error.message}');
        return false;
      },
    );
  }

  /// Validate Workshop ID format (numeric only).
  bool _isValidWorkshopId(String workshopId) {
    return RegExp(r'^\d+$').hasMatch(workshopId);
  }
}
