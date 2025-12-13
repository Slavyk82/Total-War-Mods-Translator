import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/help_section.dart';

/// Widget that renders the markdown content of a single help section.
class HelpSectionContent extends StatelessWidget {
  const HelpSectionContent({
    super.key,
    required this.section,
    this.onNavigateToSection,
  });

  /// The section to display.
  final HelpSection section;

  /// Callback when an internal link to another section is tapped.
  /// The anchor string is passed to allow navigation.
  final ValueChanged<String>? onNavigateToSection;

  Future<void> _handleLinkTap(String? href) async {
    if (href == null) return;

    // Internal anchor links
    if (href.startsWith('#')) {
      final anchor = href.substring(1);
      onNavigateToSection?.call(anchor);
      return;
    }

    // External links
    final uri = Uri.tryParse(href);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: MarkdownBody(
            data: section.content,
            selectable: true,
            shrinkWrap: true,
            onTapLink: (text, href, title) => _handleLinkTap(href),
            sizedImageBuilder: (config) => _buildImage(
              config.uri,
              config.title,
              config.alt,
              config.width,
              config.height,
              theme,
            ),
            styleSheet: _buildMarkdownStyleSheet(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(
    Uri uri,
    String? title,
    String? alt,
    double? width,
    double? height,
    ThemeData theme,
  ) {
    final path = uri.toString();

    Widget imageWidget;

    // Limit width to 1000px max
    const double maxWidth = 1000;
    final effectiveWidth = width != null && width < maxWidth ? width : maxWidth;

    if (path.startsWith('http://') || path.startsWith('https://')) {
      // Network image
      imageWidget = Image.network(
        path,
        width: effectiveWidth,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildImageError(theme, alt ?? 'Image failed to load');
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildImageLoading();
        },
      );
    } else {
      // Asset image
      final assetPath = path.startsWith('assets/') ? path : 'assets/$path';
      imageWidget = Image.asset(
        assetPath,
        width: effectiveWidth,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildImageError(theme, alt ?? path);
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.dividerColor,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: imageWidget,
            ),
          ),
          if (alt != null && alt.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              alt,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageError(ThemeData theme, String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.image_off_24_regular,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageLoading() {
    return const Padding(
      padding: EdgeInsets.all(48),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  MarkdownStyleSheet _buildMarkdownStyleSheet(ThemeData theme) {
    final baseStyle = theme.textTheme.bodyMedium ?? const TextStyle();

    return MarkdownStyleSheet(
      p: baseStyle.copyWith(height: 1.6),
      h1: theme.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
      h2: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.onSurface,
      ),
      h3: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      h4: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      h5: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      h6: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      a: baseStyle.copyWith(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      code: TextStyle(
        fontFamily: 'Consolas',
        fontSize: 13,
        color: theme.colorScheme.onSurfaceVariant,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      codeblockPadding: const EdgeInsets.all(16),
      blockquote: baseStyle.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 4),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
      tableHead: baseStyle.copyWith(fontWeight: FontWeight.bold),
      tableBody: baseStyle,
      tableBorder: TableBorder.all(color: theme.dividerColor, width: 1),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      listBullet: baseStyle,
      listIndent: 24,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
      ),
    );
  }
}
