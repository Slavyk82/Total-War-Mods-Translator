/// Shared relative-date primitives used by list cells.
///
/// Extracted from the Mods and Steam Publish list cells so both features
/// format identical "3 days" / "2 months" labels. Pure functions — no widget
/// or theme coupling. Callers inject `now` from the ambient `clockProvider`
/// so tests can drive deterministic clocks.
library;

/// Formats the elapsed time from [date] up to [now] as a short relative
/// label used in list cells.
///
/// Examples:
/// - `< 1h` — under an hour old
/// - `5h` — same-day delta in hours
/// - `1 day` / `12 days` — sub-month deltas
/// - `3 months` — sub-year deltas (month = 30 days)
/// - `2 years` — >= 365 days (year = 365 days)
///
/// Returns null when [date] is null so callers can short-circuit the cell
/// render without a separate null-check.
String? formatRelativeSince(DateTime? date, {required DateTime now}) {
  if (date == null) return null;
  final diff = now.difference(date);
  final days = diff.inDays;
  if (days == 0) {
    final hours = diff.inHours;
    return hours == 0 ? '< 1h' : '${hours}h';
  }
  if (days == 1) return '1 day';
  if (days < 30) return '$days days';
  if (days < 365) {
    final months = (days / 30).floor();
    return months == 1 ? '1 month' : '$months months';
  }
  final years = (days / 365).floor();
  return years == 1 ? '1 year' : '$years years';
}

/// Formats [date] as `dd/MM/yyyy HH:mm` for use in hover tooltips.
///
/// Returns null when [date] is null so callers can omit the tooltip block.
String? formatAbsoluteDate(DateTime? date) {
  if (date == null) return null;
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}
