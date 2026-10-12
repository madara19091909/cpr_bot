import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/filesystem/safe_path.dart';
import '../core/jobs/cancel_token.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => 'BackupException: $message';
}

class VerifyReport {
  VerifyReport(this.ok, this.problems, this.filesChecked);
  final bool ok;
  final List<String> problems;
  final int filesChecked;
}

class BackupInfo {
  BackupInfo({
    required this.directory,
    required this.name,
    required this.note,
    required this.createdAt,
    required this.sourcePath,
    required this.fileCount,
    required this.totalBytes,
    required this.consistency,
    required this.incomplete,
  });
  final Directory directory;
  final String name;
  final String note;
  final DateTime? createdAt;
  final String sourcePath;
  final int fileCount;
  final int totalBytes;
  final String consistency;
  final bool incomplete;
}

typedef ProgressCallback = void Function(int done, int total);

/// Directory-based backups with a SHA-256 manifest.
///
/// Layout: `root/name/manifest.json` and `root/name/world/...`
/// Consistency: the app cannot tell whether Minecraft is writing to a world,
/// so every backup is labelled "unverified_snapshot" and the copy is rejected
/// if any source file changes (size/mtime) while it is being copied.
class BackupService {
  static const manifestName = 'manifest.json';
  static const worldDir = 'world';
  static const formatVersion = 1;

  Future<String> sha256File(File f) async =>
      (await sha256.bind(f.openRead()).first).toString();

  Future<BackupInfo> createBackup({
    required Directory source,
    required Directory backupsRoot,
    String? name,
    String note = '',
    CancelToken? cancel,
    ProgressCallback? onProgress,
    DateTime? now,
  }) async {
    if (!await source.exists()) {
      throw BackupException('Source world does not exist: ${source.path}');
    }
    if (!await File(p.join(source.path, 'level.dat')).exists()) {
      throw BackupException('Source is not a Bedrock world (no level.dat)');
    }
    await backupsRoot.create(recursive: true);
    final srcReal = await source.resolveSymbolicLinks();
    final rootReal = await backupsRoot.resolveSymbolicLinks();
    if (p.equals(srcReal, rootReal) || p.isWithin(srcReal, rootReal)) {
      throw BackupException(
          'Backup destination is inside the source world (recursive copy refused)');
    }

    final ts = (now ?? DateTime.now().toUtc());
    final stamp = '${ts.year.toString().padLeft(4, '0')}'
        '${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_'
        '${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}'
        '${ts.second.toString().padLeft(2, '0')}';
    final base = sanitizeFileName(name ?? p.basename(source.path));
    final dirName = '${base}_$stamp';
    final finalDir = Directory(p.join(backupsRoot.path, dirName));
    final partial = Directory('${finalDir.path}.partial');
    if (await finalDir.exists()) {
      throw BackupException('A backup named "$dirName" already exists (not overwriting)');
    }
    if (await partial.exists()) await partial.delete(recursive: true);

    try {
      // 1. Enumerate (no symlink following).
      final dirs = <String>[];
      final files = <File>[];
      final skipped = <Map<String, String>>[];
      await for (final e in source.list(recursive: true, followLinks: false)) {
        final rel = p.split(p.relative(e.path, from: source.path)).join('/');
        if (!isSafeRelativePath(rel)) {
          skipped.add({'path': rel, 'reason': 'unsafe path'});
        } else if (e is Link) {
          skipped.add({'path': rel, 'reason': 'symbolic link'});
        } else if (e is Directory) {
          dirs.add(rel);
        } else if (e is File) {
          files.add(e);
        }
      }

      // 2. Copy + hash the copy; remember source stat to detect live changes.
      final destWorld = Directory(p.join(partial.path, worldDir));
      await destWorld.create(recursive: true);
      for (final d in dirs) {
        await Directory(p.join(destWorld.path, d)).create(recursive: true);
      }
      final entries = <Map<String, Object>>[];
      final stats = <File, (int, DateTime)>{};
      var total = 0;
      for (var i = 0; i < files.length; i++) {
        cancel?.throwIfCancelled();
        final f = files[i];
        final rel = p.split(p.relative(f.path, from: source.path)).join('/');
        final st = await f.stat();
        stats[f] = (st.size, st.modified);
        final dest = File(p.join(destWorld.path, rel));
        await dest.parent.create(recursive: true);
        await f.copy(dest.path);
        final copied = await dest.length();
        if (copied != st.size) {
          throw BackupException('Incomplete copy of $rel ($copied of ${st.size} bytes)');
        }
        entries.add({'path': rel, 'size': copied, 'sha256': await sha256File(dest)});
        total += copied;
        onProgress?.call(i + 1, files.length);
      }
      for (final e in stats.entries) {
        final st = await e.key.stat();
        if (st.size != e.value.$1 || st.modified != e.value.$2) {
          throw BackupException(
              'Source changed during backup (${p.basename(e.key.path)}). '
              'Close Minecraft and try again.');
        }
      }

      // 3. Manifest + verification before publishing.
      final manifest = {
        'format': formatVersion,
        'app': 'MC Manger',
        'name': dirName,
        'note': note,
        'createdAt': ts.toIso8601String(),
        'sourcePath': source.path,
        'consistency': 'unverified_snapshot',
        'totalBytes': total,
        'dirs': dirs,
        'files': entries,
        'skipped': skipped,
      };
      await File(p.join(partial.path, manifestName))
          .writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
      final report = await verify(partial, cancel: cancel);
      if (!report.ok) {
        throw BackupException('Verification failed: ${report.problems.first}');
      }
      await partial.rename(finalDir.path);
      return (await _readInfo(finalDir))!;
    } catch (_) {
      if (await partial.exists()) await partial.delete(recursive: true);
      rethrow;
    }
  }

