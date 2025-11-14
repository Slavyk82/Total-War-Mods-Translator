# Architecture de la Couche Services - TWMT

**Document technique** : Architecture détaillée de la couche services (Business Layer) de l'application TWMT.

---

## Vue d'ensemble

La couche services de TWMT implémente la **Clean Architecture** avec une séparation stricte entre :

- **Présentation** (UI, ViewModels) → Ne connaît que les services
- **Services** (Business Logic) → Orchestre les opérations métier
- **Repositories** (Data Access) → Accès aux données (DB, API)

Cette architecture garantit :
- ✅ **Testabilité** : Services mockables via interfaces
- ✅ **Maintenabilité** : Responsabilités claires et séparées
- ✅ **Évolutivité** : Ajout de providers/services sans impacter le reste
- ✅ **Type-safety** : Gestion d'erreurs via Result<T, E>

---

## Structure des répertoires

```
lib/services/
├── llm/
│   ├── i_llm_service.dart                    # Interface principale LLM
│   ├── llm_service_impl.dart                 # Implémentation orchestrateur
│   ├── providers/
│   │   ├── i_llm_provider.dart               # Interface provider
│   │   ├── anthropic_provider.dart           # Anthropic Claude
│   │   ├── openai_provider.dart              # OpenAI GPT
│   │   └── deepl_provider.dart               # DeepL
│   ├── llm_provider_factory.dart             # Factory pour providers
│   ├── models/
│   │   ├── llm_request.dart                  # Requête de traduction
│   │   ├── llm_response.dart                 # Réponse LLM
│   │   ├── llm_provider_config.dart          # Configuration provider
│   │   └── batch_translation_result.dart     # Résultat batch
│   └── utils/
│       ├── token_calculator.dart             # Calcul de tokens
│       └── rate_limiter.dart                 # Rate limiting
├── rpfm/
│   ├── i_rpfm_service.dart                   # Interface RPFM-CLI
│   ├── rpfm_service_impl.dart                # Implémentation
│   ├── models/
│   │   ├── rpfm_extract_result.dart          # Résultat extraction
│   │   └── rpfm_pack_info.dart               # Infos .pack
│   └── utils/
│       └── rpfm_output_parser.dart           # Parser output CLI
├── steam/
│   ├── i_steamcmd_service.dart               # Interface SteamCMD
│   ├── steamcmd_service_impl.dart            # Implémentation
│   ├── i_workshop_api_service.dart           # Interface Workshop API
│   ├── workshop_api_service_impl.dart        # Implémentation
│   └── models/
│       ├── workshop_item_info.dart           # Infos mod Workshop
│       └── workshop_update_info.dart         # Infos MAJ
├── file/
│   ├── i_file_service.dart                   # Interface fichiers
│   ├── file_service_impl.dart                # Implémentation
│   ├── i_localization_parser.dart            # Interface parser .loc
│   ├── localization_parser_impl.dart         # Parser implementation
│   └── models/
│       ├── localization_entry.dart           # Entrée key-value
│       └── localization_file.dart            # Fichier .loc complet
├── translation/
│   ├── i_translation_orchestrator.dart       # Interface orchestrateur
│   ├── translation_orchestrator_impl.dart    # Implémentation
│   ├── i_prompt_builder_service.dart         # Interface prompts
│   ├── prompt_builder_service_impl.dart      # Construction prompts
│   ├── i_validation_service.dart             # Interface validation
│   ├── validation_service_impl.dart          # Validation traductions
│   └── models/
│       ├── translation_batch.dart            # Définition batch
│       ├── translation_context.dart          # Contexte traduction
│       ├── validation_result.dart            # Résultat validation
│       └── translation_progress.dart         # Progress tracking
├── database/
│   ├── database_service.dart                 # Initialisation DB
│   └── migration_service.dart                # Migrations schéma
├── settings/
│   ├── i_settings_service.dart               # Interface settings
│   └── settings_service_impl.dart            # Implémentation
├── process/
│   ├── i_process_service.dart                # Interface process externes
│   └── process_service_impl.dart             # Exécution process
└── service_locator.dart                       # Injection de dépendances
```

**Total** : ~40 fichiers

---

## Gestion d'erreurs

### Type Result<T, E>

Pattern fonctionnel pour gestion d'erreurs explicite (inspiré de Rust) :

```dart
// lib/models/common/result.dart

sealed class Result<T, E> {
  const Result();

  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  T unwrap() {
    return switch (this) {
      Ok(value: final v) => v,
      Err(error: final e) => throw StateError('Called unwrap on Err: $e'),
    };
  }

  T unwrapOr(T defaultValue) {
    return switch (this) {
      Ok(value: final v) => v,
      Err() => defaultValue,
    };
  }

  Result<U, E> map<U>(U Function(T) fn) {
    return switch (this) {
      Ok(value: final v) => Ok(fn(v)),
      Err(error: final e) => Err(e),
    };
  }

  R match<R>({
    required R Function(T) ok,
    required R Function(E) err,
  }) {
    return switch (this) {
      Ok(value: final v) => ok(v),
      Err(error: final e) => err(e),
    };
  }
}

class Ok<T, E> extends Result<T, E> {
  final T value;
  const Ok(this.value);
}

class Err<T, E> extends Result<T, E> {
  final E error;
  const Err(this.error);
}
```

**Utilisation** :

