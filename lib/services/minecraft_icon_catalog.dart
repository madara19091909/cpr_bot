import 'package:flutter/material.dart';

class MinecraftIconData {
  const MinecraftIconData(this.emoji, this.color);
  final String emoji;
  final Color color;
}

/// Small offline catalog of familiar block/item symbols. These are visual
/// fallbacks, not Mojang's copyrighted in-game sprite textures.
const Map<String, MinecraftIconData> minecraftIconCatalog = {
  'minecraft:grass_block': MinecraftIconData('🌱', Color(0xFF69A843)),
  'minecraft:dirt': MinecraftIconData('🟫', Color(0xFF8A6144)),
  'minecraft:stone': MinecraftIconData('🪨', Color(0xFF858585)),
  'minecraft:cobblestone': MinecraftIconData('🪨', Color(0xFF777777)),
  'minecraft:oak_log': MinecraftIconData('🪵', Color(0xFF9A7545)),
  'minecraft:oak_planks': MinecraftIconData('🟫', Color(0xFFB38B55)),
  'minecraft:sand': MinecraftIconData('🟨', Color(0xFFE0D09A)),
  'minecraft:water': MinecraftIconData('💧', Color(0xFF3989E8)),
  'minecraft:lava': MinecraftIconData('🔥', Color(0xFFFF6B22)),
  'minecraft:diamond': MinecraftIconData('💎', Color(0xFF47D8D2)),
  'minecraft:diamond_ore': MinecraftIconData('💎', Color(0xFF4BB7B8)),
  'minecraft:iron_ingot': MinecraftIconData('🔩', Color(0xFFB7B7B7)),
  'minecraft:gold_ingot': MinecraftIconData('🪙', Color(0xFFFFD34F)),
  'minecraft:emerald': MinecraftIconData('💚', Color(0xFF42C879)),
  'minecraft:coal': MinecraftIconData('⚫', Color(0xFF555555)),
  'minecraft:redstone': MinecraftIconData('🔴', Color(0xFFDF3C36)),
  'minecraft:lapis_lazuli': MinecraftIconData('🔵', Color(0xFF326DD6)),
  'minecraft:apple': MinecraftIconData('🍎', Color(0xFFE94B4B)),
  'minecraft:bread': MinecraftIconData('🍞', Color(0xFFC9954B)),
  'minecraft:carrot': MinecraftIconData('🥕', Color(0xFFF28B35)),
  'minecraft:diamond_sword': MinecraftIconData('⚔️', Color(0xFF56DAD8)),
  'minecraft:iron_sword': MinecraftIconData('🗡️', Color(0xFFB9C2CA)),
  'minecraft:bow': MinecraftIconData('🏹', Color(0xFF9A7545)),
  'minecraft:shield': MinecraftIconData('🛡️', Color(0xFF7896B8)),
  'minecraft:torch': MinecraftIconData('🔦', Color(0xFFFFC85C)),
  'minecraft:chest': MinecraftIconData('📦', Color(0xFFB17A3E)),
  'minecraft:crafting_table': MinecraftIconData('🧰', Color(0xFFB17A3E)),
  'minecraft:furnace': MinecraftIconData('♨️', Color(0xFF8B8B8B)),
  'minecraft:bed': MinecraftIconData('🛏️', Color(0xFFB74D4D)),
  'minecraft:ender_pearl': MinecraftIconData('🟢', Color(0xFF36A86D)),
  'minecraft:ender_eye': MinecraftIconData('👁️', Color(0xFF4A9D7B)),
  'minecraft:totem_of_undying': MinecraftIconData('🧿', Color(0xFF45B68A)),
  'minecraft:elytra': MinecraftIconData('🪽', Color(0xFFB5B7C9)),
  'minecraft:shield_item': MinecraftIconData('🛡️', Color(0xFF7896B8)),
};

MinecraftIconData iconForMinecraftId(String id) {
  final normalized = id.contains(':') ? id : 'minecraft:$id';
  final exact = minecraftIconCatalog[normalized];
  if (exact != null) return exact;
  final n = normalized.toLowerCase();
  if (n.contains('ore')) return const MinecraftIconData('💎', Color(0xFF63B9B0));
  if (n.contains('wood') || n.contains('log') || n.contains('planks')) {
    return const MinecraftIconData('🪵', Color(0xFF9A7545));
  }
  if (n.contains('sword') || n.contains('axe') || n.contains('pickaxe')) {
    return const MinecraftIconData('⚔️', Color(0xFFB6C4CE));
  }
  if (n.contains('food') || n.contains('apple') || n.contains('bread')) {
    return const MinecraftIconData('🍎', Color(0xFFE5A34A));
  }
  return const MinecraftIconData('🧱', Color(0xFF8A8F94));
}

class MinecraftItemIcon extends StatelessWidget {
  const MinecraftItemIcon({super.key, required this.id, this.size = 38});
  final String id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final data = iconForMinecraftId(id);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: data.color.withValues(alpha: .6)),
      ),
      child: Text(data.emoji, style: TextStyle(fontSize: size * .52)),
    );
  }
}
