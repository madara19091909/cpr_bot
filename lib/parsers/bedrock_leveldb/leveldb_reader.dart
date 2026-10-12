import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'crc32c.dart';
import 'errors.dart';
import 'snappy.dart';

/// One live record. For table-backed records the value is NOT held in memory;
/// it is re-read on demand via [LevelDbReader.readValue].
class IndexEntry {
  IndexEntry({
    required this.key,
    required this.sequence,
    required this.isDeletion,
    required this.valueLength,
    required this.file,
    this.blockOffset = -1,
    this.blockSize = 0,
    this.entryIndex = -1,
    this.inlineValue,
  });
  final Uint8List key;
  final int sequence;
  final bool isDeletion;
  final int valueLength;
  final String file;
  final int blockOffset;
  final int blockSize;
  final int entryIndex;
  final Uint8List? inlineValue;
}

class DbIndex {
  DbIndex(this.entries, this.errors, this.warnings, this.filesRead);
  final List<IndexEntry> entries; // live records, sorted by key bytes
  final List<String> errors; // corruption: records from these spots may be missing
  final List<String> warnings;
  final List<String> filesRead;
  bool get isComplete => errors.isEmpty;
}

class _RawEntry {
  _RawEntry(this.key, this.valueStart, this.valueLength);
  final Uint8List key;
  final int valueStart;
  final int valueLength;
}

/// Pure-Dart, READ-ONLY LevelDB reader (tables + write-ahead logs).
///
/// Simplification (documented in docs/compatibility.md): the MANIFEST is not
/// parsed. Every *.ldb/*.sst/*.log file is read and per-key the highest
/// sequence number wins; tombstones are honoured. A leftover obsolete file
/// therefore cannot resurrect a deleted/overwritten key, but a key that only
/// exists in an orphaned file would still be listed.
class LevelDbReader {
  LevelDbReader(this.directory, {this.verifyChecksums = true, this.maxEntries = 5000000});
  final Directory directory;
  final bool verifyChecksums;
  final int maxEntries;

  static const _tableMagic = [0x57, 0xfb, 0x80, 0x8b, 0x24, 0x75, 0x47, 0xdb];
  static const _footerLen = 48;

