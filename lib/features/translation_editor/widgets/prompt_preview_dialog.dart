import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../../../models/domain/translation_unit.dart';
import '../../../services/translation/models/translation_context.dart';
import '../../../services/translation/prompt_preview_service.dart';
import '../../../providers/shared/service_providers.dart';
import '../../../widgets/fluent/fluent_widgets.dart';

/// Token-themed popup previewing the LLM prompt for a translation unit.
class PromptPreviewDialog extends ConsumerStatefulWidget {
  final TranslationUnit unit;
  final TranslationContext context;

  const PromptPreviewDialog({
    super.key,
    required this.unit,
    required this.context,
  });

  @override
  ConsumerState<PromptPreviewDialog> createState() =>
      _PromptPreviewDialogState();
}

class _PromptPreviewDialogState extends ConsumerState<PromptPreviewDialog>
    with SingleTickerProviderStateMixin {
  PromptPreview? _preview;
  bool _isLoading = true;
  String? _error;
  late TabController _tabController;

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
      final promptBuilder = ref.read(promptBuilderServiceProvider);
      final previewService = PromptPreviewService(promptBuilder);

      final result = await previewService.buildPreview(
        unit: widget.unit,
        context: widget.context,
      );

      result.when(
        ok: (preview) {
          if (mounted) {
            setState(() {
              _preview = preview;
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
    final tokens = context.tokens;

    return TokenDialog(
      icon: FluentIcons.code_24_regular,
      title: 'Prompt Preview',
      subtitle: 'View the exact prompt that will be sent to the LLM',
      width: 900,
      body: SizedBox(
        height: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_preview != null) ...[
              Align(
                alignment: Alignment.centerRight,
                child: _MetadataBadge(
                  icon: FluentIcons.document_24_regular,
                  label: '~${_preview!.estimatedTokens} tokens',
                ),
              ),
              const SizedBox(height: 10),
            ],
            _buildUnitInfo(tokens),
            const SizedBox(height: 12),
            Divider(height: 1, color: tokens.border),
            const SizedBox(height: 12),
            Expanded(child: _buildContent(tokens)),
          ],
        ),
      ),
      actions: [
        if (_preview != null)
          SmallTextButton(
            label: 'Copy Full Prompt',
            icon: FluentIcons.copy_24_regular,
            onTap: () =>
                _copyToClipboard(_preview!.fullPrompt, 'Full prompt'),
          ),
        SmallTextButton(
          label: 'Close',
          filled: true,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildUnitInfo(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.infoBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.info.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FluentIcons.document_text_24_regular,
            size: 16,
            color: tokens.info,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Key: ${widget.unit.key}',
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.unit.sourceText.length > 100
                      ? '${widget.unit.sourceText.substring(0, 100)}...'
                      : widget.unit.sourceText,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12,
                    color: tokens.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(TwmtThemeTokens tokens) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: tokens.accent),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.error_circle_24_regular,
              size: 48,
              color: tokens.err,
            ),
            const SizedBox(height: 16),
            Text(
              'Error building prompt preview',
              style: tokens.fontBody.copyWith(
                fontSize: 14,
                color: tokens.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.textDim,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_preview == null) {
      return Center(
        child: Text(
          'No preview available',
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.textDim,
          ),
        ),
      );
    }

    return Column(
      children: [
        Theme(
          data: Theme.of(context).copyWith(
            tabBarTheme: TabBarThemeData(
              labelColor: tokens.accent,
              unselectedLabelColor: tokens.textDim,
              dividerColor: tokens.border,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(color: tokens.accent, width: 2),
              ),
              overlayColor: WidgetStatePropertyAll(tokens.accentBg),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'System Prompt'),
              Tab(text: 'User Message'),
              Tab(text: 'API Payload'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPromptSection(
                tokens: tokens,
                title: 'System Prompt',
                content: _preview!.systemMessage,
                description:
                    'Instructions, context, and glossary sent as the system message',
              ),
              _buildPromptSection(
                tokens: tokens,
                title: 'User Message',
                content: _preview!.userMessage,
                description:
                    'The actual translation request with source text',
              ),
              _buildApiPayloadSection(tokens),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildApiPayloadSection(TwmtThemeTokens tokens) {
    final payloads = _preview!.providerPayloads;
    final content =
        payloads.isEmpty ? _preview!.formattedPayload : payloads.first.payload;
    return _buildPromptSection(
      tokens: tokens,
      title: 'API Payload',
      content: content,
      description:
          'Complete JSON payload as it would be sent to the provider',
      isJson: true,
    );
  }

  Widget _buildPromptSection({
    required TwmtThemeTokens tokens,
    required String title,
    required String content,
    required String description,
    bool isJson = false,
  }) {
    final bgColor = isJson ? const Color(0xFF1E1E1E) : tokens.panel2;
    final textColor = isJson ? const Color(0xFF9CDCFE) : tokens.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                description,
                style: tokens.fontBody.copyWith(
                  fontSize: 12,
                  color: tokens.textDim,
                ),
              ),
            ),
            SmallTextButton(
              label: 'Copy',
              icon: FluentIcons.copy_24_regular,
              onTap: () => _copyToClipboard(content, title),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.border),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: tokens.fontMono.copyWith(
                  fontSize: 12,
                  color: textColor,
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
}

class _MetadataBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetadataBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.panel2,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tokens.textDim),
          const SizedBox(width: 6),
          Text(
            label,
            style: tokens.fontBody.copyWith(
              fontSize: 11.5,
              color: tokens.textDim,
            ),
          ),
        ],
      ),
    );
  }
}
