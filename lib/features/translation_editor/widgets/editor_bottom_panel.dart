import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/widgets/editor_history_panel.dart';
import 'package:twmt/features/translation_editor/widgets/editor_validation_panel.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Bottom panel with tabs for TM suggestions, history, and validation
///
/// Resizable panel showing contextual information for selected translation
class EditorBottomPanel extends ConsumerStatefulWidget {
  final String? selectedUnitId;
  final String? selectedVersionId;
  final String sourceLanguageCode;
  final String targetLanguageCode;
  final String? sourceText;
  final String? translatedText;
  /// Callback when applying a TM suggestion
  /// Parameters: unitId, targetText, isExactMatch
  final Function(String unitId, String targetText, bool isExactMatch)? onApplySuggestion;

  const EditorBottomPanel({
    super.key,
    this.selectedUnitId,
    this.selectedVersionId,
    required this.sourceLanguageCode,
    required this.targetLanguageCode,
    this.sourceText,
    this.translatedText,
    this.onApplySuggestion,
  });

  @override
  ConsumerState<EditorBottomPanel> createState() => _EditorBottomPanelState();
}

class _EditorBottomPanelState extends ConsumerState<EditorBottomPanel>
  with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _hoveredMatchId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Tab bar
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(
                  icon: Icon(FluentIcons.lightbulb_24_regular, size: 16),
                  text: 'TM Suggestions',
                ),
                Tab(
                  icon: Icon(FluentIcons.history_24_regular, size: 16),
                  text: 'History',
                ),
                Tab(
                  icon: Icon(FluentIcons.warning_24_regular, size: 16),
                  text: 'Validation',
                ),
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTmSuggestionsTab(),
                _buildHistoryTab(),
                _buildValidationTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTmSuggestionsTab() {
    if (widget.selectedUnitId == null) {
      return _buildEmptyState(
        icon: FluentIcons.lightbulb_24_regular,
        message: 'Select a translation unit to view TM suggestions',
      );
    }

    // Watch TM suggestions for the selected unit
    final suggestionsAsync = ref.watch(
      tmSuggestionsForUnitProvider(
        widget.selectedUnitId!,
        widget.sourceLanguageCode,
        widget.targetLanguageCode,
      ),
    );

    return suggestionsAsync.when(
      data: (matches) => _buildTmSuggestionsList(matches),
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (error, stack) => _buildEmptyState(
        icon: FluentIcons.error_circle_24_regular,
        message: 'Error loading TM suggestions: ${error.toString()}',
      ),
    );
  }

  Widget _buildTmSuggestionsList(List<TmMatch> matches) {
    if (matches.isEmpty) {
      return _buildEmptyState(
        icon: FluentIcons.lightbulb_24_regular,
        message: 'No TM suggestions found',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: matches.length,
      separatorBuilder: (context, index) => const Divider(height: 24),
      itemBuilder: (context, index) {
        final match = matches[index];
        return _buildTmSuggestionCard(match);
      },
    );
  }

  Widget _buildTmSuggestionCard(TmMatch match) {
    final similarity = (match.similarityScore * 100).round();
    final color = _getSimilarityColor(match.similarityScore);
    final isHovered = _hoveredMatchId == match.entryId;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredMatchId = match.entryId),
      onExit: (_) => setState(() => _hoveredMatchId = null),
      child: GestureDetector(
        onTap: () {
          // Apply suggestion if callback is provided
          if (widget.onApplySuggestion != null && widget.selectedUnitId != null) {
            widget.onApplySuggestion!(
              widget.selectedUnitId!,
              match.targetText,
              match.matchType == TmMatchType.exact,
            );

            // Show confirmation toast
            FluentToast.success(context, 'Applied TM suggestion ($similarity% match)');
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isHovered
                ? color.withValues(alpha: 0.1)
                : color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isHovered
                  ? color.withValues(alpha: 0.5)
                  : color.withValues(alpha: 0.3),
              width: isHovered ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with similarity score
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$similarity% Match',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getMatchTypeLabel(match.matchType),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    FluentIcons.arrow_download_24_regular,
                    size: 16,
                    color: color,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Source text
              Text(
                match.sourceText,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),

              // Target text
              Text(
                match.targetText,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),

              // Metadata
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        FluentIcons.clock_24_regular,
                        size: 12,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timeago.format(match.lastUsedAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        FluentIcons.arrow_repeat_all_24_regular,
                        size: 12,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Used ${match.usageCount} times',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSimilarityColor(double similarity) {
    if (similarity >= 0.90) return Colors.green;
    if (similarity >= 0.80) return Colors.orange;
    return Colors.red;
  }

  String _getMatchTypeLabel(TmMatchType type) {
    switch (type) {
      case TmMatchType.exact:
        return 'Exact Match';
      case TmMatchType.fuzzy:
        return 'Fuzzy Match';
      case TmMatchType.context:
        return 'Context Match';
    }
  }

  Widget _buildHistoryTab() {
    return EditorHistoryPanel(
      selectedVersionId: widget.selectedVersionId,
      onRevert: (translatedText, reason) {
        // Handle revert - this would need to be wired up to the parent
        if (widget.onApplySuggestion != null && widget.selectedUnitId != null) {
          // History reverts are treated as manual edits
          widget.onApplySuggestion!(widget.selectedUnitId!, translatedText, false);
        }
      },
    );
  }

  Widget _buildValidationTab() {
    if (widget.selectedUnitId == null || widget.sourceText == null) {
      return _buildEmptyState(
        icon: FluentIcons.warning_24_regular,
        message: 'Select a translation unit to view validation results',
      );
    }

    return EditorValidationPanel(
      sourceText: widget.sourceText,
      translatedText: widget.translatedText,
      onApplyFix: (fixedText) {
        // Handle auto-fix
        if (widget.onApplySuggestion != null && widget.selectedUnitId != null) {
          // Validation fixes are treated as manual edits
          widget.onApplySuggestion!(widget.selectedUnitId!, fixedText, false);
        }
      },
      onValidate: () {
        // Handle validation
        // This would mark the translation as validated
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 48,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
