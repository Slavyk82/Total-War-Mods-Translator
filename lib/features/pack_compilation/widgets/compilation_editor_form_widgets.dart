import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../widgets/common/fluent_spinner.dart' hide FluentProgressBar;
import '../../../widgets/fluent/fluent_progress_indicator.dart';

/// Label for form fields in compilation editor.
class CompilationFieldLabel extends StatelessWidget {
  const CompilationFieldLabel({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
      ),
    );
  }
}

/// Fluent-styled text field for compilation editor.
class CompilationTextField extends StatefulWidget {
  const CompilationTextField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.hint,
  });

  final String value;
  final void Function(String) onChanged;
  final String hint;

  @override
  State<CompilationTextField> createState() => _CompilationTextFieldState();
}

class _CompilationTextFieldState extends State<CompilationTextField> {
  late TextEditingController _controller;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(CompilationTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Focus(
      onFocusChange: (hasFocus) => setState(() => _isFocused = hasFocus),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _isFocused
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.5),
            width: _isFocused ? 2 : 1,
          ),
        ),
        child: TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

/// Language dropdown for compilation editor.
class CompilationLanguageDropdown extends StatelessWidget {
  const CompilationLanguageDropdown({
    super.key,
    required this.languages,
    required this.selectedId,
    required this.onChanged,
    this.isDisabled = false,
  });

  final List languages;
  final String? selectedId;
  final void Function(String?) onChanged;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
        color: isDisabled
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedId,
          isExpanded: true,
          hint: Text(
            'Select a language...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
            ),
          ),
          items: languages.map<DropdownMenuItem<String>>((lang) {
            return DropdownMenuItem(
              value: lang.id,
              child: Text(
                lang.displayName,
                style: isDisabled
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color
                            ?.withValues(alpha: 0.7),
                      )
                    : null,
              ),
            );
          }).toList(),
          onChanged: isDisabled ? null : onChanged,
        ),
      ),
    );
  }
}

/// Message box for displaying errors or success messages.
class CompilationMessageBox extends StatelessWidget {
  const CompilationMessageBox({
    super.key,
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError ? theme.colorScheme.error : Colors.green;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isError
                ? FluentIcons.error_circle_24_regular
                : FluentIcons.checkmark_circle_24_regular,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress indicator with label.
class CompilationProgressIndicator extends StatelessWidget {
  const CompilationProgressIndicator({
    super.key,
    required this.progress,
    this.currentStep,
  });

  final double progress;
  final String? currentStep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: FluentProgressBar(
                value: progress,
                height: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${(progress * 100).toInt()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        if (currentStep != null) ...[
          const SizedBox(height: 8),
          Text(
            currentStep!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }
}

/// Summary showing the number of selected projects.
class CompilationSelectionSummary extends StatelessWidget {
  const CompilationSelectionSummary({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = count == 0
        ? 'No projects selected'
        : count == 1
            ? '1 project selected'
            : '$count projects selected';

    return Row(
      children: [
        Icon(
          count > 0
              ? FluentIcons.checkbox_checked_24_regular
              : FluentIcons.checkbox_unchecked_24_regular,
          size: 20,
          color: count > 0
              ? theme.colorScheme.primary
              : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: count > 0
                ? theme.textTheme.bodyMedium?.color
                : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

/// Primary/secondary action button for compilation editor.
class CompilationActionButton extends StatefulWidget {
  const CompilationActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.isPrimary = false,
    this.isLoading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isPrimary;
  final bool isLoading;

  @override
  State<CompilationActionButton> createState() => _CompilationActionButtonState();
}

class _CompilationActionButtonState extends State<CompilationActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onTap != null && !widget.isLoading;

    Color backgroundColor;
    Color contentColor;

    if (widget.isPrimary) {
      backgroundColor = isEnabled
          ? (_isHovered
              ? theme.colorScheme.primary.withValues(alpha: 0.9)
              : theme.colorScheme.primary)
          : theme.colorScheme.surfaceContainerHighest;
      contentColor = isEnabled
          ? theme.colorScheme.onPrimary
          : theme.textTheme.bodyMedium!.color!.withValues(alpha: 0.5);
    } else {
      backgroundColor = _isHovered
          ? theme.colorScheme.surfaceContainerHighest
          : Colors.transparent;
      contentColor = isEnabled
          ? theme.colorScheme.onSurface
          : theme.textTheme.bodyMedium!.color!.withValues(alpha: 0.5);
    }

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6),
            border: widget.isPrimary
                ? null
                : Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isLoading) ...[
                FluentSpinner(
                  size: 18,
                  strokeWidth: 2,
                  color: contentColor,
                ),
              ] else ...[
                Icon(widget.icon, size: 18, color: contentColor),
              ],
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: contentColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stop button for cancelling compilation.
class CompilationStopButton extends StatefulWidget {
  const CompilationStopButton({
    super.key,
    required this.onTap,
    required this.isCancelling,
  });

  final VoidCallback? onTap;
  final bool isCancelling;

  @override
  State<CompilationStopButton> createState() => _CompilationStopButtonState();
}

class _CompilationStopButtonState extends State<CompilationStopButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onTap != null && !widget.isCancelling;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isEnabled
                ? (_isHovered
                    ? theme.colorScheme.error.withValues(alpha: 0.9)
                    : theme.colorScheme.error)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isCancelling) ...[
                FluentSpinner(
                  size: 18,
                  strokeWidth: 2,
                  color: theme.colorScheme.onError,
                ),
              ] else ...[
                Icon(
                  FluentIcons.stop_24_regular,
                  size: 18,
                  color: isEnabled
                      ? theme.colorScheme.onError
                      : theme.textTheme.bodyMedium!.color!.withValues(alpha: 0.5),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                widget.isCancelling ? 'Cancelling...' : 'Stop Generation',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isEnabled
                      ? theme.colorScheme.onError
                      : theme.textTheme.bodyMedium!.color!.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small button used in headers and toolbars.
class CompilationSmallButton extends StatefulWidget {
  const CompilationSmallButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<CompilationSmallButton> createState() => _CompilationSmallButtonState();
}

class _CompilationSmallButtonState extends State<CompilationSmallButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _isHovered
                ? theme.colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            widget.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
