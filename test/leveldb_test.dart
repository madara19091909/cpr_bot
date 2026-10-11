import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mc_manger/parsers/bedrock_leveldb/bedrock_keys.dart';
import 'package:mc_manger/parsers/bedrock_leveldb/crc32c.dart';
import 'package:mc_manger/parsers/bedrock_leveldb/errors.dart';
import 'package:mc_manger/parsers/bedrock_leveldb/leveldb_reader.dart';
import 'package:mc_manger/parsers/bedrock_leveldb/snappy.dart';
import 'package:mc_manger/parsers/nbt/nbt.dart';
import 'package:mc_manger/parsers/player_summary.dart';
import 'package:path/path.dart' as p;

String ks(Uint8List k) => LevelDbReader.hex(k);

void main() {
  // SYNTHETIC fixtures from tools/make_leveldb_fixture.py (not a real Bedrock DB).
  final fixtureDir = Directory('test/fixtures/db');
  final expected = jsonDecode(File('test/fixtures/db.expected.json').readAsStringSync())
      as Map<String, dynamic>;

  test('crc32c standard test vector', () {
    expect(crc32c(Uint8List.fromList(ascii.encode('123456789'))), 0xE3069283);
  });

  test('snappy: literal + overlapping copy', () {
    final out = snappyDecompress(Uint8List.fromList([12, 8, 97, 98, 99, 34, 3, 0]));
    expect(ascii.decode(out), 'abcabcabcabc');
  });

  test('snappy: rejects bad offset, truncation, oversized output', () {
    expect(() => snappyDecompress(Uint8List.fromList([4, 1 | (0 << 2), 0])),
        throwsA(isA<LevelDbException>()));
    expect(() => snappyDecompress(Uint8List.fromList([12, 8, 97])),
        throwsA(isA<LevelDbException>()));
    expect(() => snappyDecompress(Uint8List.fromList([0xff, 0xff, 0xff, 0xff, 0x0f])),
        throwsA(isA<LevelDbException>()));
  });

  test('reads table (raw-zlib + plain blocks) merged with log; honours overwrite+delete', () async {
    final idx = await LevelDbReader(fixtureDir).buildIndex();
    expect(idx.errors, isEmpty);
    expect(idx.entries.length, expected['liveKeys']);
    final byKey = {for (final e in idx.entries) ks(e.key): e};
    expect(byKey.containsKey(expected['deleted']), isFalse);
    final mob = byKey[ks(Uint8List.fromList(ascii.encode('mobevents')))]!;
    expect(ascii.decode(await LevelDbReader(fixtureDir).readValue(mob)), expected['mobevents']);
    final unk = byKey[ks(Uint8List.fromList(ascii.encode('zzz_unknown')))]!;
    expect(await LevelDbReader(fixtureDir).readValue(unk), [0xde, 0xad, 0xbe, 0xef]);
  });

  test('unknown keys stay accessible; classification does not invent meaning', () async {
    final idx = await LevelDbReader(fixtureDir).buildIndex();
    final unknown = idx.entries.where((e) => classifyKey(e.key).family == KeyFamily.unknown);
    expect(unknown.map((e) => ascii.decode(e.key)), contains('zzz_unknown'));
  });

  test('local player NBT decodes to summary; absent fields stay null', () async {
    final r = LevelDbReader(fixtureDir);
    final idx = await r.buildIndex();
    final e = idx.entries.firstWhere((e) => classifyKey(e.key).family == KeyFamily.localPlayer);
    final doc = NbtReader(await r.readValue(e)).readAllDocuments().single;
    final s = PlayerSummary(doc);
    expect(s.position, [10.5, 64.0, -3.25]);
    expect(s.rotation, [90.0, 15.0]);
    expect(s.dimensionId, 0);
    expect(s.experienceLevel, isNull);
    final item = s.inventory!.single;
    expect([item.slot, item.name, item.count, item.damage],
        [0, 'minecraft:diamond_sword', 1, 5]);
  });

  group('corruption & failure handling', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('mcm_ldb_');
      for (final f in fixtureDir.listSync().whereType<File>()) {
        f.copySync(p.join(tmp.path, p.basename(f.path)));
      }
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('flipped byte in a block is reported, other data still read', () async {
      final f = File(p.join(tmp.path, '000005.ldb'));
      final b = f.readAsBytesSync();
      b[10] ^= 0xFF;
      f.writeAsBytesSync(b);
      final idx = await LevelDbReader(tmp).buildIndex();
      expect(idx.isComplete, isFalse);
      expect(idx.errors.single, contains('CRC'));
    });

    test('same corruption is NOT silently accepted when checksums are on', () async {
      final f = File(p.join(tmp.path, '000005.ldb'));
      final b = f.readAsBytesSync()..[10] ^= 0xFF;
      f.writeAsBytesSync(b);
      final idx = await LevelDbReader(tmp, verifyChecksums: true).buildIndex();
      expect(idx.entries.length, lessThan(expected['liveKeys'] as int));
    });

    test('bad magic / truncated table', () async {
      File(p.join(tmp.path, '000005.ldb')).writeAsBytesSync(List.filled(100, 1));
      var idx = await LevelDbReader(tmp).buildIndex();
      expect(idx.errors.single, contains('magic'));
      File(p.join(tmp.path, '000005.ldb')).writeAsBytesSync([1, 2, 3]);
      idx = await LevelDbReader(tmp).buildIndex();
      expect(idx.errors.single, contains('too small'));
    });

    test('torn log tail is a warning, not an error', () async {
      final f = File(p.join(tmp.path, '000006.log'));
      f.writeAsBytesSync([...f.readAsBytesSync(), 1, 2, 3]);
      final idx = await LevelDbReader(tmp).buildIndex();
      expect(idx.errors, isEmpty);
      expect(idx.warnings, isNotEmpty);
    });

    test('corrupt log record CRC reported', () async {
      final f = File(p.join(tmp.path, '000006.log'));
      final b = f.readAsBytesSync()..[20] ^= 1;
      f.writeAsBytesSync(b);
      final idx = await LevelDbReader(tmp).buildIndex();
      expect(idx.errors.single, contains('CRC'));
    });

    test('missing directory and empty directory throw LevelDbException', () async {
      await expectLater(LevelDbReader(Directory(p.join(tmp.path, 'nope'))).buildIndex(),
          throwsA(isA<LevelDbException>()));
      final empty = Directory(p.join(tmp.path, 'empty'))..createSync();
      await expectLater(
          LevelDbReader(empty).buildIndex(), throwsA(isA<LevelDbException>()));
    });

    test('reading never modifies the database files', () async {
      Map<String, int> sizes() => {
            for (final f in tmp.listSync().whereType<File>())
              p.basename(f.path): f.readAsBytesSync().fold(0, (a, b) => a * 31 + b & 0xffffff)
          };
      final before = sizes();
      final r = LevelDbReader(tmp);
      final idx = await r.buildIndex();
      for (final e in idx.entries) {
        await r.readValue(e);
      }
      expect(sizes(), before);
    });
  });

  group('Bedrock key classification', () {
    Uint8List chunk(int x, int z, int tag, {int? dim, int? sub}) {
      final b = BytesBuilder();
      final d = ByteData(12)
        ..setInt32(0, x, Endian.little)
        ..setInt32(4, z, Endian.little);
      b.add(d.buffer.asUint8List(0, 8));
      if (dim != null) {
        final dd = ByteData(4)..setInt32(0, dim, Endian.little);
        b.add(dd.buffer.asUint8List());
      }
      b.addByte(tag);
      if (sub != null) b.addByte(sub & 0xff);
      return b.toBytes();
    }

    test('overworld, nether, subchunk with negative y', () {
      var i = classifyKey(chunk(5, -7, 47, sub: -4));
      expect([i.family, i.x, i.z, i.dimension, i.subChunk],
          [KeyFamily.chunkSubChunk, 5, -7, 0, -4]);
      i = classifyKey(chunk(1, 2, 44, dim: 1));
      expect([i.family, i.dimension], [KeyFamily.chunkVersion, 1]);
    });

    test('invalid dimension or tag is unknown, never guessed', () {
      expect(classifyKey(chunk(1, 2, 44, dim: 9)).family, KeyFamily.unknown);
      expect(classifyKey(chunk(1, 2, 200)).family, KeyFamily.unknown);
      expect(classifyKey(chunk(1, 2, 44, sub: 1)).family, KeyFamily.unknown);
    });

    test('named keys take priority over 13-byte chunk shape', () {
      expect(classifyKey(Uint8List.fromList(ascii.encode('~local_player'))).family,
          KeyFamily.localPlayer);
      expect(classifyKey(Uint8List.fromList(ascii.encode('player_abc'))).family,
          KeyFamily.player);
    });
  });
}