  static String hex(Uint8List b) {
    final sb = StringBuffer();
    for (final x in b) {
      sb.write(x.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  Future<DbIndex> buildIndex() async {
    final errors = <String>[];
    final warnings = <String>[];
    if (!await directory.exists()) {
      throw LevelDbException('Database directory missing', file: directory.path);
    }
    final files = <File>[];
    try {
      await for (final e in directory.list(followLinks: false)) {
        if (e is File) files.add(e);
      }
    } on FileSystemException catch (e) {
      throw LevelDbException('Cannot list database directory: ${e.osError?.message ?? e.message}',
          file: directory.path);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    final tables = files.where((f) => f.path.endsWith('.ldb') || f.path.endsWith('.sst'));
    final logs = files.where((f) => f.path.endsWith('.log'));
    if (tables.isEmpty && logs.isEmpty) {
      throw LevelDbException('No .ldb/.sst/.log files found', file: directory.path);
    }

    final winners = <String, IndexEntry>{};
    final read = <String>[];
    void offer(IndexEntry e) {
      final k = hex(e.key);
      final cur = winners[k];
      if (cur == null || e.sequence > cur.sequence) {
        if (cur == null && winners.length >= maxEntries) {
          throw LevelDbException('Entry limit $maxEntries exceeded');
        }
        winners[k] = e;
      }
    }

    for (final f in tables) {
      read.add(p.basename(f.path));
      try {
        await _scanTable(f, offer);
      } on LevelDbException catch (e) {
        errors.add(e.toString());
      } on FileSystemException catch (e) {
        errors.add('${p.basename(f.path)}: ${e.osError?.message ?? e.message}');
      }
    }
    for (final f in logs) {
      read.add(p.basename(f.path));
      try {
        await _scanLog(f, offer, warnings);
      } on LevelDbException catch (e) {
        errors.add(e.toString());
      } on FileSystemException catch (e) {
        errors.add('${p.basename(f.path)}: ${e.osError?.message ?? e.message}');
      }
    }

    final live = winners.values.where((e) => !e.isDeletion).toList()
      ..sort((a, b) => _cmp(a.key, b.key));
    return DbIndex(live, errors, warnings, read);
  }

  static int _cmp(Uint8List a, Uint8List b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }

  final _cache = <String, (Uint8List, List<_RawEntry>)>{}; // small LRU of decoded blocks

  Future<Uint8List> readValue(IndexEntry e) async {
    if (e.inlineValue != null) return e.inlineValue!;
    final ck = '${e.file}:${e.blockOffset}';
    var hit = _cache.remove(ck);
    if (hit == null) {
      final raf = await File(p.join(directory.path, e.file)).open();
      try {
        final block = await _readBlock(raf, e.blockOffset, e.blockSize, e.file);
        hit = (block, _decodeBlock(block, e.file));
      } finally {
        await raf.close();
      }
    }
    _cache[ck] = hit;
    if (_cache.length > 64) _cache.remove(_cache.keys.first);
    final (block, entries) = hit;
    if (e.entryIndex < 0 || e.entryIndex >= entries.length) {
      throw LevelDbException('Entry index out of range', file: e.file);
    }
    final r = entries[e.entryIndex];
    return Uint8List.fromList(block.sublist(r.valueStart, r.valueStart + r.valueLength));
  }

  // ---------- varints ----------
  (int, int) _varint(Uint8List b, int pos, String file, {int maxBytes = 10}) {
    var result = 0;
    var shift = 0;
    for (var i = 0; i < maxBytes; i++) {
      if (pos >= b.length) throw LevelDbException('Truncated varint', file: file, offset: pos);
      final x = b[pos++];
      result |= (x & 0x7F) << shift;
      if (x < 0x80) return (result, pos);
      shift += 7;
    }
    throw LevelDbException('Varint too long', file: file, offset: pos);
  }

  // ---------- blocks ----------
  Future<Uint8List> _readBlock(RandomAccessFile raf, int offset, int size, String name) async {
    final total = size + 5;
    if (offset < 0 || size < 0 || offset + total > await raf.length()) {
      throw LevelDbException('Block handle ($offset,$size) outside file', file: name, offset: offset);
    }
    await raf.setPosition(offset);
    final raw = await raf.read(total);
    if (raw.length != total) {
      throw LevelDbException('Short read for block', file: name, offset: offset);
    }
    final type = raw[size];
    if (verifyChecksums) {
      final stored = ByteData.sublistView(raw).getUint32(size + 1, Endian.little);
      final actual = maskCrc(crc32c(raw, 0, size + 1));
      if (stored != actual) {
        throw LevelDbException('Block CRC mismatch (corrupt data)', file: name, offset: offset);
      }
    }
    final body = Uint8List.sublistView(raw, 0, size);
    switch (type) {
      case 0:
        return Uint8List.fromList(body);
      case 1:
        return snappyDecompress(body);
      case 2:
        return _inflate(body, raw: false, name: name, offset: offset);
      case 4: // Mojang's raw-deflate variant used by Bedrock
        return _inflate(body, raw: true, name: name, offset: offset);
      default:
        throw LevelDbException('Unknown block compression type $type', file: name, offset: offset);
    }
  }

  Uint8List _inflate(Uint8List body, {required bool raw, required String name, required int offset}) {
    try {
      return Uint8List.fromList(ZLibCodec(raw: raw).decode(body));
    } on Object catch (e) {
      throw LevelDbException('Decompression failed: $e', file: name, offset: offset);
    }
  }

  List<_RawEntry> _decodeBlock(Uint8List b, String name) {
    if (b.length < 4) throw LevelDbException('Block too short', file: name);
    final bd = ByteData.sublistView(b);
    final nRestarts = bd.getUint32(b.length - 4, Endian.little);
    final restartsOffset = b.length - 4 - 4 * nRestarts;
    if (nRestarts > (b.length ~/ 4) || restartsOffset < 0) {
      throw LevelDbException('Invalid restart array', file: name);
    }
    final out = <_RawEntry>[];
    var pos = 0;
    var prev = Uint8List(0);
    while (pos < restartsOffset) {
      final (shared, p1) = _varint(b, pos, name, maxBytes: 5);
      final (nonShared, p2) = _varint(b, p1, name, maxBytes: 5);
      final (vlen, p3) = _varint(b, p2, name, maxBytes: 5);
      if (shared > prev.length || p3 + nonShared + vlen > restartsOffset) {
        throw LevelDbException('Block entry out of bounds', file: name, offset: pos);
      }
      final key = Uint8List(shared + nonShared)
        ..setRange(0, shared, prev)
        ..setRange(shared, shared + nonShared, b, p3);
      out.add(_RawEntry(key, p3 + nonShared, vlen));
      prev = key;
      pos = p3 + nonShared + vlen;
    }
    return out;
  }

  // ---------- tables ----------
  Future<void> _scanTable(File f, void Function(IndexEntry) offer) async {
    final name = p.basename(f.path);
    final raf = await f.open();
    try {
      final len = await raf.length();
      if (len < _footerLen) throw LevelDbException('File too small for a table', file: name);
      await raf.setPosition(len - _footerLen);
      final footer = await raf.read(_footerLen);
      for (var i = 0; i < 8; i++) {
        if (footer[40 + i] != _tableMagic[i]) {
          throw LevelDbException('Bad table magic (not a LevelDB table)', file: name);
        }
      }
      var (_, pos) = _varint(footer, 0, name); // metaindex offset
      (_, pos) = _varint(footer, pos, name); // metaindex size
      final (idxOff, pos2) = _varint(footer, pos, name);
      final (idxSize, _) = _varint(footer, pos2, name);
      final index = await _readBlock(raf, idxOff, idxSize, name);
      for (final h in _decodeBlock(index, name)) {
        final hv = Uint8List.sublistView(index, h.valueStart, h.valueStart + h.valueLength);
        final (off, q) = _varint(hv, 0, name);
        final (size, _) = _varint(hv, q, name);
        final block = await _readBlock(raf, off, size, name);
        final entries = _decodeBlock(block, name);
        for (var i = 0; i < entries.length; i++) {
          final k = entries[i].key;
          if (k.length < 8) throw LevelDbException('Internal key shorter than 8 bytes', file: name);
          final tail = ByteData.sublistView(k).getUint64(k.length - 8, Endian.little);
          final type = tail & 0xFF;
          if (type > 1) throw LevelDbException('Unknown value type $type', file: name);
          offer(IndexEntry(
            key: Uint8List.fromList(k.sublist(0, k.length - 8)),
            sequence: tail >> 8,
            isDeletion: type == 0,
            valueLength: entries[i].valueLength,
            file: name,
            blockOffset: off,
            blockSize: size,
            entryIndex: i,
          ));
        }
      }
    } finally {
      await raf.close();
    }
  }

  // ---------- write-ahead log ----------
  Future<void> _scanLog(File f, void Function(IndexEntry) offer, List<String> warnings) async {
    final name = p.basename(f.path);
    final b = await f.readAsBytes();
    const blockSize = 32768;
    var pos = 0;
    final frag = BytesBuilder(copy: false);
    var inFrag = false;
    while (pos < b.length) {
      final left = blockSize - (pos % blockSize);
      if (left < 7) {
        pos += left;
        continue;
      }
      if (pos + 7 > b.length) {
        warnings.add('$name: truncated tail ignored');
        break;
      }
      final bd = ByteData.sublistView(b);
      final crc = bd.getUint32(pos, Endian.little);
      final len = bd.getUint16(pos + 4, Endian.little);
      final type = b[pos + 6];
      if (type == 0 && len == 0) {
        pos += left; // zero padding to end of block
        continue;
      }
      if (len > left - 7 || pos + 7 + len > b.length) {
        warnings.add('$name: torn record at $pos ignored');
        break;
      }
      if (verifyChecksums && crc != maskCrc(crc32c(b, pos + 6, pos + 7 + len))) {
        throw LevelDbException('Log record CRC mismatch', file: name, offset: pos);
      }
      final data = Uint8List.sublistView(b, pos + 7, pos + 7 + len);
      pos += 7 + len;
      switch (type) {
        case 1:
          _applyBatch(data, name, offer);
        case 2:
          frag.clear();
          frag.add(data);
          inFrag = true;
        case 3:
          if (!inFrag) throw LevelDbException('Orphan middle log fragment', file: name, offset: pos);
          frag.add(data);
        case 4:
          if (!inFrag) throw LevelDbException('Orphan last log fragment', file: name, offset: pos);
          frag.add(data);
          inFrag = false;
          _applyBatch(frag.takeBytes(), name, offer);
        default:
          throw LevelDbException('Unknown log record type $type', file: name, offset: pos);
      }
    }
    if (inFrag) warnings.add('$name: unfinished fragmented record ignored');
  }

  void _applyBatch(Uint8List d, String name, void Function(IndexEntry) offer) {
    if (d.length < 12) throw LevelDbException('WriteBatch shorter than 12 bytes', file: name);
    final bd = ByteData.sublistView(d);
    final seq = bd.getUint64(0, Endian.little);
    final count = bd.getUint32(8, Endian.little);
    var pos = 12;
    for (var i = 0; i < count; i++) {
      if (pos >= d.length) throw LevelDbException('WriteBatch truncated', file: name);
      final tag = d[pos++];
      final (klen, p1) = _varint(d, pos, name, maxBytes: 5);
      if (p1 + klen > d.length) throw LevelDbException('WriteBatch key overruns', file: name);
      final key = Uint8List.fromList(d.sublist(p1, p1 + klen));
      pos = p1 + klen;
      if (tag == 1) {
        final (vlen, p2) = _varint(d, pos, name, maxBytes: 5);
        if (p2 + vlen > d.length) throw LevelDbException('WriteBatch value overruns', file: name);
        offer(IndexEntry(
            key: key, sequence: seq + i, isDeletion: false, valueLength: vlen, file: name,
            inlineValue: Uint8List.fromList(d.sublist(p2, p2 + vlen))));
        pos = p2 + vlen;
      } else if (tag == 0) {
        offer(IndexEntry(
            key: key, sequence: seq + i, isDeletion: true, valueLength: 0, file: name));
      } else {
        throw LevelDbException('Unknown WriteBatch tag $tag', file: name);
      }
    }
    if (pos != d.length) throw LevelDbException('Trailing bytes in WriteBatch', file: name);
  }
}
