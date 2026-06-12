import 'dart:io';
import 'package:path/path.dart' as p;

/// Resolves a raw import string found in [importingLibPath] to a normalized
/// repo-relative `lib/...` path, or null if the import does not point into
/// this package's `lib/` (e.g. dart:, package:flutter, third-party).
String? resolveImport({
  required String importingLibPath,
  required String rawImport,
}) {
  const pkgPrefix = 'package:twmt/';
  if (rawImport.startsWith(pkgPrefix)) {
    return 'lib/${rawImport.substring(pkgPrefix.length)}';
  }
  if (rawImport.startsWith('package:') || rawImport.startsWith('dart:')) {
    return null;
  }
  final dir = p.dirname(importingLibPath);
  final joined = p.normalize(p.join(dir, rawImport));
  return p.split(joined).join('/');
}

/// Returns the set of resolved in-package import targets for [absFilePath].
/// [libRelPath] is the path relative to the repo root, e.g. 'lib/a/b.dart'.
Set<String> importsOf(String absFilePath, String libRelPath) {
  final content = File(absFilePath).readAsStringSync();
  final regex = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);
  final result = <String>{};
  for (final m in regex.allMatches(content)) {
    final resolved = resolveImport(
      importingLibPath: libRelPath,
      rawImport: m.group(1)!,
    );
    if (resolved != null) result.add(resolved);
  }
  return result;
}
