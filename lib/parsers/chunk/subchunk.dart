import 'dart:typed_data';

import '../nbt/nbt.dart';

class SubChunkException implements Exception {
  SubChunkException(this.message);
  final String message;
  @override
  String toString() => 'SubChunkException: $message';
}

class BlockStorage {
  BlockStorage(this.indices, this.palette);
  final Uint16List indices; // 4096 palette indices, order x*256 + z*16 + y
  final List<String> palette; // block names (states are NOT interpreted here)
  String nameAt(int x, int y, int z) => palette[indices[(x << 8) | (z << 4) | y]];
}

class SubChunk {
  SubChunk(this.version, this.yIndex, this.storages);
  final int version;
  final int? yIndex; // only present in version 9
  final List<BlockStorage> storages;
}

/// Decodes the persistent (on-disk) SubChunkPrefix layout, versions 1, 8, 9.
/// Layout knowledge is community-documented and UNVERIFIED for 1.26.x.
/// Unsupported shapes throw instead of being guessed.
SubChunk decodeSubChunk(Uint8List v) {
  if (v.length < 2) throw SubChunkException('Value too short');
  final version = v[0];
  var count = 0;
  var pos = 0;
  int? yIndex;
  switch (version) {
    case 1:
      count = 1;
      pos = 1;
    case 8:
      count = v[1];
      pos = 2;
    case 9:
      if (v.length < 3) throw SubChunkException('Version 9 header truncated');
      count = v[1];
      yIndex = ByteData.sublistView(v).getInt8(2);
      pos = 3;
    default:
      throw SubChunkException('Unsupported sub-chunk version $version');
  }
  if (count < 1 || count > 4) throw SubChunkException('Unsupported storage count $count');
  final bd = ByteData.sublistView(v);
  final storages = <BlockStorage>[];
  for (var s = 0; s < count; s++) {
    if (pos >= v.length) throw SubChunkException('Truncated before storage $s');
    final header = v[pos++];
    final bits = header >> 1;
    if ((header & 1) != 0) throw SubChunkException('Runtime-id palette on disk not supported');
    if (!const [1, 2, 3, 4, 5, 6, 8, 16].contains(bits)) {
      throw SubChunkException('Unsupported bits-per-block $bits');
    }
    final bpw = 32 ~/ bits;
    final words = (4096 + bpw - 1) ~/ bpw;
    if (pos + words * 4 + 4 > v.length) throw SubChunkException('Truncated block data');
    final mask = (1 << bits) - 1;
    final idx = Uint16List(4096);
    var n = 0;
    for (var w = 0; w < words; w++) {
      final word = bd.getUint32(pos + w * 4, Endian.little);
      for (var j = 0; j < bpw && n < 4096; j++) {
        idx[n++] = (word >> (j * bits)) & mask;
      }
    }
    pos += words * 4;
    final pcount = bd.getInt32(pos, Endian.little);
    pos += 4;
    if (pcount < 1 || pcount > 4096) throw SubChunkException('Invalid palette size $pcount');
    final reader = NbtReader(v)..seek(pos);
    final names = <String>[];
    try {
      for (var i = 0; i < pcount; i++) {
        final doc = reader.readNextDocument();
        final name = doc.root['name'];
        if (name == null || name.type != TagType.string) {
          throw SubChunkException('Palette entry $i has no string "name"');
        }
        names.add(name.value as String);
      }
    } on NbtException catch (e) {
      throw SubChunkException('Palette NBT invalid: $e');
    }
    pos = reader.position;
    for (final i in idx) {
      if (i >= pcount) throw SubChunkException('Block index $i outside palette of $pcount');
    }
    storages.add(BlockStorage(idx, names));
  }
  return SubChunk(version, yIndex, storages);
}