```dart
final result = await llmService.translateBatch(request);

result.match(
  ok: (response) => print('Success: ${response.translations.length} translations'),
  err: (error) => print('Error: $error'),
);

// Ou avec unwrapOr pour valeur par défaut
final translations = result.unwrapOr(LlmResponse.empty());
```

### Hiérarchie d'exceptions

```dart
// lib/models/common/service_exception.dart

/// Exception de base pour tous les services
abstract class ServiceException implements Exception {
  final String message;
  final String? details;
  final Object? originalError;
  final StackTrace? stackTrace;

  const ServiceException(
    this.message, {
    this.details,
    this.originalError,
    this.stackTrace,
  });
}

/// Exceptions LLM
class LlmServiceException extends ServiceException { }
class LlmProviderException extends LlmServiceException { }
class LlmRateLimitException extends LlmProviderException {
  final Duration retryAfter;
}
class LlmAuthenticationException extends LlmProviderException { }
class LlmQuotaExceededException extends LlmProviderException { }
class LlmTokenLimitException extends LlmServiceException {
  final int estimatedTokens;
  final int maxTokens;
}

/// Exceptions RPFM
class RpfmServiceException extends ServiceException { }
class RpfmNotFoundException extends RpfmServiceException {
  final String? attemptedPath;
}
class RpfmTimeoutException extends RpfmServiceException {
  final Duration timeout;
}
class RpfmExtractionException extends RpfmServiceException {
  final String packPath;
}

/// Exceptions Steam
class SteamServiceException extends ServiceException { }
class SteamCmdNotFoundException extends SteamServiceException { }
class SteamCmdDownloadException extends SteamServiceException {
  final String appId;
  final String modId;
}
class WorkshopApiException extends SteamServiceException {
  final int? statusCode;
}

/// Exceptions Fichiers
class FileServiceException extends ServiceException { }
class LocalizationParseException extends FileServiceException {
  final String filePath;
  final int? lineNumber;
}
class FileWriteException extends FileServiceException {
  final String filePath;
}

/// Exceptions Traduction
class TranslationOrchestrationException extends ServiceException { }
class BatchProcessingException extends TranslationOrchestrationException {
  final String batchId;
  final int failedUnitsCount;
}

/// Exceptions Database
class DatabaseException extends ServiceException { }
class DatabaseMigrationException extends DatabaseException {
  final int fromVersion;
  final int toVersion;
}

/// Exceptions Process
class ProcessException extends ServiceException {
  final String command;
  final int? exitCode;
}
```

---

## Services LLM

### Interface principale

```dart
// lib/services/llm/i_llm_service.dart

abstract class ILlmService {
  /// Traduit un batch d'unités via le provider actif global
  Future<Result<LlmResponse, LlmServiceException>> translateBatch(
    LlmRequest request,
  );

  /// Traduit plusieurs batches en parallèle (respect rate limits)
  Stream<Result<BatchTranslationResult, LlmServiceException>>
      translateBatchesParallel(
    List<LlmRequest> requests, {
    required int maxParallel,
  });

  /// Estime le nombre de tokens pour une requête
  Future<Result<int, LlmServiceException>> estimateTokens(
    LlmRequest request,
  );

  /// Valide qu'un batch respecte les limites de tokens
  Future<Result<bool, LlmServiceException>> validateBatchSize(
    LlmRequest request,
  );

  /// Ajuste automatiquement la taille d'un batch trop grand
  Future<Result<List<LlmRequest>, LlmServiceException>> adjustBatchSize(
    LlmRequest request,
  );

  /// Valide une clé API pour un provider
  Future<Result<bool, LlmServiceException>> validateApiKey(
    String providerCode,
    String apiKey,
  );

  /// Récupère le provider actif global
  Future<String> getActiveProviderCode();

  /// Indique si le streaming est supporté
  bool supportsStreaming();

  /// Traduction avec streaming (progress temps réel)
  Stream<Result<String, LlmServiceException>> translateStreaming(
    LlmRequest request,
  );
}
```

### Interface Provider

```dart
// lib/services/llm/providers/i_llm_provider.dart

abstract class ILlmProvider {
  /// Code du provider (anthropic, openai, deepl)
  String get providerCode;

  /// Nom lisible
  String get providerName;

  /// Configuration (endpoint, modèle, limites)
  LlmProviderConfig get config;

  /// Traduit un batch d'unités
  Future<Result<LlmResponse, LlmProviderException>> translate(
    LlmRequest request,
    String apiKey,
  );

  /// Estime les tokens (spécifique au provider)
  int estimateTokens(String text);

  /// Valide une clé API
  Future<Result<bool, LlmProviderException>> validateApiKey(String apiKey);

  /// Support du streaming
  bool get supportsStreaming;

  /// Traduction streaming
  Stream<Result<String, LlmProviderException>> translateStreaming(
    LlmRequest request,
    String apiKey,
  );

  /// Calcule le délai de retry en cas de rate limit
  Duration calculateRetryDelay(LlmRateLimitException exception);
}
```

### Modèles LLM

