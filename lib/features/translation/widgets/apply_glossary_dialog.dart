import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Dialog for applying glossary terms to selected units
///
/// Features:
/// - Glossary selection dropdown
/// - Preview of matched terms and suggested translations
/// - Options for case-sensitive matching, overwrite existing, etc.
/// - Shows units where glossary terms were found
/// - Highlights matched terms in source text
class ApplyGlossaryDialog extends ConsumerStatefulWidget {
  const ApplyGlossaryDialog({
    super.key,
    required this.selectedCount,
    required this.availableGlossaries,
    required this.onApply,
  });

  final int selectedCount;
  final List<GlossaryInfo> availableGlossaries;
  final Function({
    required String glossaryId,
    required bool applyToUntranslatedOnly,
    required bool caseSensitive,
    required bool overwriteExisting,
  }) onApply;

  @override
  ConsumerState<ApplyGlossaryDialog> createState() => _ApplyGlossaryDialogState();
}

class _ApplyGlossaryDialogState extends ConsumerState<ApplyGlossaryDialog> {
  String? _selectedGlossaryId;
  bool _applyToUntranslatedOnly = true;
  bool _caseSensitive = false;
  bool _overwriteExisting = false;

  // Mock preview data - in real implementation, this would come from a service
  final List<GlossaryMatch> _previewMatches = [
    GlossaryMatch(
      unitKey: 'units_name_wh_main_emp_inf_greatswords',
      sourceText: 'Greatswords are elite infantry armed with Zweihänder',
      matchedTerm: 'Greatswords',
      suggestedTranslation: 'Grandes Épées',
    ),
    GlossaryMatch(
      unitKey: 'units_name_wh_main_emp_cav_empire_knights',
      sourceText: 'Empire Knights charge into battle with lances',
      matchedTerm: 'Empire Knights',
      suggestedTranslation: 'Chevaliers de l\'Empire',
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.availableGlossaries.isNotEmpty) {
      _selectedGlossaryId = widget.availableGlossaries.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  FluentIcons.book_24_regular,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Apply Glossary to ${widget.selectedCount} Units',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      FluentIcons.dismiss_24_regular,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Glossary selection
                    Text(
                      'Select Glossary',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildGlossaryDropdown(),
                    const SizedBox(height: 20),

                    // Options
                    Text(
                      'Options',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildOptions(),
                    const SizedBox(height: 20),

                    // Preview section
                    Text(
                      'Preview (${_previewMatches.length} matches found)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildPreview(),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Results summary
            if (_previewMatches.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.info_24_regular,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_previewMatches.length} terms found • '
                        '${_previewMatches.length} units will be affected',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                _buildButton(
                  label: 'Apply',
                  icon: FluentIcons.checkmark_24_regular,
                  isPrimary: true,
                  onPressed: _selectedGlossaryId != null ? _performApply : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlossaryDropdown() {
    if (widget.availableGlossaries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              FluentIcons.warning_24_regular,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text(
              'No glossaries available',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButton<String>(
        value: _selectedGlossaryId,
        isExpanded: true,
        underline: const SizedBox(),
        items: widget.availableGlossaries.map((glossary) {
          return DropdownMenuItem(
            value: glossary.id,
            child: Row(
              children: [
                Icon(
                  FluentIcons.book_24_regular,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        glossary.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (glossary.description != null)
                        Text(
                          glossary.description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${glossary.termCount} terms',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) => setState(() => _selectedGlossaryId = value),
      ),
    );
  }

  Widget _buildOptions() {
    return Column(
      children: [
        _buildCheckbox(
          label: 'Apply to untranslated only',
          value: _applyToUntranslatedOnly,
          onChanged: (value) => setState(() => _applyToUntranslatedOnly = value!),
          description: 'Skip units that already have translations',
        ),
        const SizedBox(height: 8),
        _buildCheckbox(
          label: 'Case-sensitive matching',
          value: _caseSensitive,
          onChanged: (value) => setState(() => _caseSensitive = value!),
          description: 'Match terms exactly as they appear',
        ),
        const SizedBox(height: 8),
        _buildCheckbox(
          label: 'Overwrite existing translations',
          value: _overwriteExisting,
          onChanged: (value) => setState(() => _overwriteExisting = value!),
          description: 'Replace existing translations with glossary terms',
        ),
      ],
    );
  }

  Widget _buildCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
    String? description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              if (description != null)
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    if (_previewMatches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                FluentIcons.search_24_regular,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                'No glossary matches found',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _previewMatches.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: Theme.of(context).dividerColor,
        ),
        itemBuilder: (context, index) {
          final match = _previewMatches[index];
          return _buildMatchItem(match);
        },
      ),
    );
  }

  Widget _buildMatchItem(GlossaryMatch match) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            match.unitKey,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              children: _highlightMatchedTerm(match.sourceText, match.matchedTerm),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                FluentIcons.arrow_right_24_regular,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                match.suggestedTranslation,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<TextSpan> _highlightMatchedTerm(String text, String term) {
    final List<TextSpan> spans = [];
    final lowerText = text.toLowerCase();
    final lowerTerm = term.toLowerCase();

    int currentIndex = 0;
    int matchIndex = lowerText.indexOf(lowerTerm, currentIndex);

    while (matchIndex != -1) {
      // Add text before match
      if (matchIndex > currentIndex) {
        spans.add(TextSpan(text: text.substring(currentIndex, matchIndex)));
      }

      // Add highlighted match
      spans.add(TextSpan(
        text: text.substring(matchIndex, matchIndex + term.length),
        style: TextStyle(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ));

      currentIndex = matchIndex + term.length;
      matchIndex = lowerText.indexOf(lowerTerm, currentIndex);
    }

    // Add remaining text
    if (currentIndex < text.length) {
      spans.add(TextSpan(text: text.substring(currentIndex)));
    }

    return spans;
  }

  Widget _buildButton({
    required String label,
    IconData? icon,
    bool isPrimary = false,
    VoidCallback? onPressed,
  }) {
    if (isPrimary) {
      return FluentButton(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon) : null,
        child: Text(label),
      );
    } else {
      return FluentTextButton(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon) : null,
        child: Text(label),
      );
    }
  }

  void _performApply() {
    if (_selectedGlossaryId == null) return;

    widget.onApply(
      glossaryId: _selectedGlossaryId!,
      applyToUntranslatedOnly: _applyToUntranslatedOnly,
      caseSensitive: _caseSensitive,
      overwriteExisting: _overwriteExisting,
    );

    Navigator.of(context).pop();
  }
}

/// Information about a glossary
class GlossaryInfo {
  final String id;
  final String name;
  final String? description;
  final int termCount;

  const GlossaryInfo({
    required this.id,
    required this.name,
    this.description,
    required this.termCount,
  });
}

/// Represents a glossary match in the preview
class GlossaryMatch {
  final String unitKey;
  final String sourceText;
  final String matchedTerm;
  final String suggestedTranslation;

  const GlossaryMatch({
    required this.unitKey,
    required this.sourceText,
    required this.matchedTerm,
    required this.suggestedTranslation,
  });
}
