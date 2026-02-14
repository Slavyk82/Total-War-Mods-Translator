/// Visibility options for Steam Workshop items
enum WorkshopVisibility {
  public_(0),
  friendsOnly(1),
  private_(2),
  unlisted(3);

  final int value;
  const WorkshopVisibility(this.value);

  String get label => switch (this) {
        public_ => 'Public',
        friendsOnly => 'Friends Only',
        private_ => 'Private',
        unlisted => 'Unlisted',
      };
}

/// Parameters for publishing/updating a Workshop item via steamcmd
class WorkshopPublishParams {
  /// Steam App ID (e.g., 1142710 for TW:WH3)
  final String appId;

  /// Existing Workshop file ID ("0" for new items)
  final String publishedFileId;

  /// Path to the folder containing the .pack file
  final String contentFolder;

  /// Path to the preview image (512x512 PNG)
  final String previewFile;

  /// Workshop item title
  final String title;

  /// Workshop item description
  final String description;

  /// Change notes (for updates)
  final String changeNote;

  /// Visibility setting
  final WorkshopVisibility visibility;

  /// Steam Workshop tags (e.g., 'compilation' for TW:WH3 launcher visibility)
  final List<String> tags;

  const WorkshopPublishParams({
    required this.appId,
    this.publishedFileId = '0',
    required this.contentFolder,
    required this.previewFile,
    required this.title,
    required this.description,
    this.changeNote = '',
    this.visibility = WorkshopVisibility.public_,
    this.tags = const ['compilation'],
  });

  /// Whether this is a new Workshop item (not an update)
  bool get isNewItem => publishedFileId == '0';

  WorkshopPublishParams copyWith({
    String? appId,
    String? publishedFileId,
    String? contentFolder,
    String? previewFile,
    String? title,
    String? description,
    String? changeNote,
    WorkshopVisibility? visibility,
    List<String>? tags,
  }) {
    return WorkshopPublishParams(
      appId: appId ?? this.appId,
      publishedFileId: publishedFileId ?? this.publishedFileId,
      contentFolder: contentFolder ?? this.contentFolder,
      previewFile: previewFile ?? this.previewFile,
      title: title ?? this.title,
      description: description ?? this.description,
      changeNote: changeNote ?? this.changeNote,
      visibility: visibility ?? this.visibility,
      tags: tags ?? this.tags,
    );
  }
}