```dart
// lib/services/llm/models/llm_request.dart

class LlmRequest {
  final String requestId;
  final Map<String, String> units;              // key -> source text
  final String sourceLanguageCode;
  final String targetLanguageCode;
  final TranslationContext context;
  final int? batchNumber;

  int get totalCharacters => units.values.fold(0, (sum, text) => sum + text.length);
  int get unitCount => units.length;
}

// lib/services/llm/models/llm_response.dart

class LlmResponse {
  final String requestId;
  final Map<String, String> translations;       // key -> translated text
  final String providerCode;
  final String model;
  final int? tokensUsed;
  final Map<String, double>? confidenceScores;  // 0-1 par unité
  final int processingTimeMs;
}

// lib/services/llm/models/llm_provider_config.dart

class LlmProviderConfig {
  final String code;                            // anthropic, openai, deepl
  final String name;
  final String apiEndpoint;
  final String? defaultModel;
  final int? maxContextTokens;                  // Taille context window
  final int maxBatchSize;                       // Unités max par requête
  final int? rateLimitRpm;                      // Requests per minute
  final int? rateLimitTpm;                      // Tokens per minute
  final bool isActive;
}
```

### Factory Pattern

```dart
// lib/services/llm/llm_provider_factory.dart

class LlmProviderFactory {
  /// Crée un provider à partir de la config
  static ILlmProvider createProvider(LlmProviderConfig config) {
    return switch (config.code) {
      'anthropic' => AnthropicProvider(config),
      'openai' => OpenAiProvider(config),
      'deepl' => DeepLProvider(config),
      _ => throw ArgumentError('Unknown provider: ${config.code}'),
    };
  }

  /// Liste des providers supportés
  static List<String> get supportedProviders => ['anthropic', 'openai', 'deepl'];
}
```

### Rate Limiter

```dart
// lib/services/llm/utils/rate_limiter.dart

class RateLimiter {
  final int? requestsPerMinute;
  final int? tokensPerMinute;

  final Queue<DateTime> _requestTimestamps = Queue();
  int _tokensUsedInWindow = 0;
  DateTime _windowStart = DateTime.now();

  /// Vérifie si une requête peut être faite immédiatement
  bool canMakeRequest(int estimatedTokens) { }

  /// Attend jusqu'à ce qu'une requête soit possible
  Future<Duration> waitForSlot(int estimatedTokens) async { }

  /// Enregistre qu'une requête a été faite
  void recordRequest(int tokensUsed) { }

  /// Calcule le temps avant le prochain slot disponible
  Duration timeUntilAvailable(int estimatedTokens) { }

  /// Reset de l'état
  void reset() { }
}
```

### Token Calculator

```dart
// lib/services/llm/utils/token_calculator.dart

class TokenCalculator {
  /// Estime les tokens (règle 4 caractères = 1 token)
  static int estimateTokens(String text, {String? languageCode}) {
    final baseEstimate = (text.length / 4).ceil();
    final multiplier = _getLanguageMultiplier(languageCode);
    return (baseEstimate * multiplier).ceil();
  }

  /// Estime le total pour un batch (input + output + prompts + buffer 20%)
  static int estimateBatchTokens({
    required String systemPrompt,
    required String contextPrompt,
    required List<String> inputTexts,
    required String languageCode,
  }) {
    final systemTokens = estimateTokens(systemPrompt);
    final contextTokens = estimateTokens(contextPrompt);
    final inputTokens = inputTexts.map((t) => estimateTokens(t, languageCode: languageCode))
        .fold<int>(0, (sum, tokens) => sum + tokens);
    final outputTokens = inputTokens; // Assume même taille

    return ((systemTokens + contextTokens + inputTokens + outputTokens) * 1.2).ceil();
  }

  /// Calcule la taille optimale de batch pour une limite
  static int calculateOptimalBatchSize({
    required int maxContextTokens,
    required String systemPrompt,
    required String contextPrompt,
    required int averageTextLength,
    required String languageCode,
  }) {
    final fixedTokens = estimateTokens(systemPrompt) + estimateTokens(contextPrompt);
    final availableTokens = ((maxContextTokens - fixedTokens) / 2.4).floor();
    final tokensPerUnit = estimateTokens('x' * averageTextLength, languageCode: languageCode);

    return (availableTokens / tokensPerUnit).floor();
  }

  static double _getLanguageMultiplier(String? languageCode) {
    return switch (languageCode) {
      'zh' => 1.5,  // Chinois
      'ja' => 1.5,  // Japonais
      'ru' => 1.2,  // Russe
      'de' => 1.1,  // Allemand
      _ => 1.0,     // Anglais, langues romanes
    };
  }

  /// Valide qu'un batch respecte les limites (90% du max pour sécurité)
  static bool validateBatchSize({
    required int estimatedTokens,
    required int maxContextTokens,
  }) => estimatedTokens <= (maxContextTokens * 0.9);
}
```

---

## Services RPFM

### Interface RPFM-CLI

