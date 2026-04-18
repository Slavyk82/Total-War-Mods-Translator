import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// 110×68 cover slot for [DetailMetaBanner].
///
/// When [imageUrl] is provided, renders `Image.network` with a loading
/// skeleton and an `errorBuilder` that falls back to the monogram. When null
/// or on error, renders [monogramFallback] on a token-themed gradient.
class DetailCover extends StatelessWidget {
  final String? imageUrl;
  final String monogramFallback;

  const DetailCover({
    super.key,
    required this.imageUrl,
    required this.monogramFallback,
  });

  static const double _width = 110;
  static const double _height = 68;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      width: _width,
      height: _height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radiusSm + 2),
        child: imageUrl == null
            ? _Monogram(label: monogramFallback)
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _Monogram(label: monogramFallback),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(color: tokens.panel2);
                },
              ),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  final String label;

  const _Monogram({required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tokens.panel2, tokens.panel],
        ),
        border: Border.all(color: tokens.border),
      ),
      child: Center(
        child: Text(
          label,
          style: tokens.fontDisplay.copyWith(
            fontSize: 26,
            color: tokens.accent,
            fontStyle: tokens.fontDisplayStyle,
            fontWeight: FontWeight.w500,
            letterSpacing: tokens.fontDisplayItalic ? 0 : 1.4,
          ),
        ),
      ),
    );
  }
}
