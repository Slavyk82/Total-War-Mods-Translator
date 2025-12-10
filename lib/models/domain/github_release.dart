/// Represents a GitHub release from the API.
class GitHubRelease {
  final String tagName;
  final String name;
  final String body;
  final bool isDraft;
  final bool isPrerelease;
  final DateTime publishedAt;
  final String htmlUrl;
  final List<GitHubAsset> assets;

  const GitHubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.isDraft,
    required this.isPrerelease,
    required this.publishedAt,
    required this.htmlUrl,
    required this.assets,
  });

  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    return GitHubRelease(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      isDraft: json['draft'] as bool? ?? false,
      isPrerelease: json['prerelease'] as bool? ?? false,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ??
          DateTime.now(),
      htmlUrl: json['html_url'] as String? ?? '',
      assets: (json['assets'] as List<dynamic>?)
              ?.map((e) => GitHubAsset.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Extract version from tag name (e.g., "v1.2.3" -> "1.2.3").
  String get version {
    final tag = tagName;
    if (tag.startsWith('v') || tag.startsWith('V')) {
      return tag.substring(1);
    }
    return tag;
  }

  /// Find the Windows installer asset.
  GitHubAsset? get windowsInstaller {
    return assets.firstWhere(
      (asset) =>
          asset.name.toLowerCase().endsWith('.exe') &&
          asset.name.toLowerCase().contains('installer'),
      orElse: () => assets.firstWhere(
        (asset) => asset.name.toLowerCase().endsWith('.exe'),
        orElse: () => const GitHubAsset.empty(),
      ),
    );
  }
}

/// Represents an asset attached to a GitHub release.
class GitHubAsset {
  final String name;
  final String browserDownloadUrl;
  final int size;
  final String contentType;
  final int downloadCount;

  const GitHubAsset({
    required this.name,
    required this.browserDownloadUrl,
    required this.size,
    required this.contentType,
    required this.downloadCount,
  });

  const GitHubAsset.empty()
      : name = '',
        browserDownloadUrl = '',
        size = 0,
        contentType = '',
        downloadCount = 0;

  bool get isEmpty => name.isEmpty;

  factory GitHubAsset.fromJson(Map<String, dynamic> json) {
    return GitHubAsset(
      name: json['name'] as String? ?? '',
      browserDownloadUrl: json['browser_download_url'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      contentType: json['content_type'] as String? ?? '',
      downloadCount: json['download_count'] as int? ?? 0,
    );
  }

  /// Get human-readable file size.
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
