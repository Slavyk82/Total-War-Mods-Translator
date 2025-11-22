import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Dialog shown when no LLM provider is configured
///
/// Prompts user to configure a provider before translating
/// Uses Fluent Design patterns (no Material ripple effects)
class ProviderSetupDialog extends StatelessWidget {
  const ProviderSetupDialog({
    super.key,
    required this.onGoToSettings,
  });

  final VoidCallback onGoToSettings;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            _buildContent(context),
            const SizedBox(height: 24),
            _buildProviderList(context),
            const SizedBox(height: 24),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          FluentIcons.warning_24_regular,
          size: 24,
          color: Colors.orange,
        ),
        const SizedBox(width: 12),
        Text(
          'No Translation Provider Configured',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return Text(
      'To use automatic translation, you need to configure at least one LLM provider. '
      'Please go to Settings and set up one of the following providers:',
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  Widget _buildProviderList(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          _buildProviderItem(
            context: context,
            icon: FluentIcons.brain_circuit_24_regular,
            name: 'Anthropic Claude',
            description: 'High-quality translations with context awareness',
          ),
          const SizedBox(height: 12),
          _buildProviderItem(
            context: context,
            icon: FluentIcons.bot_24_regular,
            name: 'OpenAI GPT',
            description: 'Versatile language model with good translations',
          ),
          const SizedBox(height: 12),
          _buildProviderItem(
            context: context,
            icon: FluentIcons.translate_24_regular,
            name: 'DeepL',
            description: 'Specialized translation service',
          ),
        ],
      ),
    );
  }

  Widget _buildProviderItem({
    required BuildContext context,
    required IconData icon,
    required String name,
    required String description,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).primaryColor,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildActionButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
          isPrimary: false,
        ),
        const SizedBox(width: 12),
        _buildActionButton(
          label: 'Go to Settings',
          icon: FluentIcons.settings_24_regular,
          onPressed: () {
            Navigator.of(context).pop();
            onGoToSettings();
          },
          isPrimary: true,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    IconData? icon,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isPrimary
              ? const Color(0xFF0078D4)
              : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: isPrimary ? Colors.white : Colors.black87,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isPrimary ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
