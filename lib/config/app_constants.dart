/// Application-wide configuration constants
///
/// This file centralizes all magic numbers and configuration values
/// used throughout the TWMT application to improve maintainability
/// and make values easier to tune.
///
/// Constants are organized by functional area:
/// - Search Configuration
/// - LLM (Language Model) Configuration
/// - Translation Memory (TM) Configuration
/// - Translation Orchestration Configuration
/// - UI and Pagination Configuration
/// - Performance and Caching Configuration
class AppConstants {
  // Prevent instantiation
  AppConstants._();

  // ========== SEARCH CONFIGURATION ==========

  /// Maximum number of search history entries to keep in database
  ///
  /// When this limit is reached, oldest entries are automatically deleted.
  /// Prevents unbounded growth of search_history table.
  static const int maxSearchHistory = 100;

  /// Default limit for search history queries
  ///
  /// How many recent searches to show by default in search history UI.
  static const int defaultSearchHistoryLimit = 50;

  /// Maximum limit for search history queries
  ///
  /// Upper bound for user-requested history limit to prevent excessive queries.
  static const int maxSearchHistoryLimit = 100;

  /// Default number of search results to return
  ///
  /// Used when user doesn't specify a limit for search queries.
  static const int defaultSearchLimit = 100;

  /// Context length for search result snippets (in characters)
  ///
  /// How many characters to show before/after matched text in search results.
  static const int searchContextLength = 50;

  // ========== LLM (LANGUAGE MODEL) CONFIGURATION ==========

  /// Maximum concurrent LLM requests allowed
  ///
  /// Prevents overwhelming the LLM provider with too many parallel requests.
  /// Helps avoid rate limiting and manages system resources.
  static const int maxConcurrentLlmRequests = 10;

  /// Default batch size for LLM translation requests
  ///
  /// Number of translation units to include in a single LLM API call.
  /// Balanced for optimal performance and request size limits.
  static const int defaultLlmBatchSize = 25;

  /// Maximum batch size for LLM translation requests
  ///
  /// Upper limit to prevent token count from exceeding provider limits.
  static const int maxLlmBatchSize = 100;

  /// Maximum units per LLM request before forced split
  ///
  /// If a batch exceeds this size, it will be automatically split
  /// even before attempting translation. Prevents extremely large
  /// batches that cause response truncation or parsing errors.
  /// This is a hard limit to prevent overwhelmingly large requests.
  static const int maxUnitsPerLlmRequest = 50;

  /// Default provider when none is configured
  ///
  /// Fallback LLM provider to use if user hasn't selected one.
  static const String defaultLlmProvider = 'anthropic';

  // ========== LLM BATCH ADJUSTMENT CONFIGURATION ==========

  /// Token safety margin multiplier (70% of max tokens)
  ///
  /// Use only 70% of provider's max token limit to leave room for:
  /// - Variations in token counting
  /// - JSON structure overhead
  /// - Output token estimation errors
  static const double tokenSafetyMargin = 0.7;

  /// JSON structure overhead multiplier (5% additional tokens)
  ///
  /// Additional tokens needed for JSON formatting, keys, and structure
  /// beyond the actual text content.
  static const double jsonOverheadMultiplier = 1.05;

  /// Output token estimate multiplier (120% of input)
  ///
  /// Estimated ratio of output tokens to input tokens for translations.
  /// Translations typically expand by ~20% due to:
  /// - Different language structures
  /// - Additional formatting
  /// - Explanatory text
  static const double outputEstimateMultiplier = 1.2;


  // ========== TRANSLATION MEMORY (TM) CONFIGURATION ==========

  /// Minimum similarity threshold for TM fuzzy matches (85%)
  ///
  /// Fuzzy matches below this threshold are ignored.
  /// 85% is a good balance between finding useful matches and avoiding
  /// poor quality suggestions that waste translator time.
  static const double minTmSimilarity = 0.85;

  /// Auto-accept threshold for TM fuzzy matches (85%)
  ///
  /// Matches at or above this threshold are automatically applied without
  /// manual review. Aligned with minTmSimilarity for consistent behavior.
  static const double autoAcceptTmThreshold = 0.85;

  /// Maximum number of fuzzy match results to return
  ///
  /// Limits the number of TM suggestions shown to user to prevent
  /// overwhelming them with too many choices.
  static const int maxTmFuzzyResults = 5;

  /// Single fuzzy match result (for best match queries)
  ///
  /// When only the best match is needed, return just one result.
  static const int singleTmResult = 1;

  /// Days until unused TM entries are cleanup candidates
  ///
  /// Entries not used for this many days (and with low quality) may be
  /// deleted during cleanup to reduce database size.
  static const int unusedTmCleanupDays = 365;

  /// Maximum entries to cache in TM cache
  ///
  /// Limits memory usage by capping the number of cached TM entries.
  /// Most frequently used entries are kept in cache for fast lookup.
  static const int maxTmCacheEntries = 10000;

  // ========== TM SIMILARITY SCORING CONFIGURATION ==========

  /// Weight for Levenshtein distance in similarity calculation (40%)
  ///
  /// Levenshtein (edit distance) measures character-level similarity.
  /// Given highest weight as it's most reliable for game translations.
  static const double levenshteinWeight = 0.4;

