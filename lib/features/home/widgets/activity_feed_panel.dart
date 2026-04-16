import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/activity/models/activity_event.dart';
import 'package:twmt/features/activity/providers/activity_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/cards/token_card.dart';

/// Home dashboard panel surfacing the last persistent activity events.
///
/// Reads [activityFeedProvider] and renders up to 20 rows inside a
/// [TokenCard]. When the feed is empty, a single "No recent activity"
/// placeholder is shown. Each row pairs a monospace, relative timestamp
/// (fixed 60 px column) with a human-readable description derived from the
/// event type + payload.
class ActivityFeedPanel extends ConsumerWidget {
  const ActivityFeedPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final async = ref.watch(activityFeedProvider);

    // Keep loading/error surfaces silent: the Home dashboard already reports
    // global status through `homeStatusProvider`, so the activity feed stays
    // quiet while it settles or when the underlying query fails.
    final events = async.value ?? const <ActivityEvent>[];

    return TokenCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: events.isEmpty
          ? Text(
              'No recent activity',
              style: tokens.fontBody.copyWith(
                fontSize: 12.5,
                color: tokens.textDim,
              ),
            )
          : Column(
              children: [
                for (final e in events) _ActivityRow(event: e),
              ],
            ),
    );
  }
}

/// Single activity row: 60 px monospace timestamp column + description.
class _ActivityRow extends StatelessWidget {
  final ActivityEvent event;
  const _ActivityRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final ts = _formatRelative(event.timestamp);
    final text = _describeEvent(event);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              ts,
              style: tokens.fontMono.copyWith(
                fontSize: 10.5,
                color: tokens.textFaint,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: tokens.fontBody.copyWith(
                fontSize: 12.5,
                height: 1.5,
                color: tokens.textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Human-readable description per event type + payload.
  String _describeEvent(ActivityEvent e) {
    switch (e.type) {
      case ActivityEventType.translationBatchCompleted:
        final count = e.payload['count'] ?? 0;
        final name = e.payload['projectName'] ?? 'Unknown';
        final method = e.payload['method'] == 'llm' ? ' [LLM]' : '';
        return '$name — $count units translated$method';
      case ActivityEventType.packCompiled:
        final name = e.payload['projectName'] ?? 'Unknown';
        return '$name — pack generated';
      case ActivityEventType.projectPublished:
        final name = e.payload['projectName'] ?? 'Unknown';
        return '$name — published';
      case ActivityEventType.modUpdatesDetected:
        final count = e.payload['count'] ?? 0;
        return 'Workshop — $count mod update${count == 1 ? '' : 's'}';
      case ActivityEventType.glossaryEnriched:
        final count = e.payload['count'] ?? 0;
        return 'Glossary enriched — $count term${count == 1 ? '' : 's'}';
    }
  }

  /// Relative timestamp:
  /// - "just now" if < 1 min
  /// - "N min ago" if < 60 min (same day)
  /// - "HH:MM" if same day but > 1 h
  /// - "yesterday" if exactly 1 day ago
  /// - "Nd ago" if < 7 days
  /// - "YYYY-MM-DD" otherwise
  String _formatRelative(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24 && now.day == ts.day) {
      return '${ts.hour.toString().padLeft(2, '0')}:'
          '${ts.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${ts.year}-${ts.month.toString().padLeft(2, '0')}-'
        '${ts.day.toString().padLeft(2, '0')}';
  }
}
