import 'dart:typed_data';

import 'errors.dart';

/// Snappy raw-block decompressor with strict bounds checking.
Uint8List snappyDecompress(Uint8List src, {int maxOutput = 64 << 20}) {
  var pos = 0;
  var len = 0;
  var shift = 0;
  while (true) {
    if (pos >= src.length) throw LevelDbException('Snappy: truncated length');
    final b = src[pos++];
    len |= (b & 0x7F) << shift;
    if (b < 0x80) break;
    shift += 7;
    if (shift > 28) throw LevelDbException('Snappy: length varint too long');
  }
  if (len > maxOutput) throw LevelDbException('Snappy: output $len exceeds limit');
  final out = Uint8List(len);
  var o = 0;
  void need(int n) {
    if (n < 0 || pos + n > src.length) throw LevelDbException('Snappy: truncated input');
  }

  while (pos < src.length) {
    final tag = src[pos++];
    final t = tag & 3;
    if (t == 0) {
      var l = tag >> 2;
      if (l >= 60) {
        final n = l - 59;
        need(n);
        l = 0;
        for (var i = 0; i < n; i++) {
          l |= src[pos + i] << (8 * i);
        }
        pos += n;
      }
      l += 1;
      need(l);
      if (o + l > len) throw LevelDbException('Snappy: literal overruns output');
      out.setRange(o, o + l, src, pos);
      pos += l;
      o += l;
    } else {
      int l;
      int off;
      if (t == 1) {
        l = 4 + ((tag >> 2) & 7);
        need(1);
        off = ((tag >> 5) << 8) | src[pos++];
      } else if (t == 2) {
        l = 1 + (tag >> 2);
        need(2);
        off = src[pos] | (src[pos + 1] << 8);
        pos += 2;
      } else {
        l = 1 + (tag >> 2);
        need(4);
        off = src[pos] | (src[pos + 1] << 8) | (src[pos + 2] << 16) | (src[pos + 3] << 24);
        pos += 4;
      }
      if (off <= 0 || off > o) throw LevelDbException('Snappy: bad copy offset $off');
      if (o + l > len) throw LevelDbException('Snappy: copy overruns output');
      for (var i = 0; i < l; i++) {
        out[o + i] = out[o + i - off]; // byte-wise: overlapping copies are valid
      }
      o += l;
    }
  }
  if (o != len) throw LevelDbException('Snappy: produced $o of $len bytes');
  return out;
}
