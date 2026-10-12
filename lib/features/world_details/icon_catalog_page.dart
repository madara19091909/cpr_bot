import 'package:flutter/material.dart';

import '../../services/minecraft_icon_catalog.dart';

class IconCatalogPage extends StatefulWidget {
  const IconCatalogPage({super.key});
  @override
  State<IconCatalogPage> createState() => _IconCatalogPageState();
}

class _IconCatalogPageState extends State<IconCatalogPage> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final entries = minecraftIconCatalog.entries
        .where((e) => e.key.toLowerCase().contains(_query.toLowerCase()))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Scaffold(
      appBar: AppBar(title: const Text('Block & item icons')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search Minecraft ID (e.g. diamond_sword)',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('Offline symbol approximations; official Minecraft sprite textures are not bundled.'),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: .95,
            ),
            itemCount: entries.length,
            itemBuilder: (_, i) {
              final e = entries[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    MinecraftItemIcon(id: e.key, size: 48),
                    const SizedBox(height: 6),
                    Text(e.key.replaceFirst('minecraft:', ''),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
