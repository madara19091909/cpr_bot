import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mc_manger/parsers/level_dat_parser.dart';
import 'package:mc_manger/parsers/nbt/nbt.dart';
import 'package:mc_manger/services/backup_service.dart';
import 'package:mc_manger/services/mcworld_export_service.dart';
import 'package:mc_manger/services/world_mutation_service.dart';
import 'package:archive/archive.dart';

void main() {
  late Directory temp;
  late Directory world;
  late Directory backups;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mcmanger_mutation_test');
    world = Directory('${temp.path}/world');
    backups = Directory('${temp.path}/backups');
    await Directory('${world.path}/db').create(recursive: true);
    await File('${world.path}/db/CURRENT').writeAsString('MANIFEST-000001\n');
    await File('${world.path}/db/000001.log').writeAsBytes([1, 2, 3]);
    final dat = LevelDat(10, NbtDocument('', {
      'LevelName': NbtTag.string('Fixture'),
      'GameType': NbtTag.int32(0),
      'Difficulty': NbtTag.int32(2),
      'SpawnX': NbtTag.int32(0),
      'SpawnY': NbtTag.int32(64),
      'SpawnZ': NbtTag.int32(0),
      'RandomSeed': NbtTag.long(123),
    }));
    await File('${world.path}/level.dat').writeAsBytes(dat.serialize());
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('level.dat mutation creates verified pre-write backup first', () async {
    final backup = BackupService();
    final mutations = WorldMutationService(backup);
    final originalBytes = await File('${world.path}/level.dat').readAsBytes();
    final old = LevelDat.parse(originalBytes);
    final root = Map<String, NbtTag>.from(old.document.root)
      ..['LevelName'] = NbtTag.string('Changed');
    await mutations.updateLevelDat(
      world: world,
      backupsRoot: backups,
      updated: LevelDat(old.headerVersion, NbtDocument(old.document.rootName, root)),
    );
    final now = LevelDat.parse(await File('${world.path}/level.dat').readAsBytes());
    expect(now.levelName, 'Changed');
    final listed = await backup.list(backups);
    expect(listed.length, 1);
    expect((await backup.verify(listed.single.directory)).ok, isTrue);
    final backedUp = await File('${listed.single.directory.path}/world/level.dat').readAsBytes();
    expect(LevelDat.parse(backedUp).levelName, 'Fixture');
  });

  test('.mcworld export is a zip with world-relative paths', () async {
    final outDir = Directory('${temp.path}/out');
    final out = await McWorldExportService().exportWorld(world, outDir);
    expect(out.path.endsWith('.mcworld'), isTrue);
    final zip = ZipDecoder().decodeBytes(await out.readAsBytes());
    expect(zip.files.any((f) => f.name == 'level.dat'), isTrue);
    expect(zip.files.any((f) => f.name == 'db/CURRENT'), isTrue);
    expect(zip.files.any((f) => f.name.startsWith('world/')), isFalse);
  });

  test('backup manifest is valid JSON and records pre-write operation', () async {
    final service = BackupService();
    final info = await service.createBackup(
      source: world, backupsRoot: backups, name: 'world',
      note: 'PRE-WRITE [test] level.dat',
    );
    final manifest = jsonDecode(await File('${info.directory.path}/manifest.json').readAsString());
    expect(manifest['note'], contains('PRE-WRITE'));
    expect(manifest['consistency'], 'unverified_snapshot');
  });
}
