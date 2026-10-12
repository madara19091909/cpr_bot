import 'dart:typed_data';

final Uint32List _table = () {
  final t = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var j = 0; j < 8; j++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0x82F63B78 : c >> 1;
    }
    t[i] = c;
  }
  return t;
}();

int crc32c(Uint8List data, [int start = 0, int? end]) {
  var c = 0xFFFFFFFF;
  for (var i = start; i < (end ?? data.length); i++) {
    c = _table[(c ^ data[i]) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// LevelDB stores a "masked" CRC so CRCs of CRCs stay well distributed.
int maskCrc(int crc) =>
    ((((crc >> 15) | ((crc << 17) & 0xFFFFFFFF)) + 0xA282EAD8) & 0xFFFFFFFF);
