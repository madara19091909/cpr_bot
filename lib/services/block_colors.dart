/// Approximate map colours. Unlisted blocks get a deterministic fallback and
/// are reported as "unmapped" so the UI never pretends the colour is exact.
const _exact = <String, int>{
  'grass_block': 0x5D9B3A, 'dirt': 0x866043, 'stone': 0x7D7D7D, 'sand': 0xDBCFA3,
  'sandstone': 0xD8CB9B, 'gravel': 0x837F7E, 'water': 0x3355CC, 'flowing_water': 0x3355CC,
  'lava': 0xE0560F, 'flowing_lava': 0xE0560F, 'snow': 0xF4FAFA, 'snow_layer': 0xF4FAFA,
  'powder_snow': 0xF4FAFA, 'ice': 0x91B8F5, 'packed_ice': 0x8AA9E8, 'blue_ice': 0x74A6F5,
  'bedrock': 0x333333, 'deepslate': 0x4D4D52, 'netherrack': 0x6F3535, 'end_stone': 0xDDDFA5,
  'cobblestone': 0x767676, 'mycelium': 0x6F6265, 'podzol': 0x5B4020, 'clay': 0xA0A6B2,
  'terracotta': 0x985E43, 'red_sand': 0xBE6621, 'obsidian': 0x14111F, 'basalt': 0x4A4A50,
  'soul_sand': 0x51402F, 'soul_soil': 0x4B3A2B, 'magma': 0x8A3A12, 'mud': 0x3C3A3B,
};

({int r, int g, int b, bool mapped}) blockColor(String fullName) {
  final n = fullName.startsWith('minecraft:') ? fullName.substring(10) : fullName;
  int? c = _exact[n];
  var mapped = true;
  if (c == null) {
    if (n.contains('leaves')) {
      c = 0x3E7A2A;
    } else if (n.contains('planks')) {
      c = 0xA0814F;
    } else if (n.contains('log') || n.contains('wood') || n.contains('stem')) {
      c = 0x6B5232;
    } else if (n.contains('deepslate')) {
      c = 0x4D4D52;
    } else if (n.contains('ore') || n.contains('stone') || n.contains('tuff')) {
      c = 0x808080;
    } else if (n.contains('sand')) {
      c = 0xDBCFA3;
    } else if (n.contains('dirt') || n.contains('grass') || n.contains('moss')) {
      c = 0x6A8A3A;
    } else if (n.contains('water') || n.contains('kelp') || n.contains('seagrass')) {
      c = 0x3355CC;
    } else if (n.contains('ice')) {
      c = 0x91B8F5;
    } else if (n.contains('nether') || n.contains('crimson') || n.contains('warped')) {
      c = 0x6F3535;
    } else {
      var h = 0x811C9DC5;
      for (final u in n.codeUnits) {
        h = ((h ^ u) * 0x01000193) & 0xFFFFFFFF;
      }
      c = 0x404040 | (h & 0xBFBFBF);
      mapped = false;
    }
  }
  return (r: (c >> 16) & 0xFF, g: (c >> 8) & 0xFF, b: c & 0xFF, mapped: mapped);
}