```dart
// lib/services/rpfm/i_rpfm_service.dart

abstract class IRpfmService {
  /// Extrait un .pack vers un répertoire
  Future<Result<RpfmExtractResult, RpfmServiceException>> extractPack(
    String packPath,
    String outputDir, {
    Duration timeout = const Duration(minutes: 5),
  });

  /// Crée un .pack à partir de fichiers de localisation
  Future<Result<String, RpfmServiceException>> createPack(
    String outputPackPath,
    Map<String, String> localizationFiles, {  // relative path -> absolute path
    Duration timeout = const Duration(minutes: 5),
  });

  /// Valide la structure d'un .pack
  Future<Result<RpfmPackInfo, RpfmServiceException>> validatePack(
    String packPath,
  );

  /// Liste les fichiers dans un .pack (sans extraire)
  Future<Result<List<String>, RpfmServiceException>> listPackFiles(
    String packPath,
  );

  /// Trouve les fichiers de localisation dans un répertoire extrait
  Future<Result<List<String>, RpfmServiceException>> findLocalizationFiles(
    String extractedDir,
  );

  /// Récupère le chemin configuré de RPFM-CLI
  Future<String> getRpfmPath();

  /// Valide que RPFM-CLI est disponible et exécutable
  Future<Result<bool, RpfmServiceException>> validateRpfmInstallation();

  /// Détecte automatiquement l'installation de RPFM-CLI
  Future<Result<String, RpfmServiceException>> detectRpfmInstallation();
}
```

### Modèles RPFM

```dart
// lib/services/rpfm/models/rpfm_extract_result.dart

class RpfmExtractResult {
  final String extractedDir;
  final List<String> extractedFiles;         // Tous les fichiers
  final List<String> localizationFiles;      // .loc et .tsv uniquement
  final Duration duration;
}

// lib/services/rpfm/models/rpfm_pack_info.dart

class RpfmPackInfo {
  final String packPath;
  final int fileCount;
  final int sizeBytes;
  final bool isValid;
  final String? errorMessage;
}
```

---

## Services Steam

### Interface SteamCMD

```dart
// lib/services/steam/i_steamcmd_service.dart

abstract class ISteamCmdService {
  /// Télécharge un mod Workshop via SteamCMD
  Future<Result<String, SteamServiceException>> downloadWorkshopItem(
    String appId,
    String modId, {
    Duration timeout = const Duration(minutes: 30),
  });

  /// Valide un mod téléchargé
  Future<Result<WorkshopItemInfo, SteamServiceException>> validateDownloadedItem(
    String appId,
    String modId,
  );

  /// Chemin SteamCMD
  Future<String> getSteamCmdPath();

  /// Valide que SteamCMD est installé
  Future<Result<bool, SteamServiceException>> validateSteamCmdInstallation();

  /// S'assure que SteamCMD est installé (télécharge si nécessaire)
  Future<Result<String, SteamServiceException>> ensureSteamCmdInstalled();

  /// Répertoire de téléchargement des mods
  Future<String> getWorkshopDownloadDir(String appId, String modId);
}
```

### Interface Workshop API

```dart
// lib/services/steam/i_workshop_api_service.dart

abstract class IWorkshopApiService {
  /// Récupère les infos d'un mod Workshop
  Future<Result<WorkshopItemInfo, WorkshopApiException>> getWorkshopItem(
    String appId,
    String modId,
  );

  /// Vérifie si un mod a été mis à jour
  Future<Result<WorkshopUpdateInfo, WorkshopApiException>> checkForUpdate(
    String appId,
    String modId,
    int lastKnownTimestamp,
  );

  /// Récupère plusieurs mods en batch (plus efficace)
  Future<Result<Map<String, WorkshopItemInfo>, WorkshopApiException>>
      getWorkshopItemsBatch(
    String appId,
    List<String> modIds,
  );
}
```

### Modèles Steam

```dart
// lib/services/steam/models/workshop_item_info.dart

class WorkshopItemInfo {
  final String modId;
  final String appId;
  final String title;
  final String? description;
  final String? creator;
  final int timeUpdated;              // Epoch seconds
  final int timeCreated;
  final int? fileSizeBytes;
  final int? subscriptions;
  final bool isAvailable;
}

// lib/services/steam/models/workshop_update_info.dart

class WorkshopUpdateInfo {
  final String modId;
  final bool hasUpdate;
  final int currentTimestamp;
  final int previousTimestamp;

  int get updateAgeDelta => currentTimestamp - previousTimestamp;
}
```

---

## Services Fichiers

### Interface File Service

```dart
// lib/services/file/i_file_service.dart

abstract class IFileService {
  /// Répertoires AppData
  Future<String> getAppDataDir();         // AppData\Roaming\TWMT
  Future<String> getDatabasePath();       // AppData\Roaming\TWMT\twmt.db
  Future<String> getConfigDir();          // AppData\Roaming\TWMT\config
  Future<String> getLogsDir();            // AppData\Local\TWMT\logs
  Future<String> getCacheDir();           // AppData\Local\TWMT\cache
  Future<String> getTempDir();            // Temp\TWMT

  /// Assure qu'un répertoire existe
  Future<Result<String, FileServiceException>> ensureDirectoryExists(String path);

  /// Écrit un fichier de localisation (UTF-8, avec préfixage optionnel)
  Future<Result<String, FileServiceException>> writeLocalizationFile(
    String filePath,
    LocalizationFile locFile, {
    String? prefixLanguage,
  });

  /// Applique le préfixe de langue à un nom de fichier
  /// "units.loc" + "FR" -> "!!!!!!!!!!_FR_units.loc"
  String applyLanguagePrefix(String filename, String languageCode);

  /// Retire le préfixe de langue
  String removeLanguagePrefix(String filename);

  /// Copie un fichier
  Future<Result<String, FileServiceException>> copyFile(
    String sourcePath,
    String destPath,
  );

  /// Supprime un fichier/répertoire
  Future<Result<bool, FileServiceException>> delete(
    String path, {
    bool recursive = false,
  });

  /// Nettoie les fichiers temporaires
  Future<Result<void, FileServiceException>> cleanupTempFiles();
}
```

