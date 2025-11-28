import 'dart:async';
import 'dart:isolate';

/// Message sent to the isolate for batch similarity computation
class SimilarityBatchRequest {
  final String sourceText;
  final List<CandidateData> candidates;
  final double minSimilarity;
  final String? category;

  const SimilarityBatchRequest({
    required this.sourceText,
    required this.candidates,
    required this.minSimilarity,
    this.category,
  });
}

/// Simplified candidate data that can be passed to isolate
class CandidateData {
  final String id;
  final String sourceText;
  final String translatedText;
  final int usageCount;
  final int lastUsedAt;
  final double qualityScore;

  const CandidateData({
    required this.id,
    required this.sourceText,
    required this.translatedText,
    required this.usageCount,
    required this.lastUsedAt,
    required this.qualityScore,
  });
}

/// Result from similarity computation
class SimilarityResult {
  final String candidateId;
  final double combinedScore;
  final double levenshteinScore;
  final double jaroWinklerScore;
  final double tokenScore;
  final double contextBoost;

  const SimilarityResult({
    required this.candidateId,
    required this.combinedScore,
    required this.levenshteinScore,
    required this.jaroWinklerScore,
    required this.tokenScore,
    required this.contextBoost,
  });
}

/// Service that performs similarity calculations in a background isolate
/// to prevent UI freezing during heavy computation.
class IsolateSimilarityService {
  static IsolateSimilarityService? _instance;
  Isolate? _isolate;
  SendPort? _sendPort;
  final _responseCompleter = <int, Completer<List<SimilarityResult>>>{};
  int _requestId = 0;

  IsolateSimilarityService._();

  static IsolateSimilarityService get instance {
    _instance ??= IsolateSimilarityService._();
    return _instance!;
  }

  /// Initialize the isolate
  Future<void> initialize() async {
    if (_isolate != null) return;

    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      receivePort.sendPort,
    );

