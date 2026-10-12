import 'dart:io';

import 'package:path/path.dart' as p;

import '../parsers/level_dat_parser.dart';
import 'backup_service.dart';

/// The single write gateway for world mutations. A verified, SHA-256
/// manifest backup must be published before any target file is changed.
class WorldMutationService {
  WorldMutationService(this.backups);
  final BackupService backups;

  Future<BackupInfo> writeFile({
    required Directory world,
    required File target,
    required List<int> bytes,
    required Directory backupsRoot,
    required String operation,
    String? note,
  }) async {
    final worldPath = await world.resolveSymbolicLinks();
    final targetPath = p.normalize(target.absolute.path);
    if (!p.isWithin(worldPath, targetPath)) {
      throw StateError('Refusing to modify a file outside the selected world.');
    }
    if (!await target.exists()) {
      throw StateError('Refusing to replace a missing file: ${target.path}');
    }
    final backup = await backups.createBackup(
      source: world,
      backupsRoot: backupsRoot,
      name: p.basename(world.path),
      note: 'PRE-WRITE [$operation] ${note ?? p.relative(target.path, from: world.path)}',
    );
    final verified = await backups.verify(backup.directory);
    if (!verified.ok) {
      throw StateError('Pre-write backup verification failed: ${verified.problems.first}');
    }

    final transactionId = DateTime.now().microsecondsSinceEpoch;
    final temp = File('${target.path}.mcmanger-$transactionId.tmp');
    final rollback = File('${target.path}.mcmanger-rollback-$transactionId.tmp');
    final staged = File('${target.path}.mcmanger-new-$transactionId');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      // Verify bytes on disk before switching the target.
      if (await temp.length() != bytes.length) {
        throw StateError('Temporary write length mismatch.');
      }
      await target.copy(rollback.path);
      await temp.rename(staged.path);
      await target.delete();
      try {
        await staged.rename(target.path);
      } catch (_) {
        if (await rollback.exists()) await rollback.rename(target.path);
        rethrow;
      }
      await rollback.delete();
      return backup;
    } catch (_) {
      if (await rollback.exists() && !await target.exists()) {
        await rollback.rename(target.path);
      }
      if (await temp.exists()) await temp.delete();
      if (await staged.exists()) await staged.delete();
      if (await rollback.exists() && await target.exists()) await rollback.delete();
      rethrow;
    }
  }

  Future<BackupInfo> updateLevelDat({
    required Directory world,
    required Directory backupsRoot,
    required LevelDat updated,
  }) async {
    final bytes = updated.serialize();
    // Round-trip parse before any backup/write is attempted.
    final check = LevelDat.parse(bytes);
    if (check.document.root.length != updated.document.root.length) {
      throw StateError('level.dat validation failed after serialization.');
    }
    return writeFile(
      world: world,
      target: File(p.join(world.path, 'level.dat')),
      bytes: bytes,
      backupsRoot: backupsRoot,
      operation: 'edit-level.dat',
      note: 'level.dat metadata editor',
    );
  }

  /// Deliberately refuses physical LevelDB mutation. Updating an SSTable/log
  /// without a complete MANIFEST-aware Bedrock LevelDB writer can corrupt the
  /// whole world. This is the shared guard used by the DB editor.
  Never writeDatabaseRecord() => throw UnsupportedError(
      'Safe Bedrock LevelDB write support is not available yet. '
      'No database bytes were changed. Export/read-only editing remains safe.');
}
