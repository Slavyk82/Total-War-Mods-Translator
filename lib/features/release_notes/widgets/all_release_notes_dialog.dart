import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../models/domain/github_release.dart';
import 'release_notes_dialog.dart';

/// Token-themed popup showing all release notes in reverse chronological order.
class AllReleaseNotesDialog extends StatelessWidget {
  final List<GitHubRelease> releases;

  const AllReleaseNotesDialog({
    super.key,
    required this.releases,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return TokenDialog(
      icon: FluentIcons.history_24_regular,
      title: t.releaseNotes.dialogs.releaseHistory.title,
      subtitle: releases.length == 1
          ? t.releaseNotes.dialogs.releaseHistory.subtitleOne(count: releases.length)
          : t.releaseNotes.dialogs.releaseHistory.subtitleMany(count: releases.length),
      width: 760,
      body: SizedBox(
        height: 560,
        child: releases.isEmpty
            ? _buildEmptyState(tokens)
            : _buildReleasesList(tokens),
      ),
      actions: [
        SmallTextButton(
          label: t.releaseNotes.actions.gotIt,
          filled: true,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildEmptyState(TwmtThemeTokens tokens) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.document_dismiss_24_regular,
            size: 48,
            color: tokens.textFaint,
          ),
          const SizedBox(height: 12),
          Text(
            t.releaseNotes.dialogs.releaseHistory.noNotes,
            style: tokens.fontBody.copyWith(
              fontSize: 14,
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleasesList(TwmtThemeTokens tokens) {
    return ListView.separated(
      itemCount: releases.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _ReleaseExpansionTile(
          release: releases[index],
          isFirst: index == 0,
        );
      },
    );
  }
}

class _ReleaseExpansionTile extends StatefulWidget {
  final GitHubRelease release;
  final bool isFirst;

  const _ReleaseExpansionTile({
    required this.release,
    required this.isFirst,
  });

  @override
  State<_ReleaseExpansionTile> createState() => _ReleaseExpansionTileState();
}

class _ReleaseExpansionTileState extends State<_ReleaseExpansionTile> {
  late bool _isExpanded;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isFirst;
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
    final tokens = context.tokens;
    final release = widget.release;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _isExpanded ? tokens.panel2 : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(
          color: _isExpanded ? tokens.border : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: GestureDetector(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isHovered && !_isExpanded
                      ? tokens.accentBg
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: _isExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        FluentIcons.chevron_right_24_regular,
                        size: 16,
                        color: tokens.textDim,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: widget.isFirst
                            ? tokens.ok.withValues(alpha: 0.1)
                            : tokens.accentBg,
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                      ),
                      child: Text(
                        'v${release.version}',
                        style: tokens.fontBody.copyWith(
                          fontSize: 11.5,
                          color:
                              widget.isFirst ? tokens.ok : tokens.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        release.name.isNotEmpty
                            ? release.name
                            : t.releaseNotes.dialogs.whatsNew.releasePrefix(version: release.version),
                        style: tokens.fontBody.copyWith(
                          fontSize: 13,
                          color: tokens.text,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _formatDate(release.publishedAt),
                      style: tokens.fontBody.copyWith(
                        fontSize: 12,
                        color: tokens.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(42, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(height: 1, color: tokens.border),
                  const SizedBox(height: 12),
                  MarkdownBody(
                    data: release.body.isNotEmpty
                        ? release.body
                        : t.releaseNotes.dialogs.releaseHistory.noReleasesAvailable,
                    selectable: true,
                    shrinkWrap: true,
                    onTapLink: (_, href, _) => _handleLinkTap(href),
                    styleSheet: buildTokenMarkdownStyleSheet(tokens),
                  ),
                  const SizedBox(height: 10),
                  SmallTextButton(
                    label: t.releaseNotes.actions.viewOnGitHub,
                    icon: FluentIcons.open_24_regular,
                    onTap: () => _handleLinkTap(release.htmlUrl),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
