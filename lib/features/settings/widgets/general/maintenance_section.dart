import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'settings_section_header.dart';
import '../../providers/maintenance_providers.dart';

/// Database maintenance section for settings.
///
/// Provides actions to maintain and fix database statistics,
/// such as reanalyzing all translations to detect untranslated units.
class MaintenanceSection extends ConsumerWidget {
  const MaintenanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maintenanceState = ref.watch(maintenanceStateProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Database Maintenance',
          subtitle:
              'Tools to maintain and fix database statistics and translation states.',
        ),
        const SizedBox(height: 16),
        _buildMaintenanceCard(context, ref, maintenanceState, theme),
      ],
    );
  }

  Widget _buildMaintenanceCard(
    BuildContext context,
    WidgetRef ref,
    MaintenanceState state,
    ThemeData theme,
  ) {
    final isRunning = state.isReanalyzing;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.dividerColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.wrench_24_regular,
                size: 24,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Maintenance Actions',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.lastResult != null) ...[
            _buildResultMessage(context, state.lastResult!, theme),
            const SizedBox(height: 16),
          ],
          if (isRunning) ...[
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  state.progressMessage ?? 'Processing...',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ] else ...[
            _buildActionRow(
              context,
              ref,
              theme,
              icon: FluentIcons.arrow_sync_24_regular,
              title: 'Reanalyze Translations',
              description: 'Fix status inconsistencies and detect untranslated units',
              onTap: () => _runReanalysis(ref),
              isPrimary: true,
            ),
            const SizedBox(height: 12),
            _buildActionRow(
              context,
              ref,
              theme,
              icon: FluentIcons.delete_24_regular,
              title: 'Clear Mod Update Cache',
              description: 'Remove stale "pending changes" badges',
              onTap: () => _clearCache(ref),
              isPrimary: false,
            ),
            const SizedBox(height: 12),
            _buildActionRow(
              context,
              ref,
              theme,
              icon: FluentIcons.database_24_regular,
              title: 'Rebuild Translation Memory',
              description: 'Recover missing TM entries from existing translations',
              onTap: () => _rebuildTranslationMemory(ref),
              isPrimary: false,
            ),
            const SizedBox(height: 12),
            _buildActionRow(
              context,
              ref,
              theme,
              icon: FluentIcons.arrow_sync_24_regular,
              title: 'Migrate Legacy TM Hashes',
              description: 'Convert old integer hashes to SHA256 for TM lookup',
              onTap: () => _migrateLegacyHashes(ref),
              isPrimary: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionRow(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isPrimary
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isPrimary
                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                  : theme.dividerColor,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isPrimary
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                FluentIcons.chevron_right_24_regular,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultMessage(
    BuildContext context,
    MaintenanceResult result,
    ThemeData theme,
  ) {
    final isSuccess = result.success;
    final color = isSuccess ? Colors.green : theme.colorScheme.error;
    final icon = isSuccess
        ? FluentIcons.checkmark_circle_24_regular
        : FluentIcons.error_circle_24_regular;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              result.message,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  void _runReanalysis(WidgetRef ref) {
    ref.read(maintenanceStateProvider.notifier).reanalyzeAllTranslations();
  }

  void _clearCache(WidgetRef ref) {
    ref.read(maintenanceStateProvider.notifier).clearStaleAnalysisCache();
  }

  void _rebuildTranslationMemory(WidgetRef ref) {
    ref.read(maintenanceStateProvider.notifier).rebuildTranslationMemory();
  }

  void _migrateLegacyHashes(WidgetRef ref) {
    ref.read(maintenanceStateProvider.notifier).migrateLegacyHashes();
  }
}
