/// Extracts a numeric Steam Workshop ID from [raw].
///
/// Accepts:
/// - Bare numeric IDs ("3456789012")
/// - Full community URLs with an `?id=` query parameter
/// - URLs without scheme (the `Uri` parse will still surface the query)
///
/// Returns the ID as a String (digits only) or `null` when no ID can be
/// recovered. Whitespace is trimmed.
String? parseWorkshopId(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // Bare numeric id.
  if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;

  // Try URI parsing. Both with and without scheme.
  Uri? uri;
  try {
    uri = Uri.parse(trimmed.contains('://') ? trimmed : 'https://$trimmed');
  } on FormatException {
    return null;
  }

  final id = uri.queryParameters['id'];
  if (id != null && RegExp(r'^\d+$').hasMatch(id)) return id;
  return null;
}