### Interface Localization Parser

```dart
// lib/services/file/i_localization_parser.dart

abstract class ILocalizationParser {
  /// Parse un fichier .loc ou .tsv
  Future<Result<LocalizationFile, LocalizationParseException>> parseFile(
    String filePath,
  );

  /// Parse du contenu brut
  Result<LocalizationFile, LocalizationParseException> parseContent(
    String content, {
    required String format,  // 'loc' ou 'tsv'
  });

  /// Sérialise vers string
  String serialize(LocalizationFile locFile, {required String format});

  /// Détecte automatiquement la langue d'un fichier
  Future<Result<String, LocalizationParseException>> detectLanguage(
    LocalizationFile locFile,
  );
}
```

### Modèles Fichiers

```dart
// lib/services/file/models/localization_entry.dart

class LocalizationEntry {
  final String key;
  final String text;
  final String? context;
}

// lib/services/file/models/localization_file.dart

class LocalizationFile {
  final String? filePath;
  final List<LocalizationEntry> entries;
  final String format;              // 'loc' ou 'tsv'
  final String? languageCode;

  int get entryCount => entries.length;

  LocalizationEntry? getEntry(String key);
  Map<String, String> toMap();
}
```

---

## Services Traduction

### Interface Translation Orchestrator

```dart
// lib/services/translation/i_translation_orchestrator.dart

abstract class ITranslationOrchestrator {
  /// Orchestre la traduction complète d'un batch
  ///
  /// Workflow:
  /// 1. TM lookup (exact matches)
  /// 2. LLM request pour unités restantes
  /// 3. Token estimation + ajustement batch
  /// 4. Traduction LLM
  /// 5. Validation
  /// 6. Sauvegarde DB
  /// 7. MAJ Translation Memory
  Stream<Result<TranslationProgress, TranslationOrchestrationException>>
      translateBatch(TranslationBatch batch);

  /// Traduit plusieurs batches en parallèle (coordination)
  Stream<Result<TranslationProgress, TranslationOrchestrationException>>
      translateBatchesParallel(
    List<TranslationBatch> batches, {
    required int maxParallel,
  });

  /// Pause un batch
  Future<Result<bool, TranslationOrchestrationException>> pauseBatch(
    String batchId,
  );

  /// Reprend un batch pausé
  Future<Result<bool, TranslationOrchestrationException>> resumeBatch(
    String batchId,
  );

  /// Annule un batch
  Future<Result<bool, TranslationOrchestrationException>> cancelBatch(
    String batchId,
  );

  /// Statistiques en temps réel
  Future<Result<TranslationProgress, TranslationOrchestrationException>>
      getBatchProgress(String batchId);
}
```

### Interface Prompt Builder

```dart
// lib/services/translation/i_prompt_builder_service.dart

abstract class IPromptBuilderService {
  /// Construit le prompt complet pour une traduction
  ///
  /// Structure:
  /// [System prompt]
  /// [Game context prompt]
  /// [Project custom prompt]
  /// [Translation instructions]
  /// [Format specification]
  /// [Input texts]
  String buildPrompt({
    required TranslationContext context,
    required Map<String, String> units,
    required String sourceLanguage,
    required String targetLanguage,
  });

  /// Prompt système par défaut
  String getSystemPrompt();

  /// Récupère le prompt de contexte pour un jeu
  Future<String> getGameContextPrompt(String gameCode);

  /// Définit le prompt de contexte pour un jeu
  Future<void> setGameContextPrompt(String gameCode, String prompt);

  /// Instructions de format de sortie
  String getFormatInstructions();

  /// Interpole les variables dans un template
  String interpolateVariables(
    String template,
    Map<String, String> variables,
  );
}
```

### Interface Validation

```dart
// lib/services/translation/i_validation_service.dart

abstract class IValidationService {
  /// Valide une traduction
  ///
  /// Vérifications:
  /// - Non vide
  /// - Longueur raisonnable (< 150% source)
  /// - Variables préservées ({0}, %s, etc.)
  /// - Caractères spéciaux préservés
  /// - Pas d'injection HTML/script
  ValidationResult validateTranslation({
    required String sourceText,
    required String translatedText,
    required String sourceLanguage,
    required String targetLanguage,
  });

  /// Valide un batch complet
  Map<String, ValidationResult> validateBatch({
    required Map<String, ({String source, String translated})> translations,
    required String sourceLanguage,
    required String targetLanguage,
  });

  /// Vérifie qu'une traduction passe le seuil de qualité
  bool isValidTranslation(ValidationResult result);

  /// Calcule un score de confiance (0-1)
  double calculateConfidenceScore(ValidationResult result);
}
```

### Modèles Traduction

