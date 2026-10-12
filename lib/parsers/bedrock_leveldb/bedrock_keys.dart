import 'dart:convert';
import 'dart:typed_data';

/// Classification of Bedrock LevelDB keys BY PATTERN ONLY.
/// Tag numbers and key names come from community documentation and have NOT
/// been verified against Minecraft 1.26.x. The result states what the key
/// LOOKS like; it never claims the value has been decoded.
enum KeyFamily {
  chunkVersion,
  chunkData3D,
  chunkData2D,
  chunkSubChunk,
  chunkBlockEntity,
  chunkEntityLegacy,
  chunkPendingTicks,
  chunkFinalizedState,
  chunkOther,
  actorDigest,
  actor,
  player,
  localPlayer,
  map,
  structureTemplate,
  globalNamed,
  unknown,
}

class KeyInfo {
  KeyInfo(this.family, this.label, {this.x, this.z, this.dimension, this.subChunk, this.tag});
  final KeyFamily family;
  final String label;
  final int? x, z, tag;
  final int? dimension; // 0 overworld (implicit), 1 nether, 2 end, other = unknown id
  final int? subChunk; // signed
  bool get isChunk => x != null && z != null;
}

const chunkTagNames = <int, (String, KeyFamily)>{
  43: ('Data3D', KeyFamily.chunkData3D),
  44: ('Version', KeyFamily.chunkVersion),
  45: ('Data2D', KeyFamily.chunkData2D),
  46: ('Data2DLegacy', KeyFamily.chunkData2D),
  47: ('SubChunkPrefix', KeyFamily.chunkSubChunk),
  48: ('LegacyTerrain', KeyFamily.chunkOther),
  49: ('BlockEntity', KeyFamily.chunkBlockEntity),
  50: ('Entity (legacy)', KeyFamily.chunkEntityLegacy),
  51: ('PendingTicks', KeyFamily.chunkPendingTicks),
  52: ('LegacyBlockExtraData', KeyFamily.chunkOther),
  53: ('BiomeState', KeyFamily.chunkOther),
  54: ('FinalizedState', KeyFamily.chunkFinalizedState),
  55: ('ConversionData', KeyFamily.chunkOther),
  56: ('BorderBlocks', KeyFamily.chunkOther),
  57: ('HardCodedSpawners', KeyFamily.chunkOther),
  58: ('RandomTicks', KeyFamily.chunkOther),
  59: ('Checksums', KeyFamily.chunkOther),
  61: ('GenerationSeed', KeyFamily.chunkOther),
  118: ('LegacyVersion', KeyFamily.chunkVersion),
};

const _globalNames = {
  'BiomeData', 'AutonomousEntities', 'mobevents', 'scoreboard', 'schedulerWT',
  'portals', 'Overworld', 'Nether', 'TheEnd', 'LevelChunkMetaDataDictionary',
  'dimension0', 'dimension1', 'dimension2',
};

bool _printable(Uint8List k) => k.isNotEmpty && k.every((b) => b >= 0x20 && b < 0x7F);

bool _startsWith(Uint8List k, String prefix) {
  final p = ascii.encode(prefix);
  if (k.length < p.length) return false;
  for (var i = 0; i < p.length; i++) {
    if (k[i] != p[i]) return false;
  }
  return true;
}

String dimensionName(int? d) => switch (d) {
      0 => 'Overworld',
      1 => 'Nether',
      2 => 'End',
      null => 'Unknown',
      _ => 'Unknown ($d)',
    };

KeyInfo classifyKey(Uint8List k) {
  final ascii_ = _printable(k) ? ascii.decode(k) : null;
  if (ascii_ != null) {
    if (ascii_ == '~local_player') return KeyInfo(KeyFamily.localPlayer, 'Local player');
    if (_globalNames.contains(ascii_)) return KeyInfo(KeyFamily.globalNamed, ascii_);
    if (ascii_.startsWith('player_')) return KeyInfo(KeyFamily.player, 'Player record');
    if (ascii_.startsWith('map_')) return KeyInfo(KeyFamily.map, 'Map data');
    if (ascii_.startsWith('structuretemplate_')) {
      return KeyInfo(KeyFamily.structureTemplate, 'Structure template');
    }
  }
  final bd = ByteData.sublistView(k);
  if (_startsWith(k, 'digp') && (k.length == 12 || k.length == 16)) {
    final dim = k.length == 16 ? bd.getInt32(12, Endian.little) : 0;
    return KeyInfo(KeyFamily.actorDigest, 'Actor digest (chunk)',
        x: bd.getInt32(4, Endian.little), z: bd.getInt32(8, Endian.little), dimension: dim);
  }
  if (_startsWith(k, 'actorprefix') && k.length == 19) {
    return KeyInfo(KeyFamily.actor, 'Actor (entity) record');
  }
  // Chunk keys: x z [dim] tag [subchunk]
  final tagAt = switch (k.length) { 9 || 10 => 8, 13 || 14 => 12, _ => -1 };
  if (tagAt > 0) {
    final tag = k[tagAt];
    final hasSub = k.length == 10 || k.length == 14;
    final info = chunkTagNames[tag];
    final dimOk = tagAt == 8 || const [0, 1, 2].contains(bd.getInt32(8, Endian.little));
    if (info != null && dimOk && (!hasSub || tag == 47)) {
      final dim = tagAt == 12 ? bd.getInt32(8, Endian.little) : 0;
      final sub = hasSub ? bd.getInt8(k.length - 1) : null;
      return KeyInfo(info.$2, 'Chunk ${info.$1}',
          x: bd.getInt32(0, Endian.little),
          z: bd.getInt32(4, Endian.little),
          dimension: dim,
          subChunk: sub,
          tag: tag);
    }
  }
  return KeyInfo(KeyFamily.unknown, ascii_ ?? 'Unrecognised key');
}
