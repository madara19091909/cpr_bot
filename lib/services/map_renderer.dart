import 'dart:io';
import 'dart:typed_data';

import '../parsers/bedrock_leveldb/bedrock_keys.dart';
import '../parsers/bedrock_leveldb/leveldb_reader.dart';
import '../parsers/chunk/subchunk.dart';
import 'block_colors.dart';

const _airLike = {
  'minecraft:air', 'minecraft:cave_air', 'minecraft:void_air',
  'minecraft:structure_void', 'minecraft:light_block', 'minecraft:barrier',
};

/// Finds the highest non-air block of each of the 16x16 columns of a chunk,
/// feeding sub-chunks from the TOP down. Column index = z*16 + x.
class SurfaceBuilder {
  final List<String?> names = List<String?>.filled(256, null);
  final List<int> ys = List<int>.filled(256, 0);
  int unresolved = 256;
  bool get done => unresolved == 0;

  void addSubChunk(int subY, SubChunk sc) {
    final st = sc.storages.first; // layer 0 = solid blocks
    for (var z = 0; z < 16; z++) {
      for (var x = 0; x < 16; x++) {
        final ci = z * 16 + x;
        if (names[ci] != null) continue;
        for (var y = 15; y >= 0; y--) {
          final n = st.nameAt(x, y, z);
          if (!_airLike.contains(n)) {
            names[ci] = n;
            ys[ci] = subY * 16 + y;
            unresolved--;
            break;
          }
        }
      }
    }
  }
}

class MapRequest {
  MapRequest(this.dbPath, this.dimension, {this.centerBlockX, this.centerBlockZ, this.spanChunks = 128});
  final String dbPath;
  final int dimension;
  final int? centerBlockX, centerBlockZ;
  final int spanChunks;
}

class MapResult {
  MapResult({
    required this.rgba, required this.width, required this.height,
    required this.originX, required this.originZ, required this.names,
    required this.nameIdx, required this.heights, required this.chunksDrawn,
    required this.chunksInDimension, required this.availableDimensions,
    required this.errors, required this.unmappedBlocks,
  });
  final Uint8List rgba;
  final int width, height; // pixels == blocks
  final int originX, originZ; // block coords of pixel (0,0)
  final List<String> names;
  final Uint16List nameIdx; // 0xFFFF = no data
  final Int16List heights;
  final int chunksDrawn, chunksInDimension;
  final List<int> availableDimensions;
  final List<String> errors;
  final Set<String> unmappedBlocks;
}

/// Top-level so it can run via Isolate.run. READ-ONLY.
Future<MapResult> renderMap(MapRequest req) async {
  final reader = LevelDbReader(Directory(req.dbPath));
  final idx = await reader.buildIndex();
  final dims = <int>{};
  final subs = <int, List<(int, IndexEntry)>>{}; // packed (cx,cz) -> [(subY, entry)]
  final cxz = <int, (int, int)>{};
  int pack(int x, int z) => ((x & 0xFFFFFFFF) << 32) | (z & 0xFFFFFFFF);
  for (final e in idx.entries) {
    final info = classifyKey(e.key);
    if (!info.isChunk || info.tag == null) continue;
    dims.add(info.dimension ?? 0);
    if (info.family != KeyFamily.chunkSubChunk || info.dimension != req.dimension) continue;
    final k = pack(info.x!, info.z!);
    cxz[k] = (info.x!, info.z!);
    (subs[k] ??= []).add((info.subChunk ?? 0, e));
  }
  final errors = <String>[];
  final unmapped = <String>{};
  final names = <String>[];
  final nameLookup = <String, int>{};
  if (subs.isEmpty) {
    return MapResult(
        rgba: Uint8List(0), width: 0, height: 0, originX: 0, originZ: 0, names: names,
        nameIdx: Uint16List(0), heights: Int16List(0), chunksDrawn: 0, chunksInDimension: 0,
        availableDimensions: dims.toList()..sort(), errors: errors, unmappedBlocks: unmapped);
  }

  // Window of at most spanChunks x spanChunks around the requested/median centre.
  final xs = cxz.values.map((c) => c.$1).toList()..sort();
  final zs = cxz.values.map((c) => c.$2).toList()..sort();
  final ccx = req.centerBlockX != null ? req.centerBlockX! >> 4 : xs[xs.length ~/ 2];
  final ccz = req.centerBlockZ != null ? req.centerBlockZ! >> 4 : zs[zs.length ~/ 2];
  final half = req.spanChunks ~/ 2;
  final inWin = cxz.entries
      .where((e) => (e.value.$1 - ccx).abs() <= half && (e.value.$2 - ccz).abs() <= half)
      .toList();
  if (inWin.isEmpty) {
    errors.add('No chunks near the requested centre');
    return MapResult(
        rgba: Uint8List(0), width: 0, height: 0, originX: 0, originZ: 0, names: names,
        nameIdx: Uint16List(0), heights: Int16List(0), chunksDrawn: 0,
        chunksInDimension: subs.length, availableDimensions: dims.toList()..sort(),
        errors: errors, unmappedBlocks: unmapped);
  }
  final minCx = inWin.map((e) => e.value.$1).reduce((a, b) => a < b ? a : b);
  final maxCx = inWin.map((e) => e.value.$1).reduce((a, b) => a > b ? a : b);
  final minCz = inWin.map((e) => e.value.$2).reduce((a, b) => a < b ? a : b);
  final maxCz = inWin.map((e) => e.value.$2).reduce((a, b) => a > b ? a : b);
  final w = (maxCx - minCx + 1) * 16, h = (maxCz - minCz + 1) * 16;
  final rgba = Uint8List(w * h * 4);
  final nameIdx = Uint16List(w * h)..fillRange(0, w * h, 0xFFFF);
  final heights = Int16List(w * h);
  var drawn = 0;

  for (final c in inWin) {
    final list = subs[c.key]!..sort((a, b) => b.$1.compareTo(a.$1));
    final sb = SurfaceBuilder();
    try {
      for (final (subY, entry) in list) {
        if (sb.done) break;
        sb.addSubChunk(subY, decodeSubChunk(await reader.readValue(entry)));
      }
    } on Object catch (e) {
      if (errors.length < 50) errors.add('chunk ${c.value.$1},${c.value.$2}: $e');
      continue;
    }
    drawn++;
    for (var z = 0; z < 16; z++) {
      for (var x = 0; x < 16; x++) {
        final n = sb.names[z * 16 + x];
        if (n == null) continue;
        final px = (c.value.$1 - minCx) * 16 + x, pz = (c.value.$2 - minCz) * 16 + z;
        final i = pz * w + px;
        final col = blockColor(n);
        if (!col.mapped) unmapped.add(n);
        final y = sb.ys[z * 16 + x];
        final shade = 0.7 + 0.3 * ((y + 64) / 384).clamp(0.0, 1.0);
        rgba[i * 4] = (col.r * shade).round();
        rgba[i * 4 + 1] = (col.g * shade).round();
        rgba[i * 4 + 2] = (col.b * shade).round();
        rgba[i * 4 + 3] = 255;
        nameIdx[i] = nameLookup.putIfAbsent(n, () {
          names.add(n);
          return names.length - 1;
        });
        heights[i] = y;
      }
    }
  }
  return MapResult(
      rgba: rgba, width: w, height: h, originX: minCx * 16, originZ: minCz * 16, names: names,
      nameIdx: nameIdx, heights: heights, chunksDrawn: drawn, chunksInDimension: subs.length,
      availableDimensions: dims.toList()..sort(), errors: errors, unmappedBlocks: unmapped);
}