```dart
// lib/services/translation/models/translation_context.dart

class TranslationContext {
  final String projectId;
  final String gameCode;
  final String gameName;
  final String gamePrompt;
  final String? projectPrompt;
  final int batchSize;
  final int parallelBatches;
}

// lib/services/translation/models/translation_batch.dart

class TranslationBatch {
  final String batchId;
  final String projectLanguageId;
  final Map<String, String> units;        // unitId -> sourceText
  final String sourceLanguageCode;
  final String targetLanguageCode;
  final TranslationContext context;
  final int batchNumber;
}

// lib/services/translation/models/translation_progress.dart

enum TranslationStatus {
  pending,
  tmLookup,
  llmTranslating,
  validating,
  saving,
  completed,
  failed,
  paused,
  cancelled,
}

class TranslationProgress {
  final String batchId;
  final TranslationStatus status;
  final int totalUnits;
  final int completedUnits;
  final int failedUnits;
  final Duration? estimatedTimeRemaining;
  final String? errorMessage;
  final DateTime timestamp;

  double get progressPercent => totalUnits > 0
      ? (completedUnits / totalUnits) * 100
      : 0;
}

// lib/services/translation/models/validation_result.dart

enum ValidationIssueType {
  emptyTranslation,
  tooLong,
  missingVariables,
  extraVariables,
  missingSpecialChars,
  suspiciousContent,
  encodingIssue,
}

enum ValidationSeverity {
  info,
  warning,
  critical,
}

class ValidationIssue {
  final ValidationIssueType type;
  final ValidationSeverity severity;
  final String message;
  final String? details;
}

class ValidationResult {
  final bool isValid;
  final List<ValidationIssue> issues;
  final double confidenceScore;

  bool get hasCriticalIssues =>
      issues.any((i) => i.severity == ValidationSeverity.critical);
  bool get hasWarnings =>
      issues.any((i) => i.severity == ValidationSeverity.warning);
}
```

---

## Services Database & Settings

### Database Service

```dart
// lib/services/database/database_service.dart

class DatabaseService {
  static Database? _database;
  static const String _dbName = 'twmt.db';
  static const int _currentVersion = 1;

  /// Initialise la base de données (idempotent)
  static Future<Result<void, DatabaseException>> initialize() async {
    if (_database != null) return const Ok(null);

    final appDir = await getApplicationSupportDirectory();
    final dbPath = path.join(appDir.path, _dbName);

    _database = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _currentVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
      ),
    );

    return const Ok(null);
  }

  static Database get database {
    if (_database == null) {
      throw StateError('Database not initialized');
    }
    return _database!;
  }

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('PRAGMA journal_mode = WAL');
    await db.execute('PRAGMA synchronous = NORMAL');
    await db.execute('PRAGMA cache_size = -64000');      // 64MB
    await db.execute('PRAGMA temp_store = MEMORY');
    await db.execute('PRAGMA mmap_size = 268435456');    // 256MB
    await db.execute('PRAGMA page_size = 4096');
    await db.execute('PRAGMA auto_vacuum = INCREMENTAL');
  }

  static Future<void> _onCreate(Database db, int version) async {
    await MigrationService.createSchema(db);
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await MigrationService.migrate(db, oldVersion, newVersion);
  }
}
```

### Settings Service

```dart
// lib/services/settings/i_settings_service.dart

abstract class ISettingsService {
  Future<Result<String, SettingsException>> getString(String key);
  Future<Result<int, SettingsException>> getInt(String key);
  Future<Result<bool, SettingsException>> getBool(String key);
  Future<Result<Map<String, dynamic>, SettingsException>> getJson(String key);

  Future<Result<void, SettingsException>> setString(String key, String value);
  Future<Result<void, SettingsException>> setInt(String key, int value);
  Future<Result<void, SettingsException>> setBool(String key, bool value);
  Future<Result<void, SettingsException>> setJson(String key, Map<String, dynamic> value);

  // Raccourcis pour settings fréquents
  Future<Result<String, SettingsException>> getActiveProviderId();
  Future<Result<void, SettingsException>> setActiveProviderId(String providerId);
  Future<Result<int, SettingsException>> getDefaultBatchSize();
  Future<Result<int, SettingsException>> getDefaultParallelBatches();
  Future<Result<Map<String, String>, SettingsException>> getGameContextPrompts();
  Future<Result<String, SettingsException>> getGameContextPrompt(String gameCode);
  Future<Result<void, SettingsException>> setGameContextPrompt(String gameCode, String prompt);
}
```

---

## Service Process

### Interface Process Service

```dart
// lib/services/process/i_process_service.dart

abstract class IProcessService {
  /// Exécute un process externe et retourne le résultat complet
  Future<Result<ProcessResult, ProcessException>> execute(
    String command,
    List<String> arguments, {
    String? workingDirectory,
    Duration timeout = const Duration(minutes: 5),
  });

  /// Exécute avec streaming du stdout/stderr
  Stream<Result<String, ProcessException>> executeStreaming(
    String command,
    List<String> arguments, {
    String? workingDirectory,
    Duration timeout = const Duration(minutes: 5),
  });

  /// Trouve un exécutable dans le PATH système
  Future<Result<String, ProcessException>> findInPath(String executable);

  /// Valide qu'un exécutable existe et est exécutable
  Future<Result<bool, ProcessException>> validateExecutable(String path);
}

class ProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;

  bool get isSuccess => exitCode == 0;
}
```

---

## Service Locator

### Injection de dépendances

