import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/localization.dart';
import '../../parsers/bedrock_leveldb/bedrock_keys.dart';
import '../../parsers/bedrock_leveldb/errors.dart';
import '../../parsers/bedrock_leveldb/leveldb_reader.dart';
import '../../parsers/nbt/nbt.dart';
import '../../parsers/nbt/nbt_text.dart';
import '../../parsers/player_summary.dart';
import '../../services/minecraft_icon_catalog.dart';
import 'database_record_editor_page.dart';
import '../library/library_page.dart' show formatBytes;

/// Read-only explorer. Index building runs in a background isolate so large
/// databases do not freeze the UI. Values are read lazily, one at a time.
class DatabasePage extends StatefulWidget {
  const DatabasePage({super.key, required this.worldPath});
  final String worldPath;
  @override
  State<DatabasePage> createState() => _DatabasePageState();
}

class _DatabasePageState extends State<DatabasePage> {
  DbIndex? _index;
  String? _fatal;
  KeyFamily? _family;
  String _query = '';
  List<IndexEntry> _shown = [];
  Map<KeyFamily, int> _counts = {};
  late final LevelDbReader _reader =
      LevelDbReader(Directory(p.join(widget.worldPath, 'db')));

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final path = p.join(widget.worldPath, 'db');
    try {
      final idx = await Isolate.run(() => LevelDbReader(Directory(path)).buildIndex());
      final counts = <KeyFamily, int>{};
      for (final e in idx.entries) {
        final f = classifyKey(e.key).family;
        counts[f] = (counts[f] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() {
        _index = idx;
        _counts = counts;
        _apply();
      });
    } on LevelDbException catch (e) {
      if (mounted) setState(() => _fatal = e.toString());
    } on Object catch (e) {
      if (mounted) setState(() => _fatal = '$e');
    }
  }

  void _apply() {
    final q = _query.trim().toLowerCase();
    _shown = [
      for (final e in _index!.entries)
        if ((_family == null || classifyKey(e.key).family == _family) &&
            (q.isEmpty ||
                LevelDbReader.hex(e.key).contains(q.replaceAll(' ', '')) ||
                latin1.decode(e.key, allowInvalid: true).toLowerCase().contains(q)))
          e
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final idx = _index;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('database'))),
      body: _fatal != null
          ? Padding(padding: const EdgeInsets.all(16), child: LtrText(_fatal!))
          : idx == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Text('${s.t('readOnly')}\n${s.t('patternNote')}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  if (idx.errors.isNotEmpty)
                    ExpansionTile(
                      leading: const Icon(Icons.warning_amber, color: Colors.orange),
                      title: Text('${s.t('dbCorrupt')} (${idx.errors.length})'),
                      children: [for (final e in idx.errors) ListTile(title: LtrText(e))],
                    ),
                  if (idx.warnings.isNotEmpty)
                    ExpansionTile(
                      title: Text('${s.t('dbWarnings')} (${idx.warnings.length})'),
                      children: [for (final e in idx.warnings) ListTile(title: LtrText(e))],
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search), hintText: s.t('search')),
                      onChanged: (v) => setState(() {
                        _query = v;
                        _apply();
                      }),
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      _chip(s.t('allFamilies'), idx.entries.length, _family == null,
                          () => setState(() {
                                _family = null;
                                _apply();
                              })),
                      for (final e in _counts.entries)
                        _chip(e.key.name, e.value, _family == e.key,
                            () => setState(() {
                                  _family = e.key;
                                  _apply();
                                })),
                    ]),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _shown.length,
                      itemBuilder: (_, i) {
                        final e = _shown[i];
                        final info = classifyKey(e.key);
                        return ListTile(
                          dense: true,
                          title: LtrText(info.label),
                          subtitle: LtrText(
                              '${_keyText(e.key, info)}  ·  ${formatBytes(e.valueLength)}'),
                          onTap: () => _showValue(e, info, s),
                        );
                      },
                    ),
                  ),
                ]),
    );
  }

  Widget _chip(String label, int n, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FilterChip(label: Text('$label ($n)'), selected: sel, onSelected: (_) => onTap()),
      );

  String _keyText(Uint8List k, KeyInfo i) {
    if (i.isChunk) {
      final sub = i.subChunk == null ? '' : ' y=${i.subChunk}';
      return '${dimensionName(i.dimension)} x=${i.x} z=${i.z}$sub';
    }
    final h = LevelDbReader.hex(k);
    return h.length > 48 ? '${h.substring(0, 48)}…' : h;
  }

  Future<void> _showValue(IndexEntry e, KeyInfo info, AppStrings s) async {
    Uint8List? value;
    String? err;
    try {
      value = await _reader.readValue(e);
    } on Object catch (ex) {
      err = '$ex';
    }
    if (!mounted) return;
    String? parsed;
    PlayerSummary? player;
    if (value != null && value.isNotEmpty && value[0] == 10) {
      try {
        final docs = NbtReader(value).readAllDocuments();
        parsed = docs.map(nbtToText).join('\n---\n');
        if (info.family == KeyFamily.localPlayer || info.family == KeyFamily.player) {
          player = PlayerSummary(docs.first);
        }
      } on NbtException {
        parsed = null;
      }
    }
    String hexDump(Uint8List v) {
      final n = v.length > 512 ? 512 : v.length;
      final h = LevelDbReader.hex(Uint8List.sublistView(v, 0, n));
      return v.length > n ? '$h…' : h;
    }

    // ignore: use_build_context_synchronously
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
          Text(info.label, style: Theme.of(ctx).textTheme.titleMedium),
          LtrText('key: ${LevelDbReader.hex(e.key)}'),
          LtrText('${s.t('valueSize')}: ${e.valueLength} B   seq=${e.sequence}   ${e.file}'),
          TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: LevelDbReader.hex(e.key))),
              icon: const Icon(Icons.copy),
              label: Text(s.t('copyHex'))),
          if (value != null)
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DatabaseRecordEditorPage(
                    worldPath: widget.worldPath,
                    keyBytes: e.key,
                    valueBytes: value!,
                  ),
                ));
              },
              icon: const Icon(Icons.edit_note),
              label: const Text('Edit DB record (draft only)'),
            ),
          if (err != null) LtrText(err),
          if (player != null) ...[
            const Divider(),
            Text(s.t('players'), style: Theme.of(ctx).textTheme.titleSmall),
            LtrText('Pos: ${player.position?.join(', ') ?? s.t('unknown')}'),
            LtrText('Rotation: ${player.rotation?.join(', ') ?? s.t('unknown')}'),
            LtrText('DimensionId: ${player.dimensionId ?? s.t('unknown')}'),
            LtrText('Level: ${player.experienceLevel ?? s.t('unknown')}'),
            for (final it in player.inventory ?? const <InventoryItem>[])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  MinecraftItemIcon(id: it.name ?? 'unknown', size: 34),
                  const SizedBox(width: 8),
                  Expanded(child: LtrText(
                    'slot ${it.slot ?? '?'}: ${it.name ?? '?'} x${it.count ?? '?'} (dmg ${it.damage ?? '?'})')),
                ]),
              ),
          ],
          const Divider(),
          Text(s.t('parsedView'), style: Theme.of(ctx).textTheme.titleSmall),
          parsed != null ? LtrText(parsed) : Text(s.t('noParse')),
          const Divider(),
          Text(s.t('rawView'), style: Theme.of(ctx).textTheme.titleSmall),
          if (value != null) LtrText(hexDump(value), style: const TextStyle(fontFamily: 'monospace')),
        ]),
      ),
    );
  }
}
