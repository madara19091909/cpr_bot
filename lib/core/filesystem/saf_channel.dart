import 'package:flutter/services.dart';

class SafImportResult {
  SafImportResult(this.fileCount, this.errors);
  final int fileCount;
  final List<String> errors;
}

/// Thin wrapper over the Kotlin Storage Access Framework bridge.
/// All SAF handling lives in android_overlay/MainActivity.kt.
class SafChannel {
  static const _ch = MethodChannel('mcmanger/saf');

  /// Opens the system folder picker. Returns the tree URI or null if cancelled.
  Future<String?> pickTree() => _ch.invokeMethod<String>('pickTree');

  Future<bool> hasPermission(String uri) async =>
      (await _ch.invokeMethod<bool>('hasPermission', {'uri': uri})) ?? false;

  Future<String?> treeName(String uri) =>
      _ch.invokeMethod<String>('treeName', {'uri': uri});

  /// Copies the picked tree into [destPath] (app-private storage).
  /// The original is only read, never modified.
  Future<SafImportResult> copyTree(String uri, String destPath) async {
    final r = await _ch.invokeMapMethod<String, dynamic>(
        'copyTree', {'uri': uri, 'dest': destPath});
    return SafImportResult(
      (r?['files'] as int?) ?? 0,
      ((r?['errors'] as List?) ?? const []).cast<String>(),
    );
  }
}
