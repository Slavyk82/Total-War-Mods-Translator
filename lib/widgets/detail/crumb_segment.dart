/// One segment of a detail-screen crumb trail.
///
/// [route] is the absolute path to navigate to when the segment is tapped.
/// When `null`, the segment is rendered as plain text (non-clickable). By
/// convention, the first and last segments of a crumb list have `route: null`.
class CrumbSegment {
  final String label;
  final String? route;

  const CrumbSegment(this.label, {this.route});
}
