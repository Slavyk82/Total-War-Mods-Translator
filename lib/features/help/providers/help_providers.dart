import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/help_section.dart';

part 'help_providers.g.dart';

/// Provider that loads and parses the user guide into sections.
@riverpod
Future<List<HelpSection>> helpSections(Ref ref) async {
  final content = await rootBundle.loadString('docs/user_guide.md');
  return _parseUserGuideIntoSections(content);
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
