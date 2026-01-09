import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/domain/github_release.dart';
import '../../../widgets/fluent/fluent_widgets.dart';

/// Dialog showing all release notes in reverse chronological order.
class AllReleaseNotesDialog extends StatelessWidget {
  final List<GitHubRelease> releases;

  const AllReleaseNotesDialog({
    super.key,
    required this.releases,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 750,
          maxHeight: 700,
        ),
        child: Column(
          children: [
            _buildHeader(context, theme),
            const Divider(height: 1),
            Expanded(
              child: releases.isEmpty
                  ? _buildEmptyState(theme)
                  : _buildReleasesList(theme),
            ),
            const Divider(height: 1),
            _buildFooter(context, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              FluentIcons.history_24_regular,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Release History',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${releases.length} release${releases.length != 1 ? 's' : ''}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
          FluentIconButton(
            icon: const Icon(FluentIcons.dismiss_24_regular),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.document_dismiss_24_regular,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No release notes available',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleasesList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: releases.length,
      itemBuilder: (context, index) {
        final release = releases[index];
        return _ReleaseExpansionTile(
          release: release,
          isFirst: index == 0,
          theme: theme,
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _CloseButton(
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Expandable tile for a single release.
class _ReleaseExpansionTile extends StatefulWidget {
  final GitHubRelease release;
  final bool isFirst;
  final ThemeData theme;

  const _ReleaseExpansionTile({
    required this.release,
    required this.isFirst,
    required this.theme,
  });

  @override
  State<_ReleaseExpansionTile> createState() => _ReleaseExpansionTileState();
}

class _ReleaseExpansionTileState extends State<_ReleaseExpansionTile> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    // First release is expanded by default
    _isExpanded = widget.isFirst;
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _handleLinkTap(String? href) async {
    if (href == null) return;
    final uri = Uri.tryParse(href);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final release = widget.release;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isExpanded
              ? theme.colorScheme.surfaceContainerLow
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isExpanded
                ? theme.colorScheme.outlineVariant
                : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(theme, release),
            if (_isExpanded) _buildContent(theme, release),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, GitHubRelease release) {
    return _ExpansionHeader(
      isExpanded: _isExpanded,
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AnimatedRotation(
              turns: _isExpanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                FluentIcons.chevron_right_24_regular,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            // Version badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: widget.isFirst
                    ? const Color(0xFF107C10).withValues(alpha: 0.1)
                    : theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'v${release.version}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: widget.isFirst
                      ? const Color(0xFF107C10)
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                release.name.isNotEmpty
                    ? release.name
                    : 'Release ${release.version}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _formatDate(release.publishedAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, GitHubRelease release) {
    final content = release.body.isNotEmpty
        ? release.body
        : 'No release notes available for this version.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(44, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 16),
          MarkdownBody(
            data: content,
            selectable: true,
            shrinkWrap: true,
            onTapLink: (text, href, title) => _handleLinkTap(href),
            styleSheet: _buildMarkdownStyleSheet(theme),
          ),
          const SizedBox(height: 12),
          _ViewOnGitHubLink(url: release.htmlUrl),
        ],
      ),
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

/// Header widget with hover effect for expansion tiles.
class _ExpansionHeader extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onTap;
  final Widget child;

  const _ExpansionHeader({
    required this.isExpanded,
    required this.onTap,
    required this.child,
  });

  @override
  State<_ExpansionHeader> createState() => _ExpansionHeaderState();
}

class _ExpansionHeaderState extends State<_ExpansionHeader> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _isHovered && !widget.isExpanded
                ? theme.colorScheme.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Small link to view release on GitHub.
class _ViewOnGitHubLink extends StatefulWidget {
  final String url;

  const _ViewOnGitHubLink({required this.url});

  @override
  State<_ViewOnGitHubLink> createState() => _ViewOnGitHubLinkState();
}

class _ViewOnGitHubLinkState extends State<_ViewOnGitHubLink> {
  bool _isHovered = false;

  Future<void> _openUrl() async {
    final uri = Uri.tryParse(widget.url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _openUrl,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.open_16_regular,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'View on GitHub',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                decoration: _isHovered ? TextDecoration.underline : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Close button following Fluent Design.
class _CloseButton extends StatefulWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: _isPressed
                ? theme.colorScheme.primary.withValues(alpha: 0.8)
                : _isHovered
                    ? theme.colorScheme.primary.withValues(alpha: 0.9)
                    : theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Close',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
