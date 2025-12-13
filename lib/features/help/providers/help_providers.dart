import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/help_section.dart';

part 'help_providers.g.dart';

/// Cache file name for parsed help documentation.
const _helpCacheFileName = 'help_sections_cache.json';

/// Provider that loads and parses the user guide into sections.
///
/// Uses a persistent cache that is valid until the app version changes.
/// This dramatically improves Help screen load times on subsequent opens.
@riverpod
Future<List<HelpSection>> helpSections(Ref ref) async {
  // Try to load from cache first
  final cachedSections = await _loadFromCache();
  if (cachedSections != null) {
    return cachedSections;
  }

  // Cache miss or invalid - parse from source
  final content = await rootBundle.loadString('docs/user_guide.md');
  final sections = _parseUserGuideIntoSections(content);

  // Save to cache for next time (fire and forget)
  _saveToCache(sections);

  return sections;
}

/// Get the cache file path in AppData/Local/TWMT/cache.
Future<File> _getCacheFile() async {
  final appDir = await getApplicationSupportDirectory();
  final cacheDir = Directory(path.join(appDir.path, 'cache'));
  if (!await cacheDir.exists()) {
    await cacheDir.create(recursive: true);
  }
  return File(path.join(cacheDir.path, _helpCacheFileName));
}

/// Load sections from cache if valid (same app version).
Future<List<HelpSection>?> _loadFromCache() async {
  try {
    final cacheFile = await _getCacheFile();
    if (!await cacheFile.exists()) {
      return null;
    }

    final jsonString = await cacheFile.readAsString();
    final json = jsonDecode(jsonString) as Map<String, dynamic>;

    // Check version match
    final cachedVersion = json['version'] as String?;
    final packageInfo = await PackageInfo.fromPlatform();
    if (cachedVersion != packageInfo.version) {
      // Version mismatch - invalidate cache
      await cacheFile.delete();
      return null;
    }

    // Parse cached sections
    final sectionsJson = json['sections'] as List<dynamic>;
    return sectionsJson
        .map((e) => HelpSection.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    // Any error - invalidate cache and return null
    return null;
  }
}

/// Save sections to cache with current app version.
Future<void> _saveToCache(List<HelpSection> sections) async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final cacheFile = await _getCacheFile();

    final json = {
      'version': packageInfo.version,
      'sections': sections.map((s) => s.toJson()).toList(),
    };

    await cacheFile.writeAsString(jsonEncode(json));
  } catch (_) {
    // Ignore cache write errors - not critical
  }
}

/// Provider for the currently selected section index.
@riverpod
class SelectedSectionIndex extends _$SelectedSectionIndex {
  @override
  int build() => 0;

  void select(int index) {
    state = index;
  }
}

/// Parse the user guide content into sections based on H2 headers.
List<HelpSection> _parseUserGuideIntoSections(String content) {
  final sections = <HelpSection>[];
  final lines = content.split('\n');

  // Find all H2 header positions
  final h2Positions = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('## ')) {
      h2Positions.add(i);
    }
  }

  // If there's content before the first H2, create an intro section
  if (h2Positions.isEmpty) {
    // No H2 headers, treat entire content as single section
    sections.add(HelpSection(
      title: 'Documentation',
      anchor: 'documentation',
      content: content,
      subsections: _parseSubsections(content),
    ));
    return sections;
  }

  // Content before first H2 (includes H1 title and intro)
  if (h2Positions.first > 0) {
    final introContent = lines.sublist(0, h2Positions.first).join('\n').trim();
    if (introContent.isNotEmpty) {
      // Extract H1 title if present
      final h1Match = RegExp(r'^# (.+)$', multiLine: true).firstMatch(introContent);
      final title = h1Match?.group(1) ?? 'Introduction';

      sections.add(HelpSection(
        title: title,
        anchor: _headerToAnchor(title),
        content: introContent,
        subsections: _parseSubsections(introContent),
      ));
    }
  }

  // Parse each H2 section
  for (var i = 0; i < h2Positions.length; i++) {
    final startLine = h2Positions[i];
    final endLine = i + 1 < h2Positions.length ? h2Positions[i + 1] : lines.length;

    final sectionLines = lines.sublist(startLine, endLine);
    final sectionContent = sectionLines.join('\n').trim();

    // Extract the H2 title
    final titleLine = lines[startLine];
    final title = titleLine.substring(3).trim(); // Remove '## '

    sections.add(HelpSection(
      title: title,
      anchor: _headerToAnchor(title),
      content: sectionContent,
      subsections: _parseSubsections(sectionContent),
    ));
  }

  return sections;
}

/// Parse subsections (H3, H4, etc.) within a section's content.
List<HelpSubsection> _parseSubsections(String content) {
  final subsections = <HelpSubsection>[];
  final headerRegex = RegExp(r'^(#{3,6})\s+(.+)$', multiLine: true);
  final matches = headerRegex.allMatches(content);

  for (final match in matches) {
    final hashes = match.group(1)!;
    final title = match.group(2)!;
    final level = hashes.length;

    subsections.add(HelpSubsection(
      title: title,
      anchor: _headerToAnchor(title),
      level: level,
    ));
  }

  return subsections;
}

/// Convert a header title to a URL-friendly anchor.
String _headerToAnchor(String headerText) {
  return headerText
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}
