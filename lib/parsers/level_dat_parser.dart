import 'dart:typed_data';

import 'nbt/nbt.dart';

/// Bedrock level.dat: [u32 LE storage version][u32 LE payload length][NBT].
/// Field names below follow community documentation and are NOT yet verified
/// against real 1.26.x fixtures (see docs/compatibility.md). Any field that is
/// absent or has an unexpected type is reported as null ("Unknown").
class LevelDat {
  LevelDat(this.headerVersion, this.document);

  static const headerSize = 8;
  static const maxFileSize = 16 * 1024 * 1024;

  final int headerVersion;
  final NbtDocument document;

  static LevelDat parse(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw NbtException('level.dat shorter than 8-byte header', 0);
    }
    if (bytes.length > maxFileSize) {
      throw NbtException('level.dat larger than ${maxFileSize ~/ (1024 * 1024)} MiB', 0);
    }
    final h = ByteData.sublistView(bytes);
    final version = h.getUint32(0, Endian.little);
    final length = h.getUint32(4, Endian.little);
    if (length != bytes.length - headerSize) {
      throw NbtException(
          'Header payload length $length != actual ${bytes.length - headerSize}', 4);
    }
    final doc = NbtReader(Uint8List.sublistView(bytes, headerSize)).readDocument();
    return LevelDat(version, doc);
  }

  Uint8List serialize() {
    final payload = NbtWriter.write(document);
    final out = Uint8List(headerSize + payload.length);
    final h = ByteData.sublistView(out);
    h.setUint32(0, headerVersion, Endian.little);
    h.setUint32(4, payload.length, Endian.little);
    out.setRange(headerSize, out.length, payload);
    return out;
  }

  NbtTag? _tag(String key) => document.root[key];

  int? _int(String key) {
    final t = _tag(key);
    if (t == null) return null;
    return switch (t.type) {
      TagType.byte || TagType.short || TagType.int32 || TagType.long => t.value as int,
      _ => null,
    };
  }

  String? _string(String key) {
    final t = _tag(key);
    return t != null && t.type == TagType.string ? t.value as String : null;
  }

  String? get levelName => _string('LevelName');
  int? get gameType => _int('GameType');
  int? get difficulty => _int('Difficulty');
  int? get spawnX => _int('SpawnX');
  int? get spawnY => _int('SpawnY');
  int? get spawnZ => _int('SpawnZ');
  int? get storageVersion => _int('StorageVersion');
  int? get networkVersion => _int('NetworkVersion');
  int? get randomSeed => _int('RandomSeed');
  int? get lastPlayedEpochSeconds => _int('LastPlayed');

  /// e.g. [1, 26, 0, 0, 0] when present as a list of ints.
  List<int>? get lastOpenedWithVersion {
    final t = _tag('lastOpenedWithVersion');
    if (t == null || t.type != TagType.list) return null;
    final l = t.value as NbtList;
    if (l.elementType != TagType.int32) return null;
    return [for (final i in l.items) i.value as int];
  }

  String? get lastOpenedWithVersionString => lastOpenedWithVersion?.join('.');

  /// Top-level keys this parser does not interpret (preserved, never dropped).
  List<String> get uninterpretedKeys {
    const known = {
      'LevelName', 'GameType', 'Difficulty', 'SpawnX', 'SpawnY', 'SpawnZ',
      'StorageVersion', 'NetworkVersion', 'RandomSeed', 'LastPlayed',
      'lastOpenedWithVersion',
    };
    return document.root.keys.where((k) => !known.contains(k)).toList()..sort();
  }
}
