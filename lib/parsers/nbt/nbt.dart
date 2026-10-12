import 'dart:convert';
import 'dart:typed_data';

/// Bedrock-style NBT: little-endian, UTF-8 strings, uncompressed.
enum TagType {
  end(0),
  byte(1),
  short(2),
  int32(3),
  long(4),
  float32(5),
  float64(6),
  byteArray(7),
  string(8),
  list(9),
  compound(10),
  intArray(11),
  longArray(12);

  const TagType(this.id);
  final int id;

  static TagType? fromId(int id) {
    for (final t in TagType.values) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Smallest possible encoded size of one payload; used to bound allocations.
  int get minPayloadSize => switch (this) {
        TagType.end => 0,
        TagType.byte => 1,
        TagType.short => 2,
        TagType.int32 => 4,
        TagType.long => 8,
        TagType.float32 => 4,
        TagType.float64 => 8,
        TagType.byteArray => 4,
        TagType.string => 2,
        TagType.list => 5,
        TagType.compound => 1,
        TagType.intArray => 4,
        TagType.longArray => 4,
      };
}

class NbtException implements Exception {
  NbtException(this.message, [this.offset]);
  final String message;
  final int? offset;

  @override
  String toString() => offset == null
      ? 'NbtException: $message'
      : 'NbtException: $message (at byte $offset)';
}

class NbtLimits {
  const NbtLimits({this.maxDepth = 64, this.maxElements = 1 << 22});
  final int maxDepth;
  final int maxElements;
}

class NbtList {
  NbtList(this.elementType, this.items);
  final TagType elementType;
  final List<NbtTag> items;
}

class NbtTag {
  const NbtTag(this.type, this.value);

  factory NbtTag.byte(int v) => NbtTag(TagType.byte, v);
  factory NbtTag.short(int v) => NbtTag(TagType.short, v);
  factory NbtTag.int32(int v) => NbtTag(TagType.int32, v);
  factory NbtTag.long(int v) => NbtTag(TagType.long, v);
  factory NbtTag.float32(double v) => NbtTag(TagType.float32, v);
  factory NbtTag.float64(double v) => NbtTag(TagType.float64, v);
  factory NbtTag.string(String v) => NbtTag(TagType.string, v);
  factory NbtTag.byteArray(Uint8List v) => NbtTag(TagType.byteArray, v);
  factory NbtTag.intArray(List<int> v) => NbtTag(TagType.intArray, v);
  factory NbtTag.longArray(List<int> v) => NbtTag(TagType.longArray, v);
  factory NbtTag.list(TagType t, List<NbtTag> v) =>
      NbtTag(TagType.list, NbtList(t, v));
  factory NbtTag.compound(Map<String, NbtTag> v) =>
      NbtTag(TagType.compound, v);

  final TagType type;
  final Object value;

  @override
  bool operator ==(Object other) =>
      other is NbtTag && other.type == type && _valueEq(value, other.value);

  @override
  int get hashCode => type.hashCode;

  @override
  String toString() => 'NbtTag(${type.name}, $value)';
}

bool _valueEq(Object a, Object b) {
  if (a is NbtList && b is NbtList) {
    if (a.elementType != b.elementType || a.items.length != b.items.length) {
      return false;
    }
    for (var i = 0; i < a.items.length; i++) {
      if (a.items[i] != b.items[i]) return false;
    }
    return true;
  }
  if (a is Map<String, NbtTag> && b is Map<String, NbtTag>) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final o = b[e.key];
      if (o == null || o != e.value) return false;
    }
    return true;
  }
  if (a is List<int> && b is List<int>) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  if (a is double && b is double && a.isNaN && b.isNaN) return true;
  return a == b;
}

class NbtDocument {
  NbtDocument(this.rootName, this.root);
  final String rootName;
  final Map<String, NbtTag> root;

  @override
  bool operator ==(Object other) =>
      other is NbtDocument &&
      other.rootName == rootName &&
      _valueEq(root, other.root);

  @override
  int get hashCode => rootName.hashCode;
}

class NbtReader {
  NbtReader(Uint8List bytes, {this.limits = const NbtLimits()})
      : _bytes = bytes,
        _data = ByteData.sublistView(bytes);

  final Uint8List _bytes;
  final ByteData _data;
  final NbtLimits limits;
  int _pos = 0;

  NbtDocument readDocument() {
    final doc = _readOne();
    if (_pos != _bytes.length) {
      throw NbtException(
          '${_bytes.length - _pos} trailing bytes after root compound', _pos);
    }
    return doc;
  }

