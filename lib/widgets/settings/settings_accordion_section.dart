import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/status_pill.dart';

/// Reusable accordion section used by Settings (Ignored Source Texts,
/// LLM Custom Rules, LLM Provider) — clickable header + animated body.
class SettingsAccordionSection extends StatefulWidget {
  const SettingsAccordionSection({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.activeCount,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final int? activeCount;
  final bool initiallyExpanded;

  @override
  State<SettingsAccordionSection> createState() =>
      _SettingsAccordionSectionState();
}

class _SettingsAccordionSectionState extends State<SettingsAccordionSection> {
  late bool _isExpanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Column(
        children: [
          _buildHeader(tokens),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: widget.child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(TwmtThemeTokens tokens) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isExpanded ? tokens.panel2 : Colors.transparent,
            borderRadius: _isExpanded
                ? BorderRadius.vertical(top: Radius.circular(tokens.radiusMd))
                : BorderRadius.circular(tokens.radiusMd),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 24, color: tokens.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: tokens.fontBody.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tokens.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: tokens.fontBody.copyWith(
                        fontSize: 12,
                        color: tokens.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              if ((widget.activeCount ?? 0) > 0) ...[
                StatusPill(
                  label: '${widget.activeCount} active',
                  foreground: tokens.accent,
                  background: tokens.accentBg,
                ),
                const SizedBox(width: 12),
              ],
              AnimatedRotation(
                turns: _isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  FluentIcons.chevron_down_24_regular,
                  size: 20,
                  color: tokens.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
