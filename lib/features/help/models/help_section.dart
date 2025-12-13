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

  /// Creates a HelpSection from a JSON map.
  factory HelpSection.fromJson(Map<String, dynamic> json) {
    return HelpSection(
      title: json['title'] as String,
      anchor: json['anchor'] as String,
      content: json['content'] as String,
      subsections: (json['subsections'] as List<dynamic>?)
              ?.map((e) => HelpSubsection.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  /// The section title (from the H2 header).
  final String title;

  /// URL-friendly anchor for navigation.
  final String anchor;

  /// The markdown content for this section (including the H2 header).
  final String content;

  /// Subsections within this section (H3, H4, etc.) for internal navigation.
  final List<HelpSubsection> subsections;

  /// Converts this section to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'anchor': anchor,
      'content': content,
      'subsections': subsections.map((s) => s.toJson()).toList(),
    };
  }
}

/// Represents a subsection within a help section.
class HelpSubsection {
  const HelpSubsection({
    required this.title,
    required this.anchor,
    required this.level,
  });

  /// Creates a HelpSubsection from a JSON map.
  factory HelpSubsection.fromJson(Map<String, dynamic> json) {
    return HelpSubsection(
      title: json['title'] as String,
      anchor: json['anchor'] as String,
      level: json['level'] as int,
    );
  }

  /// The subsection title.
  final String title;

  /// URL-friendly anchor for navigation.
  final String anchor;

  /// Header level (3 for H3, 4 for H4, etc.).
  final int level;

  /// Converts this subsection to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'anchor': anchor,
      'level': level,
    };
  }
}
