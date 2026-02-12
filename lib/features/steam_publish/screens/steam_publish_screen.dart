import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';

import '../providers/steam_publish_providers.dart';
import '../widgets/pack_export_list.dart';

class SteamPublishScreen extends ConsumerStatefulWidget {
  const SteamPublishScreen({super.key});

  @override
  ConsumerState<SteamPublishScreen> createState() =>
      _SteamPublishScreenState();
}

class _SteamPublishScreenState extends ConsumerState<SteamPublishScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncExports = ref.watch(recentPackExportsProvider);

    return FluentScaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      header: FluentHeader(
        title: 'Publish on Steam',
        actions: [
          Tooltip(
            message: 'Refresh',
            child: IconButton(
              icon: const Icon(FluentIcons.arrow_sync_24_regular, size: 20),
              onPressed: () {
                ref.invalidate(recentPackExportsProvider);
              },
            ),
          ),
        ],
      ),
      body: asyncExports.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                FluentIcons.error_circle_24_regular,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load recent exports',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  ref.invalidate(recentPackExportsProvider);
                },
                icon: const Icon(FluentIcons.arrow_sync_24_regular, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (exports) {
          if (exports.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    FluentIcons.box_24_regular,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No pack exports yet',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Export a project as .pack to see it here.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            );
          }

          return PackExportList(exports: exports);
        },
      ),
    );
  }
}
