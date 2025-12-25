import 'package:dio/dio.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/settings/settings_service.dart';

/// Service responsible for DeepL integration
///
/// Handles DeepL glossary API operations including creation, deletion,
/// and listing of glossaries on DeepL's platform.
class GlossaryDeepLService {
  final GlossaryRepository _glossaryRepository;
  final SettingsService _settingsService;
  final Dio _dio;

  /// DeepL API base URL for PRO accounts
  static const String _apiBaseUrlPro = 'https://api.deepl.com/v2';

  /// DeepL API base URL for FREE accounts
  static const String _apiBaseUrlFree = 'https://api-free.deepl.com/v2';

  /// API key setting key for DeepL
  static const String _apiKeySettingKey = 'deepl_api_key';

  GlossaryDeepLService({
    required GlossaryRepository glossaryRepository,
    required SettingsService settingsService,
    Dio? dio,
  })  : _glossaryRepository = glossaryRepository,
        _settingsService = settingsService,
        _dio = dio ??
            Dio(BaseOptions(
              // Default to FREE, will be updated dynamically based on API key
              baseUrl: _apiBaseUrlFree,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 120),
              headers: {
                'Content-Type': 'application/json',
              },
            ));

  /// Determine the correct API base URL based on the API key type.
  /// FREE API keys end with ':fx'
  static String _getBaseUrl(String apiKey) {
    if (apiKey.endsWith(':fx')) {
      return _apiBaseUrlFree;
    }
    return _apiBaseUrlPro;
  }

  /// Update the base URL dynamically based on API key
  void _updateBaseUrl(String apiKey) {
    _dio.options.baseUrl = _getBaseUrl(apiKey);
  }

  // ============================================================================
  // DeepL API Integration
  // ============================================================================

  /// Create DeepL glossary from TWMT glossary
  ///
  /// Uploads glossary to DeepL API for use in translations.
  ///
  /// [glossaryId] - TWMT glossary ID
  /// [sourceLanguageCode] - Source language
  /// [targetLanguageCode] - Target language
  ///
  /// Returns DeepL glossary ID
  Future<Result<String, GlossaryException>> createDeepLGlossary({
    required String glossaryId,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) async {
    try {
      // 1. Get glossary from repository
      final glossary = await _glossaryRepository.getGlossaryById(glossaryId);
      if (glossary == null) {
        return Err(GlossaryNotFoundException(glossaryId));
      }

      // 2. Get glossary entries with specified language pair
      final entries = await _glossaryRepository.getEntriesByGlossary(
        glossaryId: glossaryId,
        targetLanguageCode: targetLanguageCode,
      );

      if (entries.isEmpty) {
        return Err(
          InvalidGlossaryDataException([
            'No entries found for language pair $sourceLanguageCode -> $targetLanguageCode'
          ]),
        );
      }

      // 3. Convert entries to DeepL TSV format
      final tsvContent = _convertToDeepLFormat(entries);

      // 4. Get API key and configure endpoint (FREE vs PRO)
      final apiKey = await _getApiKey();
      if (apiKey.isEmpty) {
        return Err(
          const DeepLGlossaryException(
            'DeepL API key not configured. Please configure it in settings.',
          ),
        );
      }
      _updateBaseUrl(apiKey);

      // 5. Create glossary name (unique per language pair)
      final glossaryName =
          '${glossary.name}_${sourceLanguageCode}_$targetLanguageCode';

      // 6. Map language codes to DeepL format
      final sourceLang = _mapLanguageCode(sourceLanguageCode);
      final targetLang = _mapLanguageCode(targetLanguageCode);

      // 7. Call DeepL API to create glossary
      final payload = {
        'name': glossaryName,
        'source_lang': sourceLang,
        'target_lang': targetLang,
        'entries': tsvContent,
        'entries_format': 'tsv',
      };

      final response = await _dio.post(
        '/glossaries',
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'DeepL-Auth-Key $apiKey',
          },
        ),
      );

      // 8. Extract and return DeepL glossary ID
      final data = response.data as Map<String, dynamic>;
      final deeplGlossaryId = data['glossary_id'] as String;

      return Ok(deeplGlossaryId);
    } on DioException catch (e) {
      return Err(_handleDioException(e));
    } catch (e, stackTrace) {
      return Err(
        DeepLGlossaryException(
          'Failed to create DeepL glossary: $e',
          null,
          stackTrace,
        ),
      );
    }
  }

  /// Delete DeepL glossary
  ///
  /// Deletes a glossary from DeepL platform via API.
  ///
  /// [deeplGlossaryId] - DeepL glossary ID to delete
  Future<Result<void, GlossaryException>> deleteDeepLGlossary(
    String deeplGlossaryId,
  ) async {
    try {
      // 1. Get API key and configure endpoint (FREE vs PRO)
      final apiKey = await _getApiKey();
      if (apiKey.isEmpty) {
        return Err(
          const DeepLGlossaryException(
            'DeepL API key not configured. Please configure it in settings.',
          ),
        );
      }
      _updateBaseUrl(apiKey);

      // 2. Call DeepL API to delete glossary
      await _dio.delete(
        '/glossaries/$deeplGlossaryId',
        options: Options(
          headers: {
            'Authorization': 'DeepL-Auth-Key $apiKey',
          },
        ),
      );

      return const Ok(null);
    } on DioException catch (e) {
      return Err(_handleDioException(e));
    } catch (e, stackTrace) {
      return Err(
        DeepLGlossaryException(
          'Failed to delete DeepL glossary: $e',
          null,
          stackTrace,
        ),
      );
    }
  }

  /// List all DeepL glossaries for the account
  ///
  /// Retrieves all glossaries available on DeepL platform.
  ///
  /// Returns list of glossary information (id, name, language pairs, etc.)
  Future<Result<List<Map<String, dynamic>>, GlossaryException>>
      listDeepLGlossaries() async {
    try {
      // 1. Get API key and configure endpoint (FREE vs PRO)
      final apiKey = await _getApiKey();
      if (apiKey.isEmpty) {
        return Err(
          const DeepLGlossaryException(
            'DeepL API key not configured. Please configure it in settings.',
          ),
        );
      }
      _updateBaseUrl(apiKey);

      // 2. Call DeepL API to list glossaries
      final response = await _dio.get(
        '/glossaries',
        options: Options(
          headers: {
            'Authorization': 'DeepL-Auth-Key $apiKey',
          },
        ),
      );

      // 3. Parse response
      final data = response.data as Map<String, dynamic>;
      final glossaries = data['glossaries'] as List;

      // 4. Return glossary information as list of maps
      // Each map contains:
      // - glossary_id: DeepL glossary ID
      // - name: Glossary name
      // - source_lang: Source language code
      // - target_lang: Target language code
      // - creation_time: Timestamp
      // - entry_count: Number of entries
      final result = glossaries.cast<Map<String, dynamic>>();

      return Ok(result);
    } on DioException catch (e) {
      return Err(_handleDioException(e));
    } catch (e, stackTrace) {
      return Err(
        DeepLGlossaryException(
          'Failed to list DeepL glossaries: $e',
          null,
          stackTrace,
        ),
      );
    }
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  /// Convert glossary entries to DeepL TSV format
  ///
  /// DeepL expects tab-separated values with source and target terms.
  /// Format: source_term\ttarget_term\n
  String _convertToDeepLFormat(List<GlossaryEntry> entries) {
    final buffer = StringBuffer();
    for (final entry in entries) {
      // Escape any tabs or newlines in the terms to prevent format issues
      final sourceTerm = entry.sourceTerm.replaceAll('\t', ' ').replaceAll('\n', ' ').trim();
      final targetTerm = entry.targetTerm.replaceAll('\t', ' ').replaceAll('\n', ' ').trim();

      // Add tab-separated entry
      buffer.write('$sourceTerm\t$targetTerm\n');
    }
    return buffer.toString();
  }

  /// Get DeepL API key from settings
  Future<String> _getApiKey() async {
    return await _settingsService.getString(_apiKeySettingKey);
  }

  /// Map language codes to DeepL format
  ///
  /// DeepL uses specific language codes (e.g., "EN", "DE", "FR")
  /// Some languages have variants (e.g., "EN-US", "EN-GB", "PT-BR", "PT-PT")
  String _mapLanguageCode(String isoCode) {
    // Map common ISO 639-1 codes to DeepL codes
    final mapping = {
      // European languages
      'en': 'EN', // English (will use EN-US by default)
      'en-us': 'EN-US', // American English
      'en-gb': 'EN-GB', // British English
      'de': 'DE', // German
      'fr': 'FR', // French
      'es': 'ES', // Spanish
      'it': 'IT', // Italian
      'nl': 'NL', // Dutch
      'pl': 'PL', // Polish
      'pt': 'PT-BR', // Portuguese (Brazilian by default)
      'pt-br': 'PT-BR', // Brazilian Portuguese
      'pt-pt': 'PT-PT', // European Portuguese
      'ru': 'RU', // Russian

      // Nordic languages
      'da': 'DA', // Danish
      'fi': 'FI', // Finnish
      'sv': 'SV', // Swedish
      'nb': 'NB', // Norwegian (Bokmål)

      // Eastern European languages
      'bg': 'BG', // Bulgarian
      'cs': 'CS', // Czech
      'et': 'ET', // Estonian
      'hu': 'HU', // Hungarian
      'lv': 'LV', // Latvian
      'lt': 'LT', // Lithuanian
      'ro': 'RO', // Romanian
      'sk': 'SK', // Slovak
      'sl': 'SL', // Slovenian

      // Other European languages
      'el': 'EL', // Greek
      'uk': 'UK', // Ukrainian
      'tr': 'TR', // Turkish

      // Asian languages
      'ja': 'JA', // Japanese
      'zh': 'ZH', // Chinese (Simplified)
      'zh-hans': 'ZH', // Chinese (Simplified)
      'ko': 'KO', // Korean
      'id': 'ID', // Indonesian

      // Arabic
      'ar': 'AR', // Arabic
    };

    final lowerCode = isoCode.toLowerCase();
    return mapping[lowerCode] ?? isoCode.toUpperCase();
  }

  /// Handle Dio exceptions and convert to GlossaryException
  GlossaryException _handleDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    final responseData = e.response?.data;

    // Extract error message from DeepL response
    String errorMessage = 'Unknown error';

    if (responseData is Map<String, dynamic>) {
      errorMessage = responseData['message'] as String? ?? errorMessage;
    } else if (responseData is String) {
      errorMessage = responseData;
    }

    // Handle authentication errors
    if (statusCode == 403) {
      return DeepLGlossaryException(
        'Invalid API key or insufficient quota: $errorMessage',
        statusCode,
      );
    }

    // Handle quota exceeded (DeepL-specific status code)
    if (statusCode == 456) {
      return DeepLGlossaryException(
        'Quota exceeded: $errorMessage',
        statusCode,
      );
    }

    // Handle rate limit errors
    if (statusCode == 429) {
      return DeepLGlossaryException(
        'Too many requests: $errorMessage',
        statusCode,
      );
    }

    // Handle invalid request errors
    if (statusCode == 400) {
      return DeepLGlossaryException(
        'Invalid request: $errorMessage',
        statusCode,
      );
    }

    // Handle unsupported language errors
    if (statusCode == 404) {
      return DeepLGlossaryException(
        'Glossary not found or unsupported language pair: $errorMessage',
        statusCode,
      );
    }

    // Handle other 4xx errors
    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      return DeepLGlossaryException(
        errorMessage,
        statusCode,
      );
    }

    // Handle server errors
    if (statusCode != null && statusCode >= 500) {
      return DeepLGlossaryException(
        'Server error: $errorMessage',
        statusCode,
      );
    }

    // Handle timeout errors
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return DeepLGlossaryException(
        'Request timeout: ${e.message}',
      );
    }

    // Handle connection errors
    if (e.type == DioExceptionType.connectionError) {
      return DeepLGlossaryException(
        'Connection failed: ${e.message}',
      );
    }

    // Default network error
    return DeepLGlossaryException(
      'Network error: ${e.message ?? errorMessage}',
    );
  }
}
