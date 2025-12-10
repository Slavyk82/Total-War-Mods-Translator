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
  ///
  /// Priority order:
  /// 1. .exe with "installer" or "setup" in name
  /// 2. .msix file (Windows App Package)
  /// 3. .msi file (Windows Installer)
  /// 4. Any .exe file
  /// 5. .zip file with "windows" in name
  /// 6. Any .zip file
  GitHubAsset? get windowsInstaller {
    final lowerAssets = assets.map((a) => (a, a.name.toLowerCase())).toList();

    // Priority 1: .exe with "installer" or "setup" in name
    for (final (asset, name) in lowerAssets) {
      if (name.endsWith('.exe') &&
          (name.contains('installer') || name.contains('setup'))) {
        return asset;
      }
    }

    // Priority 2: .msix file (modern Windows package)
    for (final (asset, name) in lowerAssets) {
      if (name.endsWith('.msix')) {
        return asset;
      }
    }

    // Priority 3: .msi file (Windows Installer)
    for (final (asset, name) in lowerAssets) {
      if (name.endsWith('.msi')) {
        return asset;
      }
    }

    // Priority 4: Any .exe file
    for (final (asset, name) in lowerAssets) {
      if (name.endsWith('.exe')) {
        return asset;
      }
    }

    // Priority 5: .zip with "windows" in name
    for (final (asset, name) in lowerAssets) {
      if (name.endsWith('.zip') && name.contains('windows')) {
        return asset;
      }
    }

    // Priority 6: Any .zip file (fallback)
    for (final (asset, name) in lowerAssets) {
      if (name.endsWith('.zip')) {
        return asset;
      }
    }

    return const GitHubAsset.empty();
  }

  /// Check if the installer requires extraction (e.g., .zip files).
  bool get installerRequiresExtraction {
    final asset = windowsInstaller;
    if (asset == null || asset.isEmpty) return false;
    return asset.name.toLowerCase().endsWith('.zip');
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