```dart
// lib/services/service_locator.dart

import 'package:get_it/get_it.dart';

class ServiceLocator {
  static final GetIt _locator = GetIt.instance;

  /// Initialise et enregistre tous les services
  static Future<void> initialize() async {
    // Services de base (sans dépendances)
    _locator.registerLazySingleton<IProcessService>(
      () => ProcessServiceImpl(),
    );

    _locator.registerLazySingleton<IFileService>(
      () => FileServiceImpl(),
    );

    _locator.registerLazySingleton<ILocalizationParser>(
      () => LocalizationParserImpl(),
    );

    _locator.registerLazySingleton<ISettingsService>(
      () => SettingsServiceImpl(),
    );

    // Services externes
    _locator.registerLazySingleton<IRpfmService>(
      () => RpfmServiceImpl(
        processService: _locator<IProcessService>(),
        fileService: _locator<IFileService>(),
      ),
    );

    _locator.registerLazySingleton<ISteamCmdService>(
      () => SteamCmdServiceImpl(
        processService: _locator<IProcessService>(),
        fileService: _locator<IFileService>(),
      ),
    );

    _locator.registerLazySingleton<IWorkshopApiService>(
      () => WorkshopApiServiceImpl(),
    );

    // Services de traduction
    _locator.registerLazySingleton<IPromptBuilderService>(
      () => PromptBuilderServiceImpl(
        settingsService: _locator<ISettingsService>(),
      ),
    );

    _locator.registerLazySingleton<IValidationService>(
      () => ValidationServiceImpl(),
    );

    _locator.registerLazySingleton<ILlmService>(
      () => LlmServiceImpl(
        settingsService: _locator<ISettingsService>(),
      ),
    );

    _locator.registerLazySingleton<ITranslationOrchestrator>(
      () => TranslationOrchestratorImpl(
        llmService: _locator<ILlmService>(),
        promptBuilder: _locator<IPromptBuilderService>(),
        validationService: _locator<IValidationService>(),
      ),
    );

    // Note: Repositories seraient enregistrés ici également
  }

  /// Récupère une instance de service (type-safe)
  static T get<T extends Object>() => _locator<T>();

  /// Vérifie si un service est enregistré
  static bool isRegistered<T extends Object>() => _locator.isRegistered<T>();

  /// Reset (utile pour les tests)
  static Future<void> reset() async {
    await _locator.reset();
  }
}
```

---

## Graphe de dépendances

```
┌─────────────────┐
│ DatabaseService │ (pas de dépendances)
└────────┬────────┘
         ↓
┌────────────────┐
│SettingsService │ (utilise Database)
└────┬───────────┘
     ↓ ↓ ↓
     │ │ └────────────────────────┐
     │ │                          │
     │ │  ┌────────────────┐      │
     │ └─→│ ProcessService │      │ (pas de dépendances)
     │    └────────┬───────┘      │
     │             ↓              │
     │    ┌────────────────┐      │
     └───→│  FileService   │←─────┘
          └────┬───────────┘
               ↓ ↓
      ┌────────┘ └──────────┐
      │                     │
┌─────────────┐    ┌────────────────┐
│ RpfmService │    │SteamCmdService │
└─────────────┘    └────────┬───────┘
                            ↓
                   ┌────────────────┐
                   │WorkshopApiSvc  │
                   └────────────────┘

┌────────────────────┐
│PromptBuilderSvc    │←── SettingsService
└────────────────────┘

┌────────────────────┐
│ ValidationService  │ (pas de dépendances)
└────────────────────┘

┌────────────────────┐
│    LlmService      │←── SettingsService
└─────────┬──────────┘
          ↓
┌─────────────────────┐
│TranslationOrchest.  │←── LlmService, PromptBuilder, Validation
└─────────────────────┘
```

---

## Initialisation (main.dart)

```dart
// lib/main.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/service_locator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Window management (Windows)
  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(800, 600),
      center: true,
      title: 'TWMT - Total War Mod Translator',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // 2. Initialiser la base de données
  final dbResult = await DatabaseService.initialize();
  dbResult.match(
    ok: (_) => debugPrint('✅ Database initialized'),
    err: (error) {
      debugPrint('❌ Database initialization failed: $error');
      // Afficher dialogue d'erreur et quitter
      return;
    },
  );

  // 3. Initialiser les services
  try {
    await ServiceLocator.initialize();
    debugPrint('✅ Services initialized');
  } catch (e, stackTrace) {
    debugPrint('❌ Service initialization failed: $e\n$stackTrace');
    return;
  }

  // 4. Lancer l'application
  runApp(const MyApp());
}
```

---

## Patterns d'utilisation

### Pattern Service dans ViewModel

```dart
class ProjectsViewModel extends ChangeNotifier {
  final ITranslationOrchestrator _orchestrator;
  final IWorkshopApiService _workshopApi;

  ProjectsViewModel({
    required ITranslationOrchestrator orchestrator,
    required IWorkshopApiService workshopApi,
  })  : _orchestrator = orchestrator,
        _workshopApi = workshopApi;

  // Factory avec service locator
  factory ProjectsViewModel.create() {
    return ProjectsViewModel(
      orchestrator: ServiceLocator.get<ITranslationOrchestrator>(),
      workshopApi: ServiceLocator.get<IWorkshopApiService>(),
    );
  }

  Future<void> startTranslation(String projectId) async {
    // Utilisation des services...
  }
}
```

### Pattern Result pour gestion d'erreurs

```dart
Future<void> translateProject(String projectId) async {
  final result = await _orchestrator.translateBatch(batch);

  result.match(
    ok: (progress) {
      // Succès
      _updateProgress(progress);
      notifyListeners();
    },
    err: (error) {
      // Erreur
      if (error is LlmRateLimitException) {
        _scheduleRetry(error.retryAfter);
      } else {
        _showError(error.message);
      }
    },
  );
}
```

