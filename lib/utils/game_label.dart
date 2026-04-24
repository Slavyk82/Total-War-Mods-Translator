/// Strips the "Total War: " prefix from an official game title so UI labels
/// show only the distinctive subtitle (e.g. "WARHAMMER III" instead of
/// "Total War: WARHAMMER III"). Returns the input unchanged when the prefix
/// is absent, keeping the helper safe to apply to any game-name string.
String gameLabel(String name) {
  const prefix = 'Total War: ';
  if (name.startsWith(prefix)) {
    return name.substring(prefix.length);
  }
  return name;
}
