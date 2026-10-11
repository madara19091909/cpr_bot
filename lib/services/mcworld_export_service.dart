import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

class McWorldExportService {
  /// Creates a Bedrock .mcworld ZIP with world-relative paths (no wrapper dir).
  /// Refuses to export incomplete worlds and never modifies the source.
  Future<File> exportWorld(Directory world, Directory destination) async {
    if (!await File(p.join(world.path, 'level.dat')).exists() ||
        !await Directory(p.join(world.path, 'db')).exists()) {
      throw StateError('This folder does not look like a complete Bedrock world.');
    }
    await destination.create(recursive: true);
    final name = p.basename(world.path).replaceAll(RegExp(r'[^A-Za-z0-9 _.-]'), '_');
    final out = File(p.join(destination.path,
        '${name}_${DateTime.now().millisecondsSinceEpoch}.mcworld'));
    final archive = Archive();
    var count = 0;
    await for (final entity in world.list(recursive: true, followLinks: false)) {
      if (entity is Link) continue;
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: world.path).split(p.separator).join('/');
      if (rel.startsWith('../') || rel.startsWith('/')) {
        throw StateError('Unsafe world path encountered: $rel');
      }
      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile(rel, bytes.length, bytes));
      count++;
    }
    if (count == 0) throw StateError('World contains no files.');
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null || encoded.isEmpty) throw StateError('Could not encode .mcworld archive.');
    await out.writeAsBytes(encoded, flush: true);
    // Basic integrity check: archive must be readable and contain level.dat.
    final check = ZipDecoder().decodeBytes(await out.readAsBytes());
    if (!check.files.any((f) => f.name == 'level.dat') ||
        !check.files.any((f) => f.name.startsWith('db/'))) {
      await out.delete();
      throw StateError('Export validation failed; incomplete .mcworld was removed.');
    }
    return out;
  }
}