  /// Reads back-to-back root compounds until the buffer ends (used by
  /// Bedrock block-entity / entity records, which concatenate documents).
  List<NbtDocument> readAllDocuments() {
    final docs = <NbtDocument>[];
    while (_pos < _bytes.length) {
      docs.add(_readOne());
    }
    if (docs.isEmpty) throw NbtException('No NBT data', 0);
    return docs;
  }

  int get position => _pos;

  void seek(int p) {
    if (p < 0 || p > _bytes.length) throw NbtException('Seek outside buffer', p);
    _pos = p;
  }

  /// Reads one root compound starting at the current position.
  NbtDocument readNextDocument() => _readOne();

  NbtDocument _readOne() {
    final start = _pos;
    final typeId = _u8();
    if (typeId != TagType.compound.id) {
      throw NbtException('Root tag must be a compound, found type id $typeId', start);
    }
    final name = _string();
    final root = _readCompound(1);
    return NbtDocument(name, root);
  }

  void _need(int n) {
    if (n < 0 || n > _bytes.length - _pos) {
      throw NbtException(
          'Unexpected end of data: need $n bytes, ${_bytes.length - _pos} remain',
          _pos);
    }
  }

  int _u8() {
    _need(1);
    return _bytes[_pos++];
  }

  int _i8() {
    _need(1);
    final v = _data.getInt8(_pos);
    _pos += 1;
    return v;
  }

  int _u16() {
    _need(2);
    final v = _data.getUint16(_pos, Endian.little);
    _pos += 2;
    return v;
  }

  int _i16() {
    _need(2);
    final v = _data.getInt16(_pos, Endian.little);
    _pos += 2;
    return v;
  }

  int _i32() {
    _need(4);
    final v = _data.getInt32(_pos, Endian.little);
    _pos += 4;
    return v;
  }

  int _i64() {
    _need(8);
    final v = _data.getInt64(_pos, Endian.little);
    _pos += 8;
    return v;
  }

  double _f32() {
    _need(4);
    final v = _data.getFloat32(_pos, Endian.little);
    _pos += 4;
    return v;
  }

  double _f64() {
    _need(8);
    final v = _data.getFloat64(_pos, Endian.little);
    _pos += 8;
    return v;
  }

  String _string() {
    final len = _u16();
    _need(len);
    final start = _pos;
    _pos += len;
    try {
      return utf8.decode(Uint8List.sublistView(_bytes, start, start + len));
    } on FormatException {
      throw NbtException('Invalid UTF-8 in string', start);
    }
  }

  int _length(String what, int elementSize) {
    final at = _pos;
    final n = _i32();
    if (n < 0) throw NbtException('Negative $what length $n', at);
    if (n > limits.maxElements) {
      throw NbtException('$what length $n exceeds limit ${limits.maxElements}', at);
    }
    _need(n * elementSize);
    return n;
  }

  Map<String, NbtTag> _readCompound(int depth) {
    if (depth > limits.maxDepth) {
      throw NbtException('Nesting depth exceeds ${limits.maxDepth}', _pos);
    }
    final map = <String, NbtTag>{};
    while (true) {
      final typeAt = _pos;
      final id = _u8();
      if (id == 0) return map;
      final type = TagType.fromId(id);
      if (type == null) throw NbtException('Unknown tag type id $id', typeAt);
      final name = _string();
      if (map.length >= limits.maxElements) {
        throw NbtException('Compound entry count exceeds limit', typeAt);
      }
      if (map.containsKey(name)) {
        throw NbtException('Duplicate key "$name" in compound', typeAt);
      }
      map[name] = _readPayload(type, depth + 1);
    }
  }

