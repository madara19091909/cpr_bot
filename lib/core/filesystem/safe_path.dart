/// Validates a manifest/archive-style relative path using POSIX separators.
/// Rejects absolute paths, traversal, backslashes, drive letters and NULs.
bool isSafeRelativePath(String rel) {
  if (rel.isEmpty || rel.startsWith('/')) return false;
  if (rel.contains('\\') || rel.contains('\u0000') || rel.contains(':')) {
    return false;
  }
  for (final seg in rel.split('/')) {
    if (seg.isEmpty || seg == '.' || seg == '..') return false;
  }
  return true;
}

/// Turns a user-provided name into a safe single path segment.
String sanitizeFileName(String input) {
  final cleaned = input.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  final trimmed = cleaned.replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  return trimmed.isEmpty ? 'backup' : trimmed;
}
