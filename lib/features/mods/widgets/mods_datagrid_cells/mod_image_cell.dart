import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Mod image widget for the DataGrid.
///
/// Displays the mod's preview image, handling both local file paths
/// and network URLs. Shows a placeholder icon when no image is available
/// or when loading fails.
class ModImageCell extends StatelessWidget {
  /// The URL or local file path of the image to display.
  final String? imageUrl;

  const ModImageCell({super.key, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildPlaceholder(context, FluentIcons.image_off_24_regular);
    }

    // Check if it's a local file path or a URL
    final isLocalFile =
        !imageUrl!.startsWith('http://') && !imageUrl!.startsWith('https://');

    if (isLocalFile) {
      return _buildLocalImage(context);
    }

    return _buildNetworkImage(context);
  }

  Widget _buildPlaceholder(BuildContext context, IconData icon) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        icon,
        size: 24,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildLocalImage(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        File(imageUrl!),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(context, FluentIcons.image_alt_text_24_regular),
      ),
    );
  }

  Widget _buildNetworkImage(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: 48,
          height: 48,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (context, url, error) =>
            _buildPlaceholder(context, FluentIcons.image_alt_text_24_regular),
      ),
    );
  }
}
