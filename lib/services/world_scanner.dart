import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/jobs/cancel_token.dart';

class WorldInfo {
  WorldInfo({
    required this.path,
    required this.folderName,
    required this.displayName,
    required this.hasLevelDat,
    required this.hasDb,
    required this.levelDatReadable,
    required this.sizeBytes,
    required this.fileCount,
    required this.lastModified,
    required this.errors,
    required this.scannedAt,
  });

  final String path;
  final String folderName;
  final String? displayName; // from levelname.txt, null if absent
  final bool hasLevelDat;
  final bool hasDb;
  final bool levelDatReadable;
  final int sizeBytes;
  final int fileCount;
  final DateTime? lastModified;
  final List<String> errors;
  final DateTime scannedAt;
}

class ScanResult {
  ScanResult(this.worlds, this.errors);
  final List<WorldInfo> worlds;
  final List<String> errors;
}

/// Read-only discovery. Never writes, never follows symlinks.
class WorldScanner {
  Future<ScanResult> scan(Directory root,
      {int maxDepth = 2, CancelToken? cancel}) async {
    final worlds = <WorldInfo>[];
    final errors = <String>[];
    if (!await root.exists()) {
      return ScanResult(worlds, ['Directory does not exist: ${root.path}']);
    }
    var level = <Directory>[root];
    for (var depth = 0; depth <= maxDepth && level.isNotEmpty; depth++) {
      final next = <Directory>[];
      for (final dir in level) {
        cancel?.throwIfCancelled();
        if (await File(p.join(dir.path, 'level.dat')).exists()) {
          worlds.add(await inspectWorld(dir, cancel: cancel));
          continue; // do not descend into a world
        }
        try {
          await for (final e in dir.list(followLinks: false)) {
            if (e is Directory) next.add(e);
          }
        } on FileSystemException catch (e) {
          errors.add('${dir.path}: ${e.osError?.message ?? e.message}');
        }
      }
      level = next;
    }
    return ScanResult(worlds, errors);
  }

  Future<WorldInfo> inspectWorld(Directory dir, {CancelToken? cancel}) async {
    final errors = <String>[];
    var size = 0;
    var count = 0;
    DateTime? newest;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        cancel?.throwIfCancelled();
        if (e is File) {
          try {
            size += await e.length();
            count++;
            final m = await e.lastModified();
            if (newest == null || m.isAfter(newest)) newest = m;
          } on FileSystemException catch (ex) {
            errors.add('${e.path}: ${ex.osError?.message ?? ex.message}');
          }
        }
      }
    } on FileSystemException catch (ex) {
      errors.add('${dir.path}: ${ex.osError?.message ?? ex.message}');
    }

    String? name;
    try {
      final f = File(p.join(dir.path, 'levelname.txt'));
      if (await f.exists()) name = (await f.readAsString()).trim();
      if (name != null && name.isEmpty) name = null;
    } on Exception catch (ex) {
      errors.add('levelname.txt: $ex');
    }

    final levelDat = File(p.join(dir.path, 'level.dat'));
    var readable = false;
    try {
      final raf = await levelDat.open();
      await raf.read(1);
      await raf.close();
      readable = true;
    } on Exception catch (ex) {
      errors.add('level.dat not readable: $ex');
    }

    return WorldInfo(
      path: dir.path,
      folderName: p.basename(dir.path),
      displayName: name,
      hasLevelDat: await levelDat.exists(),
      hasDb: await Directory(p.join(dir.path, 'db')).exists(),
      levelDatReadable: readable,
      sizeBytes: size,
      fileCount: count,
      lastModified: newest,
      errors: errors,
      scannedAt: DateTime.now(),
    );
  }
}

/// Locations worth probing. On modern Android most are NOT accessible without
/// SAF; the scanner reports the real failure instead of assuming access.
const commonBedrockWorldPaths = <String>[
  '/storage/emulated/0/games/com.mojang/minecraftWorlds',
  '/storage/emulated/0/Android/data/com.mojang.minecraftpe/files/games/com.mojang/minecraftWorlds',
];
