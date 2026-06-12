import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/app_constants.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/utils/pack_prefix_sanitizer.dart';
import 'settings_section_header.dart';

/// Settings section to customize the load-order prefix used when generating
/// .pack files and the .loc files inside them.
class PackPrefixSection extends ConsumerStatefulWidget {
  final String initialPrefix;

  const PackPrefixSection({super.key, required this.initialPrefix});

  @override
  ConsumerState<PackPrefixSection> createState() => _PackPrefixSectionState();
}

class _PackPrefixSectionState extends ConsumerState<PackPrefixSection> {
  late final TextEditingController _controller;
  late String _preview;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPrefix);
    _preview = _controller.text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(String value) async {
    // Sanitize locally so the live preview shows exactly what will be stored.
    // The notifier's updatePackPrefix re-sanitizes authoritatively on persist.
    final clean = sanitizePackPrefix(value);
    setState(() => _preview = clean);
    await ref.read(generalSettingsProvider.notifier).updatePackPrefix(clean);
  }

  void _reset() {
    _controller.text = AppConstants.defaultPackPrefix;
    unawaited(_save(AppConstants.defaultPackPrefix));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final prefix = _preview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(
          title: t.settings.general.packPrefix.sectionTitle,
          subtitle: t.settings.general.packPrefix.sectionSubtitle,
        ),
        const SizedBox(height: 12),
        _buildWarning(context),
        const SizedBox(height: 16),
        Text(
          t.settings.general.packPrefix.fieldLabel,
          style: tokens.fontBody.copyWith(
            fontSize: 14,
            color: tokens.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SmallTextButton(
              label: t.settings.general.packPrefix.resetButton,
              icon: FluentIcons.arrow_reset_24_regular,
              onTap: _reset,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: AppConstants.defaultPackPrefix,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: _save,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          t.settings.general.packPrefix.previewLabel,
          style: tokens.fontBody.copyWith(
            fontSize: 12,
            color: tokens.textDim,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          '${prefix}_fr_twmt_mod.pack',
          style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
        ),
        SelectableText(
          'text/db/${prefix}_fr_twmt_text.loc',
          style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
        ),
      ],
    );
  }

  Widget _buildWarning(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.warnBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.warn.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FluentIcons.warning_24_regular, size: 18, color: tokens.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.settings.general.packPrefix.warning,
              style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.text),
            ),
          ),
        ],
      ),
    );
  }
}
