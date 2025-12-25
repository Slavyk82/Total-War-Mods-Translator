/// Represents a mapping between a TWMT glossary and a DeepL glossary.
///
/// DeepL requires glossaries to be created on their servers before use.
/// This mapping tracks which TWMT glossaries have been synced to DeepL
/// and their corresponding DeepL glossary IDs.
class DeepLGlossaryMapping {
  /// Unique identifier (UUID)
  final String id;

  /// TWMT glossary ID
  final String twmtGlossaryId;

  /// Source language code (e.g., 'en')
  final String sourceLanguageCode;

  /// Target language code (e.g., 'fr')
  final String targetLanguageCode;

  /// DeepL glossary ID (returned by DeepL API)
  final String deeplGlossaryId;

  /// DeepL glossary name (used when creating on DeepL)
  final String deeplGlossaryName;

  /// Number of entries in the glossary when synced
  final int entryCount;

  /// Sync status: 'synced', 'pending', 'error'
  final String syncStatus;

  /// Unix timestamp when the glossary was last synced to DeepL
  final int syncedAt;

  /// Unix timestamp when this mapping was created
  final int createdAt;

  /// Unix timestamp when this mapping was last updated
  final int updatedAt;

  const DeepLGlossaryMapping({
    required this.id,
    required this.twmtGlossaryId,
    required this.sourceLanguageCode,
    required this.targetLanguageCode,
    required this.deeplGlossaryId,
    required this.deeplGlossaryName,
    required this.entryCount,
    required this.syncStatus,
    required this.syncedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Whether this mapping is currently synced
  bool get isSynced => syncStatus == 'synced';

  /// Whether this mapping has an error
  bool get hasError => syncStatus == 'error';

  /// Whether this mapping is pending sync
  bool get isPending => syncStatus == 'pending';

  /// Language pair string for display
  String get languagePair => '$sourceLanguageCode → $targetLanguageCode';

  DeepLGlossaryMapping copyWith({
    String? id,
    String? twmtGlossaryId,
    String? sourceLanguageCode,
    String? targetLanguageCode,
    String? deeplGlossaryId,
    String? deeplGlossaryName,
    int? entryCount,
    String? syncStatus,
    int? syncedAt,
    int? createdAt,
    int? updatedAt,
  }) {
    return DeepLGlossaryMapping(
      id: id ?? this.id,
      twmtGlossaryId: twmtGlossaryId ?? this.twmtGlossaryId,
      sourceLanguageCode: sourceLanguageCode ?? this.sourceLanguageCode,
      targetLanguageCode: targetLanguageCode ?? this.targetLanguageCode,
      deeplGlossaryId: deeplGlossaryId ?? this.deeplGlossaryId,
      deeplGlossaryName: deeplGlossaryName ?? this.deeplGlossaryName,
      entryCount: entryCount ?? this.entryCount,
      syncStatus: syncStatus ?? this.syncStatus,
      syncedAt: syncedAt ?? this.syncedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory DeepLGlossaryMapping.fromJson(Map<String, dynamic> json) {
    return DeepLGlossaryMapping(
      id: json['id'] as String,
      twmtGlossaryId: json['twmt_glossary_id'] as String,
      sourceLanguageCode: json['source_language_code'] as String,
      targetLanguageCode: json['target_language_code'] as String,
      deeplGlossaryId: json['deepl_glossary_id'] as String,
      deeplGlossaryName: json['deepl_glossary_name'] as String,
      entryCount: json['entry_count'] as int,
      syncStatus: json['sync_status'] as String,
      syncedAt: json['synced_at'] as int,
      createdAt: json['created_at'] as int,
      updatedAt: json['updated_at'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'twmt_glossary_id': twmtGlossaryId,
      'source_language_code': sourceLanguageCode,
      'target_language_code': targetLanguageCode,
      'deepl_glossary_id': deeplGlossaryId,
      'deepl_glossary_name': deeplGlossaryName,
      'entry_count': entryCount,
      'sync_status': syncStatus,
      'synced_at': syncedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeepLGlossaryMapping &&
        other.id == id &&
        other.twmtGlossaryId == twmtGlossaryId &&
        other.sourceLanguageCode == sourceLanguageCode &&
        other.targetLanguageCode == targetLanguageCode &&
        other.deeplGlossaryId == deeplGlossaryId;
  }

  @override
  int get hashCode => Object.hash(
        id,
        twmtGlossaryId,
        sourceLanguageCode,
        targetLanguageCode,
        deeplGlossaryId,
      );

  @override
  String toString() =>
      'DeepLGlossaryMapping(twmtGlossaryId: $twmtGlossaryId, deeplGlossaryId: $deeplGlossaryId, languagePair: $languagePair)';
}