  /// Weight for Jaro-Winkler distance in similarity calculation (30%)
  ///
  /// Jaro-Winkler favors strings with matching prefixes, useful for
  /// UI strings that often start with common words.
  static const double jaroWinklerWeight = 0.3;

  /// Weight for token-based similarity in similarity calculation (30%)
  ///
  /// Token similarity measures word-level overlap, good for catching
  /// reordered phrases and partial matches.
  static const double tokenWeight = 0.3;

  /// Context boost for matching game context (+5%)
  ///
  /// Small bonus when TM entry has the same game context as current text.
  /// Helps prioritize contextually relevant translations.
  static const double gameContextBoost = 0.05;

  /// Category boost for matching category (+3%)
  ///
  /// Small bonus when TM entry has the same category as current text.
  /// Further refines match quality based on text type.
  static const double categoryBoost = 0.03;

  /// Jaro-Winkler scaling factor for prefix matches (0.1)
  ///
  /// Standard Jaro-Winkler parameter that determines how much to boost
  /// the score for matching prefixes (first few characters).
  static const double jaroWinklerScalingFactor = 0.1;

  /// N-gram size for token similarity calculation
  ///
  /// Character n-grams of this size are used to calculate similarity
  /// at the sub-word level. 2-grams (bigrams) work well for most text.
  static const int nGramSize = 2;

  // ========== TRANSLATION ORCHESTRATION CONFIGURATION ==========

  /// Maximum parallel batches for concurrent translation
  ///
  /// How many translation batches can be processed simultaneously.
  /// Balances throughput with system resource usage.
  static const int maxParallelBatches = 3;

  /// Upper limit for user-specified parallel batch count
  ///
  /// Prevents users from requesting too many parallel batches which
  /// could overwhelm the system or hit provider rate limits.
  static const int maxParallelBatchLimit = 20;

  /// Estimated translation units processed per minute (for duration estimates)
  ///
  /// Rough throughput estimate used to calculate expected completion time.
  /// Actual speed varies by text complexity, provider, and batch size.
  static const int estimatedUnitsPerMinute = 50;

  // ========== UI AND PAGINATION CONFIGURATION ==========

  /// Default page size for paginated lists
  ///
  /// Number of items to show per page in data grids and list views.
  /// Balances data density with scrolling convenience.
  static const int defaultPageSize = 100;

  /// Maximum page size allowed for pagination
  ///
  /// Upper limit to prevent users from requesting too many items at once
  /// which could cause UI slowdowns or excessive memory usage.
  static const int maxPageSize = 1000;

  /// Minimum page size allowed for pagination
  ///
  /// Lower limit ensures at least some items are visible.
  static const int minPageSize = 1;

  /// Default TM entries to show per page
  ///
  /// Specific page size for translation memory entry lists.
  static const int defaultTmPageSize = 50;

  /// Debounce delay for search input (milliseconds)
  ///
  /// How long to wait after user stops typing before executing search.
  /// Prevents excessive API calls while user is still typing.
  static const int searchDebounceMs = 300;

  /// Maximum length for preview text snippets (characters)
  ///
  /// Truncate long text to this length for display in lists and cards.
  /// Shows "..." if text exceeds this length.
  static const int maxPreviewTextLength = 30;

  // ========== PERFORMANCE AND CACHING CONFIGURATION ==========

  /// Maximum entries to cache in general application cache
  ///
  /// Limits memory usage for application-wide cached data.
  /// Evicts least recently used entries when limit is reached.
  static const int maxCacheEntries = 500;

  /// Debounce duration for UI updates and event handling
  ///
  /// Standard debounce delay for non-search UI interactions to prevent
  /// excessive updates and improve performance.
  static const Duration debounceDelay = Duration(milliseconds: 300);

  // ========== UNDO/REDO CONFIGURATION ==========

  /// Maximum size of undo/redo stack
  ///
  /// How many historical actions to keep in memory for undo/redo.
  /// Prevents unbounded memory growth while providing reasonable history.
  static const int maxUndoStackSize = 100;

  // ========== USER IDENTIFICATION ==========

  /// Default user identifier for single-user desktop application
  ///
  /// TWMT is a single-user desktop application, so we use a constant
  /// identifier for the user. This is used in history tracking and
  /// change attribution.
  static const String defaultUserId = 'user';

  // ========== DATA LIMITS CONFIGURATION ==========

  /// Minimum similarity clamp value
  ///
  /// Lower bound for similarity scores in validation checks.
  static const double minSimilarityClamp = 0.0;

  /// Maximum similarity clamp value
  ///
  /// Upper bound for similarity scores in validation checks.
  static const double maxSimilarityClamp = 1.0;

  // ========== VALIDATION CONSTANTS ==========

  /// Exact match similarity score (100%)
  ///
  /// Perfect 1.0 similarity indicates exact match in TM.
  static const double exactMatchSimilarity = 1.0;

  /// Zero similarity score
  ///
  /// No similarity between texts (completely different).
  static const double zeroSimilarity = 0.0;

  /// Division factor for Jaro similarity calculation
  ///
  /// Standard denominator used in Jaro distance formula.
  static const double jaroSimilarityDivisor = 3.0;
}
