import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../providers/tm_providers.dart';

/// Filter panel for Translation Memory entries
class TmFilterPanel extends ConsumerWidget {
  const TmFilterPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterState = ref.watch(tmFilterStateProvider);

    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filters',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Quality filter
              Expanded(
                child: _FilterDropdown<QualityFilter>(
                  label: 'Quality',
                  value: filterState.qualityFilter,
                  items: QualityFilter.values,
                  itemLabel: _getQualityFilterLabel,
                  onChanged: (value) {
                    if (value != null) {
                      ref
                          .read(tmFilterStateProvider.notifier)
                          .setQualityFilter(value);
                    }
                  },
                ),
              ),

              const SizedBox(width: 12),

              // Target language
              Expanded(
                child: _LanguageDropdown(
                  label: 'Target Language',
                  value: filterState.targetLanguage,
                  onChanged: (value) {
                    ref
                        .read(tmFilterStateProvider.notifier)
                        .setTargetLanguage(value);
                  },
                ),
              ),

              const SizedBox(width: 12),

              // Game context
              Expanded(
                child: _GameContextDropdown(
                  value: filterState.gameContext,
                  onChanged: (value) {
                    ref
                        .read(tmFilterStateProvider.notifier)
                        .setGameContext(value);
                  },
                ),
              ),

              const SizedBox(width: 12),

              // Reset button
              FluentButton(
                onPressed: () {
                  ref.read(tmFilterStateProvider.notifier).reset();
                  ref.read(tmPageStateProvider.notifier).reset();
                },
                icon: const Icon(FluentIcons.arrow_reset_24_regular),
                child: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getQualityFilterLabel(QualityFilter filter) {
    switch (filter) {
      case QualityFilter.all:
        return 'All';
      case QualityFilter.highQuality:
        return 'High (≥90%)';
      case QualityFilter.mediumQuality:
        return 'Medium (70-89%)';
      case QualityFilter.lowQuality:
        return 'Low (<70%)';
      case QualityFilter.unused:
        return 'Unused';
    }
  }
}

/// Generic filter dropdown widget
class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final void Function(T?) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<T>(
          initialValue: value,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          items: items
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(itemLabel(item)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Language dropdown widget
class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final void Function(String?) onChanged;

  static const _languages = ['EN', 'FR', 'DE', 'ZH', 'ES', 'JA', 'RU'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: value,
          hint: const Text('All'),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('All'),
            ),
            ..._languages.map((lang) => DropdownMenuItem(
                  value: lang,
                  child: Text(lang),
                )),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Game context dropdown widget
class _GameContextDropdown extends StatelessWidget {
  const _GameContextDropdown({
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final void Function(String?) onChanged;

  static const _contexts = ['tw_warhammer_2', 'tw_warhammer_3', 'tw_three_kingdoms'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Game Context',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: value,
          hint: const Text('All'),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('All'),
            ),
            ..._contexts.map((ctx) => DropdownMenuItem(
                  value: ctx,
                  child: Text(ctx),
                )),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
