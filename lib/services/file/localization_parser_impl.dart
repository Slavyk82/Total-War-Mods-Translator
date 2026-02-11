import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/i_localization_parser.dart';
import 'package:twmt/services/file/models/localization_entry.dart';
import 'package:twmt/services/file/models/localization_file.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/parsers/encoding_detector.dart';
import 'package:twmt/services/file/parsers/binary_loc_parser.dart';
import 'package:twmt/services/file/parsers/tsv_parser.dart';

/// Implementation of .loc localization file parser
///
/// Coordinates between different parsing strategies:
/// - Binary LOC format (Total War .loc files)
/// - TSV format (text-based localization files)
///
/// Uses Strategy Pattern to delegate parsing to specialized parsers.
class LocalizationParserImpl implements ILocalizationParser {
  /// Singleton instance
  static final LocalizationParserImpl _instance =
      LocalizationParserImpl._internal();

  factory LocalizationParserImpl() => _instance;

  LocalizationParserImpl._internal();

  final _encodingDetector = EncodingDetector();
  final _binaryLocParser = BinaryLocParser();
  final _tsvParser = TsvParser();

  @override
  Future<Result<LocalizationFile, FileServiceException>> parseFile({
    required String filePath,
    String encoding = 'utf-8',
    String? languageCode,
  }) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        return Err(
          FileNotFoundException(
            'Localization file not found: $filePath',
            filePath,
          ),
        );
      }

      final fileName = file.uri.pathSegments.last;

      // Extract language code if not provided
      final lang = languageCode ?? extractLanguageCode(fileName) ?? 'en';

      // Read file as bytes
      final bytes = await file.readAsBytes();

      // Detect if binary LOC format (check for LOC header or UTF-16 LE BOM)
      final isBinaryLoc = _isBinaryLocFormat(bytes);

      List<LocalizationEntry> entries;

      if (isBinaryLoc) {
        // Use binary parser
        final parseResult = await _binaryLocParser.parseFile(
          filePath: filePath,
          bytes: bytes,
        );

        if (parseResult.isErr) {
          return Err(parseResult.error);
        }

        entries = parseResult.value;
      } else {
        // Use TSV parser - decode as UTF-8 for proper Unicode support
        final content = utf8.decode(bytes, allowMalformed: true);
        final parseResult = _tsvParser.parseString(
          content: content,
          fileName: fileName,
        );

        if (parseResult == null) {
          return Err(
            FileParsingException(
              'Failed to parse TSV content',
              fileName,
              lineNumber: 0,
            ),
          );
        }

        entries = parseResult.entries;
      }

      final locFile = LocalizationFile(
        fileName: fileName,
        filePath: filePath,
        languageCode: lang,
        entries: entries,
        encoding: encoding,
        comments: [],
      );

      return Ok(locFile);
    } on FileSystemException catch (e) {
      return Err(
        FileAccessDeniedException(
          'Cannot access localization file: ${e.message}',
          filePath,
          'read',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error parsing file: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<LocalizationFile, FileParsingException>> parseString({
    required String content,
    required String fileName,
    required String languageCode,
  }) async {
    try {
      // Parse as TSV
      final parseResult = _tsvParser.parseString(
        content: content,
        fileName: fileName,
      );

      if (parseResult == null) {
        return Err(
          FileParsingException(
            'Failed to parse TSV content',
            fileName,
            lineNumber: 0,
          ),
        );
      }

      final locFile = LocalizationFile(
        fileName: fileName,
        filePath: '', // Will be set when writing to disk
        languageCode: languageCode,
        entries: parseResult.entries,
        encoding: 'utf-8',
        comments: parseResult.comments,
      );

      return Ok(locFile);
    } catch (e, stackTrace) {
      return Err(
        FileParsingException(
          'Failed to parse localization content: ${e.toString()}',
          fileName,
          lineNumber: 0,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Stream<Result<LocalizationEntry, FileParsingException>> parseFileStream({
    required String filePath,
    String encoding = 'utf-8',
    String? languageCode,
  }) {
    return _tsvParser.parseFileStream(
      filePath: filePath,
      encoding: encoding,
    );
  }

  @override
  Future<Result<String, FileServiceException>> generateFileContent({
    required LocalizationFile file,
    bool includeComments = true,
    bool applyPrefix = true,
  }) async {
    try {
      final content = _tsvParser.generateContent(
        entries: file.entries,
        comments: file.comments,
        includeComments: includeComments,
      );

      return Ok(content);
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Failed to generate file content: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<String, FileServiceException>> writeFile({
    required LocalizationFile file,
    required String destinationPath,
    String encoding = 'utf-8',
    bool applyPrefix = true,
  }) async {
    try {
      // Generate content
      final contentResult = await generateFileContent(
        file: file,
        applyPrefix: applyPrefix,
      );

      if (contentResult.isErr) {
        return Err(contentResult.error);
      }

      // Write to file
      final outputFile = File(destinationPath);
      await outputFile.writeAsString(
        contentResult.value,
        encoding: _encodingDetector.getEncoding(encoding),
      );

      return Ok(destinationPath);
    } on FileSystemException catch (e) {
      return Err(
        FileAccessDeniedException(
          'Cannot write localization file: ${e.message}',
          destinationPath,
          'write',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error writing file: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<FileValidationResult, FileServiceException>> validateFile({
    required String filePath,
  }) async {
    try {
      // 1. Check file exists
      final file = File(filePath);
      if (!await file.exists()) {
        return Err(
          FileNotFoundException(
            'File not found: $filePath',
            filePath,
          ),
        );
      }

      // 2. Detect encoding
      final encodingResult = await detectEncoding(filePath: filePath);
      if (encodingResult.isErr) {
        return Ok(FileValidationResult(
          isValid: false,
          errors: ['Failed to detect encoding: ${encodingResult.error.message}'],
          warnings: [],
        ));
      }

      final detectedEncoding = encodingResult.value;

      // 3. Validate TSV structure
      final validationResult = await _tsvParser.validateFile(
        filePath: filePath,
        detectedEncoding: detectedEncoding,
      );

      if (validationResult == null) {
        return Err(
          FileServiceException(
            'Failed to validate TSV file',
          ),
        );
      }

      return Ok(FileValidationResult(
        isValid: validationResult.isValid,
        errors: validationResult.errors,
        warnings: validationResult.warnings,
      ));
    } on FileSystemException catch (e) {
      return Err(
        FileAccessDeniedException(
          'Cannot access file for validation: ${e.message}',
          filePath,
          'read',
          error: e,
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Unexpected error during file validation: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<String, FileEncodingException>> detectEncoding({
    required String filePath,
  }) {
    return _encodingDetector.detectEncoding(filePath: filePath);
  }

  @override
  String? extractLanguageCode(String fileName) {
    // Total War uses prefix format: !!!!!!!!!!_FR_units.loc
    final pattern = RegExp(r'!+_([A-Z]{2})_');
    final match = pattern.firstMatch(fileName);

    if (match != null && match.groupCount >= 1) {
      return match.group(1)!.toLowerCase();
    }

    return null;
  }

  @override
  String generatePrefixedFileName(String baseName, String languageCode) {
    // Total War format: !!!!!!!!!!_FR_filename.loc
    final prefix = '!!!!!!!!!!_${languageCode.toUpperCase()}_';
    return '$prefix$baseName';
  }

  @override
  Future<Result<LocalizationFile, FileServiceException>> mergeFiles({
    required List<LocalizationFile> files,
    String conflictResolution = 'last',
  }) async {
    try {
      if (files.isEmpty) {
        return Err(
          const FileServiceException(
            'Cannot merge empty list of files',
          ),
        );
      }

      if (files.length == 1) {
        return Ok(files.first);
      }

      // Use first file as base for metadata
      final firstFile = files.first;
      final mergedEntries = <String, LocalizationEntry>{};
      final allComments = <String>[];
      final duplicateKeys = <String>[];

      // Process each file in order
      for (final file in files) {
        // Collect comments from all files
        allComments.addAll(file.comments);

        // Process entries
        for (final entry in file.entries) {
          final key = entry.key;

          // Check for duplicates
          if (mergedEntries.containsKey(key)) {
            duplicateKeys.add(key);

            // Handle conflict based on resolution strategy
            switch (conflictResolution.toLowerCase()) {
              case 'first':
                // Keep existing entry (from earlier file)
                continue;
              case 'last':
                // Replace with new entry (from later file)
                mergedEntries[key] = entry;
                break;
              case 'error':
                return Err(
                  FileServiceException(
                    'Duplicate key found during merge: "$key"',
                  ),
                );
              default:
                return Err(
                  FileServiceException(
                    'Invalid conflict resolution strategy: $conflictResolution',
                  ),
                );
            }
          } else {
            mergedEntries[key] = entry;
          }
        }
      }

      // Create merged file
      final mergedFile = LocalizationFile(
        fileName: firstFile.fileName,
        filePath: '', // Will be set when writing to disk
        languageCode: firstFile.languageCode,
        encoding: firstFile.encoding,
        entries: mergedEntries.values.toList(),
        comments: allComments,
      );

      return Ok(mergedFile);
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Failed to merge files: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<List<LocalizationFile>, FileServiceException>> splitFile({
    required LocalizationFile file,
    int maxEntriesPerFile = 10000,
  }) async {
    try {
      if (maxEntriesPerFile <= 0) {
        return Err(
          const FileServiceException(
            'maxEntriesPerFile must be greater than 0',
          ),
        );
      }

      // If file is already small enough, return it as-is
      if (file.entries.length <= maxEntriesPerFile) {
        return Ok([file]);
      }

      final splitFiles = <LocalizationFile>[];
      final totalEntries = file.entries.length;
      final chunkCount = (totalEntries / maxEntriesPerFile).ceil();

      // Calculate how many comments per chunk (distribute evenly)
      final commentsPerChunk = file.comments.isNotEmpty
          ? (file.comments.length / chunkCount).ceil()
          : 0;

      for (var i = 0; i < chunkCount; i++) {
        final startIndex = i * maxEntriesPerFile;
        final endIndex = ((i + 1) * maxEntriesPerFile).clamp(0, totalEntries);

        // Get entries for this chunk
        final chunkEntries = file.entries.sublist(startIndex, endIndex);

        // Get comments for this chunk (distribute evenly)
        final commentStartIndex = i * commentsPerChunk;
        final commentEndIndex =
            ((i + 1) * commentsPerChunk).clamp(0, file.comments.length);
        final chunkComments = file.comments.isNotEmpty
            ? file.comments.sublist(commentStartIndex, commentEndIndex)
            : <String>[];

        // Generate unique filename for chunk
        final baseName = file.fileName.replaceAll('.loc', '');
        final chunkFileName = '${baseName}_part${i + 1}.loc';

        // Create chunk file
        final chunkFile = LocalizationFile(
          fileName: chunkFileName,
          filePath: '', // Will be set when writing to disk
          languageCode: file.languageCode,
          encoding: file.encoding,
          entries: chunkEntries,
          comments: chunkComments,
        );

        splitFiles.add(chunkFile);
      }

      return Ok(splitFiles);
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Failed to split file: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Detect if file is in binary LOC format
  ///
  /// Binary LOC files have either:
  /// - UTF-16 LE BOM (FF FE)
  /// - LOC header starting with "LOC"
  bool _isBinaryLocFormat(List<int> bytes) {
    if (bytes.length < 4) return false;

    // Check for UTF-16 LE BOM
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return true;
    }

    // Check for LOC header
    final header = String.fromCharCodes(bytes.sublist(0, 3));
    if (header == 'LOC') {
      return true;
    }

    return false;
  }
}
