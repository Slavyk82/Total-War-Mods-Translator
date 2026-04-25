import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/theme/twmt_theme_tokens.dart';

import '../providers/steam_publish_providers.dart';
import 'steam_id_editing.dart';

/// Cell rendered in the Steam Publish list's Steam ID column.
///
/// Three modes selected from `(hasPack, hasPublishedId, _isEditing)`:
///   - Read (id present)  → mono ID + pencil
///   - Read (no id)       → em dash + pencil
///   - Edit               → TextField + Save + Cancel
class SteamIdCell extends ConsumerStatefulWidget {
  final PublishableItem item;

  const SteamIdCell({super.key, required this.item});

  @override
  ConsumerState<SteamIdCell> createState() => _SteamIdCellState();
}

class _SteamIdCellState extends ConsumerState<SteamIdCell> {
  final TextEditingController _controller = TextEditingController();
  bool _isEditing = false;
  bool _isSaving = false;
  bool _autoEditDismissed = false;

  /// State-B auto-open: pack exists, no published id, and the user hasn't
  /// explicitly cancelled the auto-opened editor for this row instance.
  bool get _autoEdit {
    final id = widget.item.publishedSteamId;
    final hasId = id != null && id.isNotEmpty;
    return widget.item.hasPack && !hasId && !_autoEditDismissed;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing || _autoEdit) {
      return _buildEdit(context, autoOpen: !_isEditing && _autoEdit);
    }
    return _buildRead(context);
  }

  // ---------------------------------------------------------------------------
  // Read mode (id present or em dash).
  // ---------------------------------------------------------------------------

  Widget _buildRead(BuildContext context) {
    final tokens = context.tokens;
    final id = widget.item.publishedSteamId;
    final hasId = id != null && id.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasId ? id : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.fontMono.copyWith(
                fontSize: 12,
                color: hasId ? tokens.textMid : tokens.textFaint,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _iconButton(
            context: context,
            icon: FluentIcons.edit_24_regular,
            tooltip: hasId ? 'Edit Workshop id' : 'Set Workshop id',
            onTap: _beginEdit,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Edit mode (TextField + Save + Cancel).
  // ---------------------------------------------------------------------------

  Widget _buildEdit(BuildContext context, {required bool autoOpen}) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _controller,
                    enabled: !_isSaving,
                    style: tokens.fontMono.copyWith(
                      fontSize: 12,
                      color: tokens.text,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Paste Workshop URL or ID...',
                      hintStyle: tokens.fontMono.copyWith(
                        fontSize: 12,
                        color: tokens.textFaint,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: tokens.panel2,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(tokens.radiusSm),
                        borderSide: BorderSide(color: tokens.accent),
                      ),
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _iconButton(
                context: context,
                icon: _isSaving ? null : FluentIcons.save_24_regular,
                tooltip: 'Save Workshop id',
                onTap: _isSaving ? null : _save,
                busy: _isSaving,
                accent: true,
              ),
              const SizedBox(width: 4),
              _iconButton(
                context: context,
                icon: FluentIcons.dismiss_24_regular,
                tooltip: 'Cancel',
                onTap: _isSaving ? null : _cancel,
              ),
            ],
          ),
          if (autoOpen) ...[
            const SizedBox(height: 4),
            Text(
              '1. Publish from the launcher · 2. Copy the mod URL here',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.fontMono.copyWith(
                fontSize: 10,
                color: tokens.textFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _beginEdit() {
    _controller.text = widget.item.publishedSteamId ?? '';
    setState(() => _isEditing = true);
  }

  void _cancel() {
    _controller.clear();
    setState(() {
      _isEditing = false;
      _autoEditDismissed = true;
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final ok = await saveWorkshopId(
      ref: ref,
      context: context,
      item: widget.item,
      rawInput: _controller.text,
    );
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (ok) _isEditing = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Square 28×28 icon button — same shape as the action cell's `_iconButton`.
  // ---------------------------------------------------------------------------

  Widget _iconButton({
    required BuildContext context,
    required IconData? icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool busy = false,
    bool accent = false,
  }) {
    final tokens = context.tokens;
    final fg = accent ? tokens.accent : tokens.textMid;
    final borderColor = accent ? tokens.accent : tokens.border;
    final bg = accent ? tokens.accentBg : tokens.panel2;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: busy
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fg,
                    ),
                  )
                : (icon != null
                    ? Icon(icon, size: 14, color: fg)
                    : const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}