  NbtTag _readPayload(TagType type, int depth) {
    switch (type) {
      case TagType.end:
        throw NbtException('Unexpected end tag', _pos);
      case TagType.byte:
        return NbtTag.byte(_i8());
      case TagType.short:
        return NbtTag.short(_i16());
      case TagType.int32:
        return NbtTag.int32(_i32());
      case TagType.long:
        return NbtTag.long(_i64());
      case TagType.float32:
        return NbtTag.float32(_f32());
      case TagType.float64:
        return NbtTag.float64(_f64());
      case TagType.string:
        return NbtTag.string(_string());
      case TagType.byteArray:
        final n = _length('byte array', 1);
        final out = Uint8List.fromList(Uint8List.sublistView(_bytes, _pos, _pos + n));
        _pos += n;
        return NbtTag.byteArray(out);
      case TagType.intArray:
        final n = _length('int array', 4);
        return NbtTag.intArray([for (var i = 0; i < n; i++) _i32()]);
      case TagType.longArray:
        final n = _length('long array', 8);
        return NbtTag.longArray([for (var i = 0; i < n; i++) _i64()]);
      case TagType.compound:
        return NbtTag.compound(_readCompound(depth));
      case TagType.list:
        if (depth > limits.maxDepth) {
          throw NbtException('Nesting depth exceeds ${limits.maxDepth}', _pos);
        }
        final idAt = _pos;
        final elemId = _u8();
        final elemType = TagType.fromId(elemId);
        if (elemType == null) {
          throw NbtException('Unknown list element type id $elemId', idAt);
        }
        final n = _length('list', elemType.minPayloadSize);
        if (n > 0 && elemType == TagType.end) {
          throw NbtException('Non-empty list of end tags', idAt);
        }
        final items = <NbtTag>[];
        for (var i = 0; i < n; i++) {
          items.add(_readPayload(elemType, depth + 1));
        }
        return NbtTag.list(elemType, items);
    }
  }
}

class NbtWriter {
  final BytesBuilder _b = BytesBuilder();
  final ByteData _s = ByteData(8);

  static Uint8List write(NbtDocument doc) {
    final w = NbtWriter();
    w._w8(TagType.compound.id);
    w._str(doc.rootName);
    w._compound(doc.root);
    return w._b.toBytes();
  }

  void _w8(int v) => _b.addByte(v & 0xff);

  void _range(String what, int v, int lo, int hi) {
    if (v < lo || v > hi) throw NbtException('$what value $v out of range');
  }

  void _w16(int v) {
    _s.setUint16(0, v, Endian.little);
    _b.add(_s.buffer.asUint8List(0, 2));
  }

  void _w32(int v) {
    _s.setInt32(0, v, Endian.little);
    _b.add(_s.buffer.asUint8List(0, 4));
  }

  void _w64(int v) {
    _s.setInt64(0, v, Endian.little);
    _b.add(_s.buffer.asUint8List(0, 8));
  }

  void _str(String s) {
    final enc = utf8.encode(s);
    if (enc.length > 0xffff) throw NbtException('String longer than 65535 bytes');
    _w16(enc.length);
    _b.add(enc);
  }

  void _compound(Map<String, NbtTag> m) {
    for (final e in m.entries) {
      _w8(e.value.type.id);
      _str(e.key);
      _payload(e.value);
    }
    _w8(0);
  }

  void _payload(NbtTag t) {
    final v = t.value;
    switch (t.type) {
      case TagType.end:
        throw NbtException('Cannot write an end tag as a value');
      case TagType.byte:
        _range('byte', v as int, -128, 127);
        _w8(v);
      case TagType.short:
        _range('short', v as int, -32768, 32767);
        _s.setInt16(0, v, Endian.little);
        _b.add(_s.buffer.asUint8List(0, 2));
      case TagType.int32:
        _range('int', v as int, -2147483648, 2147483647);
        _w32(v);
      case TagType.long:
        _w64(v as int);
      case TagType.float32:
        _s.setFloat32(0, v as double, Endian.little);
        _b.add(_s.buffer.asUint8List(0, 4));
      case TagType.float64:
        _s.setFloat64(0, v as double, Endian.little);
        _b.add(_s.buffer.asUint8List(0, 8));
      case TagType.string:
        _str(v as String);
      case TagType.byteArray:
        final a = v as Uint8List;
        _w32(a.length);
        _b.add(a);
      case TagType.intArray:
        final a = v as List<int>;
        _w32(a.length);
        for (final x in a) {
          _range('int', x, -2147483648, 2147483647);
          _w32(x);
        }
      case TagType.longArray:
        final a = v as List<int>;
        _w32(a.length);
        for (final x in a) {
          _w64(x);
        }
      case TagType.compound:
        _compound(v as Map<String, NbtTag>);
      case TagType.list:
        final l = v as NbtList;
        _w8(l.elementType.id);
        _w32(l.items.length);
        for (final item in l.items) {
          if (item.type != l.elementType) {
            throw NbtException(
                'List element type ${item.type.name} != ${l.elementType.name}');
          }
          _payload(item);
        }
    }
  }
}
