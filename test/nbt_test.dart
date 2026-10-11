import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mc_manger/parsers/nbt/nbt.dart';

NbtDocument sample() => NbtDocument('', {
      'b': NbtTag.byte(-5),
      's': NbtTag.short(-300),
      'i': NbtTag.int32(2000000000),
      'l': NbtTag.long(-9000000000000),
      'f': NbtTag.float32(1.5),
      'd': NbtTag.float64(-2.25),
      'str': NbtTag.string('héllo مرحبا'),
      'ba': NbtTag.byteArray(Uint8List.fromList([1, 2, 255])),
      'ia': NbtTag.intArray([1, -2, 3]),
      'la': NbtTag.longArray([1, -2]),
      'list': NbtTag.list(TagType.int32, [NbtTag.int32(1), NbtTag.int32(2)]),
      'empty': NbtTag.list(TagType.end, []),
      'nested': NbtTag.compound({'x': NbtTag.compound({'y': NbtTag.byte(1)})}),
    });

void main() {
  test('round trip: parse(serialize(doc)) == doc', () {
    final doc = sample();
    expect(NbtReader(NbtWriter.write(doc)).readDocument(), doc);
  });

  test('encoding is little-endian', () {
    final bytes = NbtWriter.write(NbtDocument('', {'i': NbtTag.int32(1)}));
    // 0A 0000 | 03 0100 'i' | 01 00 00 00 | 00
    expect(bytes, [10, 0, 0, 3, 1, 0, 0x69, 1, 0, 0, 0, 0]);
  });

  test('every truncation of valid data throws NbtException, never RangeError', () {
    final full = NbtWriter.write(sample());
    for (var n = 0; n < full.length; n++) {
      expect(() => NbtReader(Uint8List.sublistView(full, 0, n)).readDocument(),
          throwsA(isA<NbtException>()),
          reason: 'prefix length $n');
    }
  });

  test('rejects non-compound root', () {
    expect(() => NbtReader(Uint8List.fromList([1, 0, 0, 0])).readDocument(),
        throwsA(isA<NbtException>()));
  });

  test('rejects trailing bytes', () {
    final b = NbtWriter.write(NbtDocument('', {}));
    final withExtra = Uint8List.fromList([...b, 0]);
    expect(() => NbtReader(withExtra).readDocument(), throwsA(isA<NbtException>()));
  });

  test('rejects negative and oversized array lengths', () {
    // root, byteArray "a" with length -1
    final neg = Uint8List.fromList([10, 0, 0, 7, 1, 0, 0x61, 0xff, 0xff, 0xff, 0xff, 0]);
    expect(() => NbtReader(neg).readDocument(), throwsA(isA<NbtException>()));
    // claims 1,000,000 bytes but has none: must fail without allocating
    final big = Uint8List.fromList([10, 0, 0, 7, 1, 0, 0x61, 0x40, 0x42, 0x0f, 0, 0]);
    expect(() => NbtReader(big).readDocument(), throwsA(isA<NbtException>()));
  });

  test('rejects unknown tag id and invalid UTF-8', () {
    expect(() => NbtReader(Uint8List.fromList([10, 0, 0, 99, 0, 0])).readDocument(),
        throwsA(isA<NbtException>()));
    final badUtf8 = Uint8List.fromList([10, 0, 0, 8, 1, 0, 0x61, 1, 0, 0xff, 0]);
    expect(() => NbtReader(badUtf8).readDocument(), throwsA(isA<NbtException>()));
  });

  test('rejects duplicate keys', () {
    final dup = Uint8List.fromList(
        [10, 0, 0, 1, 1, 0, 0x61, 1, 1, 1, 0, 0x61, 2, 0]);
    expect(() => NbtReader(dup).readDocument(), throwsA(isA<NbtException>()));
  });

  test('enforces nesting depth limit', () {
    Map<String, NbtTag> nest(int d) =>
        d == 0 ? {} : {'c': NbtTag.compound(nest(d - 1))};
    final bytes = NbtWriter.write(NbtDocument('', nest(100)));
    expect(() => NbtReader(bytes).readDocument(), throwsA(isA<NbtException>()));
    expect(NbtReader(bytes, limits: const NbtLimits(maxDepth: 200)).readDocument(),
        isA<NbtDocument>());
  });

  test('writer validates ranges and list element types', () {
    expect(() => NbtWriter.write(NbtDocument('', {'b': NbtTag.byte(200)})),
        throwsA(isA<NbtException>()));
    expect(
        () => NbtWriter.write(NbtDocument('', {
              'l': NbtTag.list(TagType.int32, [NbtTag.byte(1)])
            })),
        throwsA(isA<NbtException>()));
  });

  test('preserves unknown keys through round trip', () {
    final doc = NbtDocument('', {'mystery': NbtTag.intArray([9, 9]), 'a': NbtTag.byte(1)});
    final back = NbtReader(NbtWriter.write(doc)).readDocument();
    expect(back.root['mystery'], NbtTag.intArray([9, 9]));
  });
}
