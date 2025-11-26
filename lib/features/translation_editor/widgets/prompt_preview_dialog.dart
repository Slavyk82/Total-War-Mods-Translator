import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../models/domain/translation_unit.dart';
import '../../../services/translation/models/translation_context.dart';
import '../../../services/translation/prompt_preview_service.dart';
import '../../../services/translation/i_prompt_builder_service.dart';
import '../../../services/service_locator.dart';
import '../../../widgets/fluent/fluent_widgets.dart';

/// Dialog for previewing the LLM prompt that will be sent for a translation unit
///
/// Displays the complete prompt including system instructions, context,
/// glossary terms, and the actual translation request.
class PromptPreviewDialog extends ConsumerStatefulWidget {
  final TranslationUnit unit;
  final TranslationContext context;

  const PromptPreviewDialog({
    super.key,
    required this.unit,
    required this.context,
  });

  @override
  ConsumerState<PromptPreviewDialog> createState() => _PromptPreviewDialogState();
}

class _PromptPreviewDialogState extends ConsumerState<PromptPreviewDialog>
    with SingleTickerProviderStateMixin {
  PromptPreview? _preview;
  bool _isLoading = true;
  String? _error;
  late TabController _tabController;
  int _selectedProviderIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPreview();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final promptBuilder = ServiceLocator.get<IPromptBuilderService>();
      final previewService = PromptPreviewService(promptBuilder);

      final result = await previewService.buildPreview(
        unit: widget.unit,
        context: widget.context,
      );

      result.when(
        ok: (preview) {
          if (mounted) {
            // Find index of current provider to select it by default
            final currentProviderIndex = preview.providerPayloads.indexWhere(
              (p) => p.providerCode == preview.providerCode,
            );
            setState(() {
              _preview = preview;
              _selectedProviderIndex = currentProviderIndex >= 0 ? currentProviderIndex : 0;
              _isLoading = false;
            });
          }
        },
        err: (error) {
          if (mounted) {
            setState(() {
              _error = error;
              _isLoading = false;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 900,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildUnitInfo(),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Expanded(
              child: _buildContent(),
            ),
            const SizedBox(height: 16),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(
          FluentIcons.code_24_regular,
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Prompt Preview',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'View the exact prompt that will be sent to the LLM',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ],
          ),
        ),
        if (_preview != null) ...[
          _buildMetadataBadge(
            icon: FluentIcons.server_24_regular,
            label: _preview!.providerPayloads.isNotEmpty
                ? _preview!.providerPayloads[_selectedProviderIndex].providerName
                : _preview!.providerCode,
          ),
          const SizedBox(width: 8),
          _buildMetadataBadge(
            icon: FluentIcons.document_24_regular,
            label: '~${_preview!.estimatedTokens} tokens',
          ),
          const SizedBox(width: 16),
        ],
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(8),
              child: const Icon(
                FluentIcons.dismiss_24_regular,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.blue.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            FluentIcons.document_text_24_regular,
            size: 16,
            color: Colors.blue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Key: ${widget.unit.key}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.unit.sourceText.length > 100
                      ? '${widget.unit.sourceText.substring(0, 100)}...'
                      : widget.unit.sourceText,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              FluentIcons.error_circle_24_regular,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Error building prompt preview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_preview == null) {
      return const Center(
        child: Text('No preview available'),
      );
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'System Prompt'),
            Tab(text: 'User Message'),
            Tab(text: 'API Payload'),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPromptSection(
                title: 'System Prompt',
                content: _preview!.systemMessage,
                description:
                    'Instructions, context, and glossary sent as the system message',
              ),
              _buildPromptSection(
                title: 'User Message',
                content: _preview!.userMessage,
                description: 'The actual translation request with source text',
              ),
              _buildApiPayloadSection(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildApiPayloadSection() {
    final payloads = _preview!.providerPayloads;
    if (payloads.isEmpty) {
      return _buildPromptSection(
        title: 'API Payload',
        content: _preview!.formattedPayload,
        description: 'Complete JSON payload',
        isJson: true,
      );
    }

    final selectedPayload = payloads[_selectedProviderIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Complete JSON payload as it would be sent to the provider',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            _buildProviderSelector(payloads),
            const SizedBox(width: 12),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _copyToClipboard(selectedPayload.payload, 'API Payload'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.copy_24_regular, size: 14),
                      SizedBox(width: 6),
                      Text('Copy', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Colors.grey.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                selectedPayload.payload,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  color: Colors.green.shade300,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProviderSelector(List<ProviderPayload> payloads) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: DropdownButton<int>(
        value: _selectedProviderIndex,
        underline: const SizedBox.shrink(),
        isDense: true,
        icon: const Icon(FluentIcons.chevron_down_16_regular, size: 14),
        style: const TextStyle(fontSize: 12),
        items: payloads.asMap().entries.map((entry) {
          return DropdownMenuItem<int>(
            value: entry.key,
            child: Text(
              entry.value.providerName,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          );
        }).toList(),
        onChanged: (index) {
          if (index != null) {
            setState(() {
              _selectedProviderIndex = index;
            });
          }
        },
      ),
    );
  }

  Widget _buildPromptSection({
    required String title,
    required String content,
    required String description,
    bool isJson = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _copyToClipboard(content, title),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.copy_24_regular, size: 14),
                      SizedBox(width: 6),
                      Text('Copy', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isJson
                  ? Colors.grey.shade900
                  : Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Colors.grey.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Consolas',
                  color: isJson ? Colors.green.shade300 : null,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _copyToClipboard(String content, String title) {
    Clipboard.setData(ClipboardData(text: content));
    FluentToast.success(context, '$title copied to clipboard');
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_preview != null)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _copyToClipboard(_preview!.fullPrompt, 'Full prompt'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.copy_24_regular, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Copy Full Prompt',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(width: 12),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Close',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

