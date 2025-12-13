/// Represents a section of the help documentation.
///
/// Each section corresponds to content under a main heading (H2) in the README.
class HelpSection {
  const HelpSection({
    required this.title,
    required this.anchor,
    required this.content,
    this.subsections = const [],
  });

  /// The section title (from the H2 header).
  final String title;

  /// URL-friendly anchor for navigation.
  final String anchor;

  /// The markdown content for this section (including the H2 header).
  final String content;

  /// Subsections within this section (H3, H4, etc.) for internal navigation.
  final List<HelpSubsection> subsections;
}

/// Represents a subsection within a help section.
class HelpSubsection {
  const HelpSubsection({
    required this.title,
    required this.anchor,
    required this.level,
  });

  /// The subsection title.
  final String title;

  /// URL-friendly anchor for navigation.
  final String anchor;

  /// Header level (3 for H3, 4 for H4, etc.).
  final int level;
}
