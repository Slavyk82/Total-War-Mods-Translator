import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../models/domain/github_release.dart';
import '../providers/release_notes_providers.dart';

/// Token-themed popup shown after app update, displaying release notes.
class ReleaseNotesDialog extends ConsumerWidget {
  final GitHubRelease release;

  const ReleaseNotesDialog({
    super.key,
    required this.release,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final content = release.body.isNotEmpty
        ? release.body
        : 'No release notes available for this version.';

    return TokenDialog(
      icon: FluentIcons.rocket_24_regular,
      title: "What's New",
      subtitle: release.name.isNotEmpty
          ? release.name
          : 'Release ${release.version}',
      width: 720,
      body: SizedBox(
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: tokens.ok.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Text(
                  'v${release.version}',
                  style: tokens.fontBody.copyWith(
                    fontSize: 11.5,
                    color: tokens.ok,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: tokens.border),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: MarkdownBody(
                  data: content,
                  selectable: true,
                  shrinkWrap: true,
                  onTapLink: (_, href, _) => _handleLinkTap(href),
                  styleSheet: buildTokenMarkdownStyleSheet(tokens),
                ),
              ),
            ),
          ],
        ),
      ),
      leadingActions: [
        SmallTextButton(
          label: 'View on GitHub',
          icon: FluentIcons.open_24_regular,
          onTap: () => _handleLinkTap(release.htmlUrl),
        ),
      ],
      actions: [
        SmallTextButton(
          label: 'Got it',
          icon: FluentIcons.checkmark_24_regular,
          filled: true,
          onTap: () => _dismissDialog(context, ref),
        ),
      ],
    );
  }

  void _dismissDialog(BuildContext context, WidgetRef ref) {
    ref.read(releaseNotesCheckerProvider.notifier).dismissReleaseNotes();
    Navigator.of(context).pop();
  }

  Future<void> _handleLinkTap(String? href) async {
    if (href == null) return;
    final uri = Uri.tryParse(href);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

/// Build a markdown stylesheet wired to token colors/fonts.
MarkdownStyleSheet buildTokenMarkdownStyleSheet(TwmtThemeTokens tokens) {
  final baseStyle = tokens.fontBody.copyWith(
    fontSize: 13,
    color: tokens.text,
  );

  return MarkdownStyleSheet(
    p: baseStyle.copyWith(height: 1.6),
    h1: tokens.fontDisplay.copyWith(
      fontSize: 22,
      color: tokens.accent,
      fontWeight: FontWeight.bold,
    ),
    h2: tokens.fontDisplay.copyWith(
      fontSize: 19,
      color: tokens.text,
      fontWeight: FontWeight.bold,
    ),
    h3: tokens.fontDisplay.copyWith(
      fontSize: 16,
      color: tokens.text,
      fontWeight: FontWeight.w600,
    ),
    h4: baseStyle.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    h5: baseStyle.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
    h6: baseStyle.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
    a: baseStyle.copyWith(
      color: tokens.accent,
      decoration: TextDecoration.underline,
    ),
    code: tokens.fontMono.copyWith(
      fontSize: 12.5,
      color: tokens.text,
      backgroundColor: tokens.panel2,
    ),
    codeblockDecoration: BoxDecoration(
      color: tokens.panel2,
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      border: Border.all(color: tokens.border),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    blockquote: baseStyle.copyWith(
      color: tokens.textDim,
      fontStyle: FontStyle.italic,
    ),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: tokens.accent, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
    tableHead: baseStyle.copyWith(fontWeight: FontWeight.bold),
    tableBody: baseStyle,
    tableBorder: TableBorder.all(color: tokens.border, width: 1),
    tableHeadAlign: TextAlign.left,
    tableCellsPadding: const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 8,
    ),
    listBullet: baseStyle,
    listIndent: 24,
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: tokens.border, width: 1)),
    ),
  );
}
