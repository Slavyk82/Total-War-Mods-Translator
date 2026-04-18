import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/help_section.dart';

/// Widget that renders the markdown content of a single help section.
///
/// Uses `context.tokens` so typography and colours follow the active TWMT
/// theme (Atelier / Forge). Preserves the previous widget API and markdown
/// configuration — only styling changes.
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

    // Internal anchor links.
    if (href.startsWith('#')) {
      final anchor = href.substring(1);
      onNavigateToSection?.call(anchor);
      return;
    }

    // External links.
    final uri = Uri.tryParse(href);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      color: tokens.bg,
      child: SingleChildScrollView(
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
                tokens,
              ),
              styleSheet: _buildMarkdownStyleSheet(tokens),
            ),
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
    TwmtThemeTokens tokens,
  ) {
    final path = uri.toString();

    Widget imageWidget;

    // Limit width to 1000px max.
    const double maxWidth = 1000;
    final effectiveWidth = width != null && width < maxWidth ? width : maxWidth;

    if (path.startsWith('http://') || path.startsWith('https://')) {
      // Network image.
      imageWidget = Image.network(
        path,
        width: effectiveWidth,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildImageError(tokens, alt ?? 'Image failed to load');
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildImageLoading();
        },
      );
    } else {
      // Asset image.
      final assetPath = path.startsWith('assets/') ? path : 'assets/$path';
      imageWidget = Image.asset(
        assetPath,
        width: effectiveWidth,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildImageError(tokens, alt ?? path);
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
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.border, width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radiusSm - 1),
              child: imageWidget,
            ),
          ),
          if (alt != null && alt.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              alt,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textDim,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageError(TwmtThemeTokens tokens, String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tokens.errBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.image_off_24_regular,
            color: tokens.err,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              message,
              style: tokens.fontBody.copyWith(color: tokens.err),
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

  MarkdownStyleSheet _buildMarkdownStyleSheet(TwmtThemeTokens tokens) {
    final baseStyle = tokens.fontBody.copyWith(
      fontSize: 13,
      color: tokens.text,
    );

    final displayItalic = tokens.fontDisplayStyle;

    return MarkdownStyleSheet(
      p: baseStyle.copyWith(height: 1.6, color: tokens.textMid),
      h1: tokens.fontDisplay.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w500,
        color: tokens.accent,
        fontStyle: displayItalic,
      ),
      h2: tokens.fontDisplay.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: tokens.text,
        fontStyle: displayItalic,
      ),
      h3: tokens.fontDisplay.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: tokens.text,
        fontStyle: displayItalic,
      ),
      h4: tokens.fontDisplay.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: tokens.text,
        fontStyle: displayItalic,
      ),
      h5: tokens.fontBody.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: tokens.text,
      ),
      h6: tokens.fontBody.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: tokens.textMid,
      ),
      a: baseStyle.copyWith(
        color: tokens.accent,
        decoration: TextDecoration.underline,
        decorationColor: tokens.accent,
      ),
      code: tokens.fontMono.copyWith(
        fontSize: 12,
        color: tokens.text,
        backgroundColor: tokens.panel2,
      ),
      codeblockDecoration: BoxDecoration(
        color: tokens.panel2,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      codeblockPadding: const EdgeInsets.all(16),
      blockquote: baseStyle.copyWith(
        color: tokens.textDim,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: tokens.accent, width: 4),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
      tableHead: baseStyle.copyWith(fontWeight: FontWeight.bold),
      tableBody: baseStyle.copyWith(color: tokens.textMid),
      tableBorder: TableBorder.all(color: tokens.border, width: 1),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      listBullet: baseStyle.copyWith(color: tokens.textMid),
      listIndent: 24,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border, width: 1)),
      ),
    );
  }
}
