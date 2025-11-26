import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../models/search_query_model.dart';
import '../providers/search_providers.dart';

/// Search query builder widget
///
/// Provides UI for building search queries with operators and options.
class SearchQueryBuilder extends ConsumerStatefulWidget {
  const SearchQueryBuilder({super.key});

  @override
  ConsumerState<SearchQueryBuilder> createState() =>
      _SearchQueryBuilderState();
}

class _SearchQueryBuilderState extends ConsumerState<SearchQueryBuilder> {
  final _textController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    final query = ref.read(searchQueryProvider);
    _textController.text = query.text;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        ref.read(searchQueryProvider.notifier).updateText(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final notifier = ref.read(searchQueryProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Query text input
        TextFormField(
          controller: _textController,
          decoration: const InputDecoration(
            hintText: 'Search in translations...',
            prefixIcon: Icon(FluentIcons.search_24_regular),
            border: OutlineInputBorder(),
          ),
          onChanged: _onTextChanged,
          onFieldSubmitted: (value) {
            // Cancel debounce and search immediately on Enter
            _debounceTimer?.cancel();
            notifier.updateText(value);
          },
          validator: (value) {
            if (value == null || value.trim().length < 2) {
              return 'Search query must be at least 2 characters';
            }
            return null;
          },
        ),

        const SizedBox(height: 16),

        // Search scope radio buttons
        const Text(
          'Search in:',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: SearchScope.values.map((scope) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ignore: deprecated_member_use
                Radio<SearchScope>(
                  value: scope,
                  // ignore: deprecated_member_use
                  groupValue: query.scope,
                  // ignore: deprecated_member_use
                  onChanged: (value) {
                    if (value != null) {
                      notifier.updateScope(value);
                    }
                  },
                ),
                Text(scope.displayName),
              ],
            );
          }).toList(),
        ),

        const SizedBox(height: 16),

        // Operator and quick options
        Row(
          children: [
            // Operator dropdown
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Operator:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<SearchOperator>(
                    initialValue: query.operator,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: SearchOperator.values.map((op) {
                      return DropdownMenuItem(
                        value: op,
                        child: Text(op.displayName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        notifier.updateOperator(value);
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // Quick options checkboxes
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick options:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _buildCheckbox(
                        label: 'Phrase "..."',
                        value: query.options.phraseSearch,
                        onChanged: (value) {
                          notifier.updateOptions(
                            query.options.copyWith(phraseSearch: value),
                          );
                        },
                      ),
                      _buildCheckbox(
                        label: 'Prefix *',
                        value: query.options.prefixSearch,
                        onChanged: (value) {
                          notifier.updateOptions(
                            query.options.copyWith(prefixSearch: value),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
        ),
        Text(label),
      ],
    );
  }
}