    final completer = Completer<SendPort>();
    receivePort.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      } else if (message is _IsolateResponse) {
        final completer = _responseCompleter.remove(message.requestId);
        completer?.complete(message.results);
      }
    });

    _sendPort = await completer.future;
  }

  /// Dispose of the isolate
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _responseCompleter.clear();
  }

  /// Calculate similarity for a batch of candidates in the isolate
  Future<List<SimilarityResult>> calculateBatchSimilarity({
    required String sourceText,
    required List<CandidateData> candidates,
    required double minSimilarity,
    String? category,
  }) async {
    if (_sendPort == null) {
      await initialize();
    }

    final requestId = _requestId++;
    final completer = Completer<List<SimilarityResult>>();
    _responseCompleter[requestId] = completer;

    _sendPort!.send(_IsolateRequest(
      requestId: requestId,
      sourceText: sourceText,
      candidates: candidates,
      minSimilarity: minSimilarity,
      category: category,
    ));

    return completer.future;
  }

  /// Entry point for the background isolate
  static void _isolateEntryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is _IsolateRequest) {
        final results = _computeSimilarityBatch(
          message.sourceText,
          message.candidates,
          message.minSimilarity,
          message.category,
        );
        mainSendPort.send(_IsolateResponse(
          requestId: message.requestId,
          results: results,
        ));
      }
    });
  }

  /// Compute similarity for a batch of candidates (runs in isolate)
  static List<SimilarityResult> _computeSimilarityBatch(
    String sourceText,
    List<CandidateData> candidates,
    double minSimilarity,
    String? category,
  ) {
    final results = <SimilarityResult>[];
    final normalizedSource = _normalize(sourceText);

    for (final candidate in candidates) {
      final normalizedCandidate = _normalize(candidate.sourceText);

      final levenshtein = _levenshteinSimilarity(normalizedSource, normalizedCandidate);
      final jaroWinkler = _jaroWinklerSimilarity(normalizedSource, normalizedCandidate);
      final token = _tokenSimilarity(normalizedSource, normalizedCandidate);

      // Weights: Levenshtein 40%, Jaro-Winkler 30%, Token 30%
      const levenshteinWeight = 0.4;
      const jaroWinklerWeight = 0.3;
      const tokenWeight = 0.3;

      double contextBoost = 0.0;
      // Category boost would be applied here if categories matched

      final combinedScore = (levenshtein * levenshteinWeight) +
          (jaroWinkler * jaroWinklerWeight) +
          (token * tokenWeight) +
          contextBoost;

      final clampedScore = combinedScore.clamp(0.0, 1.0);

      if (clampedScore >= minSimilarity) {
        results.add(SimilarityResult(
          candidateId: candidate.id,
          combinedScore: clampedScore,
          levenshteinScore: levenshtein,
          jaroWinklerScore: jaroWinkler,
          tokenScore: token,
          contextBoost: contextBoost,
        ));
      }
    }

    // Sort by score descending
    results.sort((a, b) => b.combinedScore.compareTo(a.combinedScore));
    return results;
  }

  /// Normalize text for comparison
  static String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Calculate Levenshtein similarity
  static double _levenshteinSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final distance = _levenshteinDistance(s1, s2);
    final maxLen = s1.length > s2.length ? s1.length : s2.length;
    return 1.0 - (distance / maxLen);
  }

  /// Calculate Levenshtein edit distance
  static int _levenshteinDistance(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;

    // Use two rows instead of full matrix for memory efficiency
    var prevRow = List<int>.generate(len2 + 1, (i) => i);
    var currRow = List<int>.filled(len2 + 1, 0);

    for (var i = 1; i <= len1; i++) {
      currRow[0] = i;
      for (var j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        currRow[j] = [
          prevRow[j] + 1, // deletion
          currRow[j - 1] + 1, // insertion
          prevRow[j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
      // Swap rows
      final temp = prevRow;
      prevRow = currRow;
      currRow = temp;
    }

    return prevRow[len2];
  }

  /// Calculate Jaro-Winkler similarity
  static double _jaroWinklerSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final jaroSim = _jaroSimilarity(s1, s2);

    // Calculate common prefix length (up to 4 characters)
    int prefixLength = 0;
    final maxPrefix = [s1.length, s2.length, 4].reduce((a, b) => a < b ? a : b);
    for (var i = 0; i < maxPrefix; i++) {
      if (s1[i] == s2[i]) {
        prefixLength++;
      } else {
        break;
      }
    }

    const scalingFactor = 0.1;
    return jaroSim + (prefixLength * scalingFactor * (1.0 - jaroSim));
  }

  /// Calculate Jaro similarity
  static double _jaroSimilarity(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;

    final matchWindow = ((len1 > len2 ? len1 : len2) / 2).floor() - 1;
    if (matchWindow < 0) return 0.0;

    final s1Matches = List<bool>.filled(len1, false);
    final s2Matches = List<bool>.filled(len2, false);

    var matches = 0;
    var transpositions = 0;

    for (var i = 0; i < len1; i++) {
      final start = (i - matchWindow) > 0 ? i - matchWindow : 0;
      final end = (i + matchWindow + 1) < len2 ? i + matchWindow + 1 : len2;

      for (var j = start; j < end; j++) {
        if (s2Matches[j] || s1[i] != s2[j]) continue;
        s1Matches[i] = true;
        s2Matches[j] = true;
        matches++;
        break;
      }
    }

    if (matches == 0) return 0.0;

    var k = 0;
    for (var i = 0; i < len1; i++) {
      if (!s1Matches[i]) continue;
      while (!s2Matches[k]) {
        k++;
      }
      if (s1[i] != s2[k]) transpositions++;
      k++;
    }

    return (matches / len1 + matches / len2 + (matches - transpositions / 2) / matches) / 3.0;
  }

  /// Calculate token-based (Jaccard) similarity
  static double _tokenSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final tokens1 = s1.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
    final tokens2 = s2.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();

    if (tokens1.isEmpty || tokens2.isEmpty) return 0.0;

    final intersection = tokens1.intersection(tokens2);
    final union = tokens1.union(tokens2);

    return intersection.length / union.length;
  }
}

/// Internal request message
class _IsolateRequest {
  final int requestId;
  final String sourceText;
  final List<CandidateData> candidates;
  final double minSimilarity;
  final String? category;

  const _IsolateRequest({
    required this.requestId,
    required this.sourceText,
    required this.candidates,
    required this.minSimilarity,
    this.category,
  });
}

/// Internal response message
class _IsolateResponse {
  final int requestId;
  final List<SimilarityResult> results;

  const _IsolateResponse({
    required this.requestId,
    required this.results,
  });
}
