import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mc_manger/parsers/chunk/subchunk.dart';
import 'package:mc_manger/parsers/nbt/nbt.dart';
import 'package:mc_manger/services/block_colors.dart';
import 'package:mc_manger/services/map_renderer.dart';

/// Builds a v9 sub-chunk in the documented on-disk layout (synthetic).
Uint8List buildSubChunk(int subY, List<String> palette, int Function(int x, int y, int z) pick,
    {int bits = 4, int version = 9}) {
  final b = BytesBuilder()..addByte(version)..addByte(1);
  if (version == 9) b.addByte(subY & 0xFF);
  b.addByte(bits << 1);
  final bpw = 32 ~/ bits;
  final words = (4096 + bpw - 1) ~/ bpw;
  final idx = List<int>.filled(4096, 0);
  for (var x = 0; x < 16; x++) {
    for (var z = 0; z < 16; z++) {
      for (var y = 0; y < 16; y++) {
        idx[(x << 8) | (z << 4) | y] = pick(x, y, z);
      }
    }
  }
  final data = ByteData(words * 4);
  for (var i = 0; i < 4096; i++) {
    final w = i ~/ bpw, j = i % bpw;
    data.setUint32(w * 4, data.getUint32(w * 4, Endian.little) | (idx[i] << (j * bits)), Endian.little);
  }
  b.add(data.buffer.asUint8List());
  final pc = ByteData(4)..setInt32(0, palette.length, Endian.little);
  b.add(pc.buffer.asUint8List());
  for (final n in palette) {
    b.add(NbtWriter.write(NbtDocument('', {
      'name': NbtTag.string(n),
      'states': NbtTag.compound({}),
      'version': NbtTag.int32(1),
    })));
  }
  return b.toBytes();
}

void main() {
  const pal = ['minecraft:air', 'minecraft:stone', 'minecraft:grass_block'];

  test('decodes v9 sub-chunk: indices and palette', () {
    final v = buildSubChunk(-1, pal, (x, y, z) => y < 5 ? 1 : (y == 5 ? 2 : 0));
    final sc = decodeSubChunk(v);
    expect(sc.version, 9);
    expect(sc.yIndex, -1);
    final st = sc.storages.single;
    expect(st.palette, pal);
    expect(st.nameAt(3, 2, 7), 'minecraft:stone');
    expect(st.nameAt(3, 5, 7), 'minecraft:grass_block');
    expect(st.nameAt(0, 15, 0), 'minecraft:air');
  });

  test('decodes every supported bits-per-block width', () {
    for (final bits in [1, 2, 3, 4, 5, 6, 8, 16]) {
      final n = bits == 1 ? 2 : 3;
      final v = buildSubChunk(0, pal.take(n).toList(), (x, y, z) => (x + y + z) % n, bits: bits);
      final st = decodeSubChunk(v).storages.single;
      expect(st.nameAt(1, 2, 3), pal[(1 + 2 + 3) % n], reason: 'bits=$bits');
    }
  });

  test('v8 (no y byte) also decodes', () {
    final v = buildSubChunk(0, pal, (x, y, z) => 1, version: 8);
    final sc = decodeSubChunk(v);
    expect(sc.yIndex, isNull);
    expect(sc.storages.single.nameAt(0, 0, 0), 'minecraft:stone');
  });

  test('malformed sub-chunks throw SubChunkException, never RangeError', () {
    final v = buildSubChunk(0, pal, (x, y, z) => 1);
    for (var n = 0; n < v.length; n += 7) {
      expect(() => decodeSubChunk(Uint8List.sublistView(v, 0, n)), throwsA(isA<SubChunkException>()),
          reason: 'prefix $n');
    }
    expect(() => decodeSubChunk(Uint8List.fromList([5, 1, 0])), throwsA(isA<SubChunkException>()));
    final bad = Uint8List.fromList(v)..[3] = 1; // runtime flag set
    expect(() => decodeSubChunk(bad), throwsA(isA<SubChunkException>()));
    // index outside palette: 3 entries declared 2
    final outside = buildSubChunk(0, pal.take(2).toList(), (x, y, z) => 2, bits: 2);
    expect(() => decodeSubChunk(outside), throwsA(isA<SubChunkException>()));
  });

  test('SurfaceBuilder: top-down, skips air, uses key sub-chunk y', () {
    final upper = decodeSubChunk(buildSubChunk(1, pal, (x, y, z) => (x == 0 && z == 0 && y == 3) ? 2 : 0));
    final lower = decodeSubChunk(buildSubChunk(0, pal, (x, y, z) => 1));
    final sb = SurfaceBuilder();
    sb.addSubChunk(1, upper);
    expect(sb.unresolved, 255);
    sb.addSubChunk(0, lower);
    expect(sb.done, isTrue);
    expect(sb.names[0], 'minecraft:grass_block');
    expect(sb.ys[0], 16 + 3);
    expect(sb.names[17], 'minecraft:stone'); // x=1,z=1
    expect(sb.ys[17], 15);
  });

  test('block colours: mapped vs fallback is reported honestly', () {
    expect(blockColor('minecraft:stone').mapped, isTrue);
    expect(blockColor('minecraft:oak_leaves').mapped, isTrue);
    final weird = blockColor('minecraft:totally_new_block');
    expect(weird.mapped, isFalse);
    expect(blockColor('minecraft:totally_new_block').r, weird.r); // deterministic
  });
}
