import 'dart:convert';

/// Project metadata stored as JSON
class ProjectMetadata {
  final String? modTitle;
  final String? modImageUrl;
  final String? modDescription;
  final int? modSubscribers;

  const ProjectMetadata({
    this.modTitle,
    this.modImageUrl,
    this.modDescription,
    this.modSubscribers,
  });

  factory ProjectMetadata.fromJson(Map<String, dynamic> json) {
    return ProjectMetadata(
      modTitle: json['mod_title'] as String?,
      modImageUrl: json['mod_image_url'] as String?,
      modDescription: json['mod_description'] as String?,
      modSubscribers: json['mod_subscribers'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (modTitle != null) 'mod_title': modTitle,
      if (modImageUrl != null) 'mod_image_url': modImageUrl,
      if (modDescription != null) 'mod_description': modDescription,
      if (modSubscribers != null) 'mod_subscribers': modSubscribers,
    };
  }

  /// Parse metadata from JSON string
  static ProjectMetadata? fromJsonString(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return null;
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return ProjectMetadata.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  /// Convert metadata to JSON string
  String toJsonString() {
    return jsonEncode(toJson());
  }

  ProjectMetadata copyWith({
    String? modTitle,
    String? modImageUrl,
    String? modDescription,
    int? modSubscribers,
  }) {
    return ProjectMetadata(
      modTitle: modTitle ?? this.modTitle,
      modImageUrl: modImageUrl ?? this.modImageUrl,
      modDescription: modDescription ?? this.modDescription,
      modSubscribers: modSubscribers ?? this.modSubscribers,
    );
  }
}