  /// Re-reads every file and compares size and SHA-256 with the manifest.
  Future<VerifyReport> verify(Directory backupDir, {CancelToken? cancel}) async {
    final problems = <String>[];
    final mf = File(p.join(backupDir.path, manifestName));
    if (!await mf.exists()) {
      return VerifyReport(false, ['manifest.json missing'], 0);
    }
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(await mf.readAsString()) as Map<String, dynamic>;
    } on Object catch (e) {
      return VerifyReport(false, ['manifest.json unreadable: $e'], 0);
    }
    if (m['format'] != formatVersion) {
      problems.add('Unsupported manifest format ${m['format']}');
    }
    final world = Directory(p.join(backupDir.path, worldDir));
    final listed = <String>{};
    var checked = 0;
    for (final raw in (m['files'] as List? ?? const [])) {
      cancel?.throwIfCancelled();
      final e = raw as Map<String, dynamic>;
      final rel = e['path'] as String? ?? '';
      if (!isSafeRelativePath(rel)) {
        problems.add('Unsafe path in manifest: $rel');
        continue;
      }
      listed.add(rel);
      final f = File(p.joinAll([world.path, ...rel.split('/')]));
      if (!await f.exists()) {
        problems.add('Missing file: $rel');
        continue;
      }
      if (await f.length() != e['size']) {
        problems.add('Size mismatch: $rel');
        continue;
      }
      if (await sha256File(f) != e['sha256']) problems.add('Hash mismatch: $rel');
      checked++;
    }
    if (await world.exists()) {
      await for (final e in world.list(recursive: true, followLinks: false)) {
        if (e is File) {
          final rel = p.split(p.relative(e.path, from: world.path)).join('/');
          if (!listed.contains(rel)) problems.add('Extra file not in manifest: $rel');
        }
      }
    } else {
      problems.add('world/ directory missing');
    }
    return VerifyReport(problems.isEmpty, problems, checked);
  }

  /// Restores into a NEW directory only. Never replaces an existing world.
  Future<Directory> restore({
    required Directory backupDir,
    required Directory destination,
    CancelToken? cancel,
    ProgressCallback? onProgress,
  }) async {
    if (await destination.exists() ||
        await FileSystemEntity.type(destination.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw BackupException('Destination already exists (not overwriting): ${destination.path}');
    }
    if (p.isWithin(backupDir.path, destination.path)) {
      throw BackupException('Destination is inside the backup');
    }
    final report = await verify(backupDir, cancel: cancel);
    if (!report.ok) {
      throw BackupException('Backup failed verification: ${report.problems.first}');
    }
    final m = jsonDecode(await File(p.join(backupDir.path, manifestName)).readAsString())
        as Map<String, dynamic>;
    final partial = Directory('${destination.path}.partial');
    if (await partial.exists()) await partial.delete(recursive: true);
    try {
      await partial.create(recursive: true);
      for (final d in (m['dirs'] as List? ?? const []).cast<String>()) {
        if (!isSafeRelativePath(d)) throw BackupException('Unsafe directory: $d');
        await Directory(p.joinAll([partial.path, ...d.split('/')])).create(recursive: true);
      }
      final files = (m['files'] as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < files.length; i++) {
        cancel?.throwIfCancelled();
        final rel = files[i]['path'] as String;
        final src = File(p.joinAll([backupDir.path, worldDir, ...rel.split('/')]));
        final dst = File(p.joinAll([partial.path, ...rel.split('/')]));
        await dst.parent.create(recursive: true);
        await src.copy(dst.path);
        if (await sha256File(dst) != files[i]['sha256']) {
          throw BackupException('Restored file hash mismatch: $rel');
        }
        onProgress?.call(i + 1, files.length);
      }
      if (!await File(p.join(partial.path, 'level.dat')).exists()) {
        throw BackupException('Restored world has no level.dat');
      }
      await partial.rename(destination.path);
      return destination;
    } catch (_) {
      if (await partial.exists()) await partial.delete(recursive: true);
      rethrow;
    }
  }

  Future<List<BackupInfo>> list(Directory backupsRoot) async {
    final out = <BackupInfo>[];
    if (!await backupsRoot.exists()) return out;
    await for (final e in backupsRoot.list(followLinks: false)) {
      if (e is! Directory) continue;
      if (e.path.endsWith('.partial')) {
        out.add(BackupInfo(
          directory: e, name: p.basename(e.path), note: '', createdAt: null,
          sourcePath: '', fileCount: 0, totalBytes: 0,
          consistency: 'unknown', incomplete: true));
        continue;
      }
      final info = await _readInfo(e);
      if (info != null) out.add(info);
    }
    out.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return out;
  }

  Future<BackupInfo?> _readInfo(Directory d) async {
    final f = File(p.join(d.path, manifestName));
    if (!await f.exists()) return null;
    try {
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return BackupInfo(
        directory: d,
        name: m['name'] as String? ?? p.basename(d.path),
        note: m['note'] as String? ?? '',
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? ''),
        sourcePath: m['sourcePath'] as String? ?? '',
        fileCount: (m['files'] as List?)?.length ?? 0,
        totalBytes: (m['totalBytes'] as num?)?.toInt() ?? 0,
        consistency: m['consistency'] as String? ?? 'unknown',
        incomplete: false,
      );
    } on Object {
      return null;
    }
  }

  Future<void> delete(Directory backupDir) async {
    if (!await File(p.join(backupDir.path, manifestName)).exists() &&
        !backupDir.path.endsWith('.partial')) {
      throw BackupException('Refusing to delete a directory that is not a backup');
    }
    await backupDir.delete(recursive: true);
  }
}
