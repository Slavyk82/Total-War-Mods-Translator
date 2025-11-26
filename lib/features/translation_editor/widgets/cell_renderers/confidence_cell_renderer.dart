import 'package:flutter/material.dart';

/// Confidence cell widget for DataGrid
///
/// Displays confidence score as a percentage with color coding
class ConfidenceCellRenderer extends StatelessWidget {
  final double? confidence;

  const ConfidenceCellRenderer({
    super.key,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    if (confidence == null) {
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8.0),
        child: const Text('-', style: TextStyle(color: Colors.grey)),
      );
    }

    final percentage = (confidence! * 100).round();
    final color = _getConfidenceColor(confidence!);

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8.0),
      child: Text(
        '$percentage%',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  /// Calculate color based on confidence score
  ///
  /// High confidence (>=90%): green
  /// Medium confidence (80-89%): orange
  /// Low confidence (<80%): red
  static Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.90) return Colors.green;
    if (confidence >= 0.80) return Colors.orange;
    return Colors.red;
  }
}