### Pattern Stream pour progress

```dart
void startBatchTranslation(List<TranslationBatch> batches) {
  final progressStream = _orchestrator.translateBatchesParallel(
    batches,
    maxParallel: 3,
  );

  progressStream.listen(
    (result) {
      result.match(
        ok: (progress) {
          // Mise à jour UI en temps réel
          _updateBatchProgress(progress);
          notifyListeners();
        },
        err: (error) {
          _handleBatchError(error);
        },
      );
    },
    onDone: () {
      _onAllBatchesCompleted();
    },
  );
}
```

---

## Tests

### Structure des tests

```
test/
├── services/
│   ├── llm/
│   │   ├── llm_service_test.dart
│   │   ├── anthropic_provider_test.dart
│   │   ├── rate_limiter_test.dart
│   │   └── token_calculator_test.dart
│   ├── rpfm/
│   │   └── rpfm_service_test.dart
│   ├── steam/
│   │   ├── steamcmd_service_test.dart
│   │   └── workshop_api_service_test.dart
│   ├── translation/
│   │   ├── translation_orchestrator_test.dart
│   │   └── validation_service_test.dart
│   └── file/
│       └── localization_parser_test.dart
└── mocks/
    ├── mock_llm_provider.dart
    ├── mock_process_service.dart
    └── mock_repositories.dart
```

### Exemple de test

```dart
// test/services/llm/token_calculator_test.dart

void main() {
  group('TokenCalculator', () {
    test('estimates tokens using 4-character rule', () {
      final text = 'Hello World';
      final tokens = TokenCalculator.estimateTokens(text);

      expect(tokens, equals(3)); // 11 chars / 4 = 2.75 → 3
    });

    test('applies language multiplier for Chinese', () {
      final text = '你好世界';
      final tokens = TokenCalculator.estimateTokens(text, languageCode: 'zh');

      // 4 chars / 4 = 1, but 1.5x multiplier = 1.5 → 2
      expect(tokens, equals(2));
    });

    test('calculates optimal batch size within token limit', () {
      final batchSize = TokenCalculator.calculateOptimalBatchSize(
        maxContextTokens: 10000,
        systemPrompt: 'You are a translator.',
        contextPrompt: 'Game: Warhammer 3',
        averageTextLength: 100,
        languageCode: 'en',
      );

      expect(batchSize, greaterThan(0));
      expect(batchSize, lessThan(100));
    });
  });
}
```

---

## Bonnes pratiques

### 1. Toujours utiliser Result<T, E>

❌ **Mauvais** :
```dart
Future<LlmResponse> translate(LlmRequest request) async {
  if (apiKey.isEmpty) {
    throw LlmAuthenticationException('Invalid API key');
  }
  // ...
}
```

✅ **Bon** :
```dart
Future<Result<LlmResponse, LlmProviderException>> translate(
  LlmRequest request,
) async {
  if (apiKey.isEmpty) {
    return Err(LlmAuthenticationException('Invalid API key'));
  }
  // ...
  return Ok(response);
}
```

### 2. Interfaces, pas d'implémentations concrètes

❌ **Mauvais** :
```dart
class MyViewModel {
  final AnthropicProvider _provider; // Couplage fort
}
```

✅ **Bon** :
```dart
class MyViewModel {
  final ILlmService _llmService; // Couplage faible via interface
}
```

### 3. Service Locator pour injection

❌ **Mauvais** :
```dart
final service = LlmServiceImpl(); // Création directe
```

✅ **Bon** :
```dart
final service = ServiceLocator.get<ILlmService>(); // Via service locator
```

### 4. Gestion explicite des erreurs

❌ **Mauvais** :
```dart
try {
  await service.translate(request);
} catch (e) {
  print('Error: $e'); // Gestion générique
}
```

✅ **Bon** :
```dart
final result = await service.translate(request);
result.match(
  ok: (response) => _handleSuccess(response),
  err: (error) {
    if (error is LlmRateLimitException) {
      _scheduleRetry(error.retryAfter);
    } else if (error is LlmTokenLimitException) {
      _reduceBatchSize();
    } else {
      _showError(error.message);
    }
  },
);
```

### 5. Streams pour opérations longues

✅ **Bon** :
```dart
Stream<Result<Progress, Exception>> processLongOperation() async* {
  for (var i = 0; i < items.length; i++) {
    yield Ok(Progress(current: i, total: items.length));
    await _processItem(items[i]);
  }
}
```

---

## Résumé

Cette architecture de services fournit :

- ✅ **40+ interfaces** bien définies
- ✅ **Séparation claire** des responsabilités
- ✅ **Gestion d'erreurs robuste** via Result<T, E>
- ✅ **Injection de dépendances** via Service Locator
- ✅ **Testabilité** complète (tous les services mockables)
- ✅ **Évolutivité** (ajout facile de providers/services)
- ✅ **Type-safety** partout
- ✅ **Documentation** inline complète

**Prochaines étapes** :
1. Créer les fichiers d'interfaces (lib/services/**/*_service.dart)
2. Implémenter les services un par un
3. Écrire les tests unitaires
4. Intégrer dans les ViewModels

Référence : Ce document doit être lu en complément de `specs.md` (spécifications fonctionnelles) et de `CLAUDE.md` (conventions de code).
