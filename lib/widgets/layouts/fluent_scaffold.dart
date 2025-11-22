import 'package:flutter/material.dart';

/// Fluent Design scaffold widget.
///
/// A replacement for Material's Scaffold that follows Fluent Design principles.
/// Provides a basic layout structure without Material-specific features.
class FluentScaffold extends StatelessWidget {
  final Widget? header;
  final Widget body;
  final Widget? footer;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;

  const FluentScaffold({
    super.key,
    this.header,
    required this.body,
    this.footer,
    this.backgroundColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor =
        backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;

    // Wrap with Material to provide Material ancestor for Material widgets
    // The Material widget is transparent and doesn't affect Fluent Design appearance
    return Material(
      color: bgColor,
      child: Column(
        children: [
          if (header != null) header!,
          Expanded(
            child: padding != null
                ? Padding(padding: padding!, child: body)
                : body,
          ),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

/// Fluent Design header/title bar.
///
/// A replacement for Material's AppBar that follows Fluent Design principles.
class FluentHeader extends StatelessWidget {
  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final double height;
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final Widget? bottom;

  const FluentHeader({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.height = 48,
    this.backgroundColor,
    this.padding,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.surface;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: height,
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: 12),
                ],
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (actions != null) ...[
                  const SizedBox(width: 12),
                  ...actions!.map((action) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: action,
                      )),
                ],
              ],
            ),
          ),
          if (bottom != null) bottom!,
        ],
      ),
    );
  }
}

/// Fluent Design page wrapper with optional header.
///
/// Combines FluentHeader and content area for a complete page layout.
class FluentPage extends StatelessWidget {
  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget? headerBottom;
  final Widget body;
  final Widget? footer;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;

  const FluentPage({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.headerBottom,
    required this.body,
    this.footer,
    this.padding,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return FluentScaffold(
      backgroundColor: backgroundColor,
      header: (title != null || leading != null || actions != null)
          ? FluentHeader(
              title: title,
              leading: leading,
              actions: actions,
              bottom: headerBottom,
            )
          : null,
      body: body,
      footer: footer,
      padding: padding,
    );
  }
}

/// Fluent Design icon button.
///
/// A button that displays only an icon, following Fluent Design interaction patterns.
class FluentIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;

  const FluentIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 20,
    this.color,
  });

  @override
  State<FluentIconButton> createState() => _FluentIconButtonState();
}

class _FluentIconButtonState extends State<FluentIconButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;
    final theme = Theme.of(context);
    final iconColor = widget.color ?? theme.iconTheme.color ?? Colors.black;

    Color backgroundColor;
    if (isDisabled) {
      backgroundColor = Colors.transparent;
    } else if (_isPressed) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.15);
    } else if (_isHovered) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.08);
    } else {
      backgroundColor = Colors.transparent;
    }

    final button = MouseRegion(
      cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            size: widget.size,
            color: isDisabled ? iconColor.withValues(alpha: 0.4) : iconColor,
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return button;
  }
}
