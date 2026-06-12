/// Removes characters that are illegal in Windows filenames from a pack prefix.
///
/// The pack prefix is concatenated into `.pack` and `.loc` filenames, so any
/// of `/ \ : * ? " < > |` would produce invalid paths. Everything else
/// (including an empty string) is preserved per design: no strong validation.
String sanitizePackPrefix(String input) {
  return input.replaceAll(RegExp(r'[/\\:*?"<>|]'), '');
}
