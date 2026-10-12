import 'nbt/nbt.dart';

class InventoryItem {
  InventoryItem(this.slot, this.name, this.count, this.damage);
  final int? slot;
  final String? name;
  final int? count;
  final int? damage;
}

/// Read-only view over a decoded player NBT document. Every field is nullable:
/// absent or mistyped data stays null (shown as "Unknown"), never guessed.
/// Field names are community-documented and unverified for 1.26.x.
class PlayerSummary {
  PlayerSummary(this.doc);
  final NbtDocument doc;

  int? _int(NbtTag? t) => switch (t?.type) {
        TagType.byte || TagType.short || TagType.int32 || TagType.long => t!.value as int,
        _ => null,
      };

  List<double>? _floats(String key, int n) {
    final t = doc.root[key];
    if (t == null || t.type != TagType.list) return null;
    final l = t.value as NbtList;
    if (l.elementType != TagType.float32 || l.items.length != n) return null;
    return [for (final i in l.items) i.value as double];
  }

  List<double>? get position => _floats('Pos', 3);
  List<double>? get rotation => _floats('Rotation', 2);
  int? get dimensionId => _int(doc.root['DimensionId']);
  int? get selectedSlot => _int(doc.root['SelectedInventorySlot']);
  int? get experienceLevel => _int(doc.root['PlayerLevel']);

  List<InventoryItem>? get inventory {
    final t = doc.root['Inventory'];
    if (t == null || t.type != TagType.list) return null;
    final l = t.value as NbtList;
    if (l.elementType != TagType.compound && l.items.isNotEmpty) return null;
    final out = <InventoryItem>[];
    for (final it in l.items) {
      final m = it.value as Map<String, NbtTag>;
      final n = m['Name'];
      out.add(InventoryItem(
        _int(m['Slot']),
        n != null && n.type == TagType.string ? n.value as String : null,
        _int(m['Count']),
        _int(m['Damage']),
      ));
    }
    return out;
  }
}
