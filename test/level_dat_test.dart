import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mc_manger/parsers/level_dat_parser.dart';
import 'package:mc_manger/parsers/nbt/nbt.dart';

void main() {
  // SYNTHETIC fixture from tools/make_fixture.py - not a real Minecraft world.
  final bytes = File('test/fixtures/level.dat').readAsBytesSync();
  final expected = jsonDecode(File('test/fixtures/level.expected.json').readAsStringSync())
      as Map<String, dynamic>;

  test('decodes known fields from synthetic fixture', () {
    final l = LevelDat.parse(bytes);
    expect(l.headerVersion, expected['headerVersion']);
    expect(l.levelName, expected['LevelName']);
    expect(l.gameType, 1);
    expect(l.difficulty, 2);
    expect(l.spawnX, -12);
    expect(l.spawnZ, 300);
    expect(l.randomSeed, -1234567890123);
    expect(l.lastOpenedWithVersionString, '1.26.0.0.0');
    expect(l.document.root.length, expected['keyCount']);
  });

  test('missing/mistyped fields are null, not guessed', () {
    final l = LevelDat(1, NbtDocument('', {'GameType': NbtTag.string('x')}));
    expect(l.gameType, isNull);
    expect(l.levelName, isNull);
    expect(l.lastOpenedWithVersion, isNull);
  });

  test('serialize round-trips byte-for-byte on the fixture', () {
    expect(LevelDat.parse(bytes).serialize(), bytes);
  });

  test('unknown keys are reported, not dropped', () {
    final l = LevelDat.parse(bytes);
    expect(l.uninterpretedKeys, contains('UnknownIntArray'));
    expect(l.uninterpretedKeys, contains('experiments'));
  });

  test('rejects short header, wrong length, truncation', () {
    expect(() => LevelDat.parse(Uint8List(4)), throwsA(isA<NbtException>()));
    final wrong = Uint8List.fromList(bytes)..[4] = 1;
    expect(() => LevelDat.parse(wrong), throwsA(isA<NbtException>()));
    expect(() => LevelDat.parse(Uint8List.sublistView(bytes, 0, bytes.length - 3)),
        throwsA(isA<NbtException>()));
  });
}
