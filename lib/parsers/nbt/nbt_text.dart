import 'nbt.dart';

/// Human-readable, indented dump of an NBT document (technical view).
String nbtToText(NbtDocument doc, {int maxLines = 2000}) {
  final lines = <String>[];
  void walk(String label, NbtTag t, int ind) {
    if (lines.length >= maxLines) return;
    final pad = '  ' * ind;
    final v = t.value;
    switch (t.type) {
      case TagType.compound:
        final m = v as Map<String, NbtTag>;
        lines.add('$pad$label: compound (${m.length})');
        for (final e in m.entries) {
          walk(e.key, e.value, ind + 1);
        }
      case TagType.list:
        final l = v as NbtList;
        lines.add('$pad$label: list<${l.elementType.name}> (${l.items.length})');
        for (var i = 0; i < l.items.length; i++) {
          walk('[$i]', l.items[i], ind + 1);
        }
      case TagType.byteArray:
        lines.add('$pad$label: byte[] (${(v as List).length})');
      case TagType.intArray || TagType.longArray:
        lines.add('$pad$label: ${t.type.name} $v');
      case TagType.string:
        lines.add('$pad$label: string "$v"');
      default:
        lines.add('$pad$label: ${t.type.name} $v');
    }
  }

  walk(doc.rootName.isEmpty ? '(root)' : doc.rootName, NbtTag.compound(doc.root), 0);
  if (lines.length >= maxLines) lines.add('… truncated at $maxLines lines');
  return lines.join('\n');
}
