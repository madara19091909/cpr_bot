import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/localization.dart';
import '../library/library_page.dart' show formatBytes;

String recognizeFile(String relPath, bool isDir) {
  final name = p.basename(relPath);
  if (isDir) {
    return switch (name) {
      'db' => 'LevelDB database',
      'behavior_packs' => 'Behavior packs',
      'resource_packs' => 'Resource packs',
      _ => 'Folder',
    };
  }
  if (name == 'level.dat' || name == 'level.dat_old') return 'World metadata (NBT)';
  if (name == 'levelname.txt') return 'World name (text)';
  if (name.startsWith('world_icon')) return 'World icon (image)';
  if (name == 'world_behavior_packs.json' || name == 'world_resource_packs.json') {
    return 'Pack list (JSON)';
  }
  if (p.split(relPath).contains('db')) {
    if (name.endsWith('.ldb') || name.endsWith('.sst')) return 'LevelDB table';
    if (name.endsWith('.log')) return 'LevelDB write-ahead log';
    if (name.startsWith('MANIFEST')) return 'LevelDB manifest';
    if (name == 'CURRENT') return 'LevelDB pointer';
    if (name == 'LOCK') return 'LevelDB lock file';
    if (name.startsWith('LOG')) return 'LevelDB info log';
  }
  if (name == 'manifest.json') return 'Pack manifest (JSON)';
  return 'Unknown';
}

const _textTypes = {'World name (text)', 'Pack list (JSON)', 'Pack manifest (JSON)', 'LevelDB pointer', 'LevelDB info log'};

class FilesPage extends StatefulWidget {
  const FilesPage({super.key, required this.rootPath});
  final String rootPath;
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _Row {
  _Row(this.entity, this.isDir, this.size, this.modified, this.type);
  final FileSystemEntity entity;
  final bool isDir;
  final int size;
  final DateTime? modified;
  final String type;
}

class _FilesPageState extends State<FilesPage> {
  late String _dir = widget.rootPath;
  List<_Row> _rows = [];
  String _filter = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = <_Row>[];
    try {
      await for (final e in Directory(_dir).list(followLinks: false)) {
        if (e is Link) continue; // never follow links
        final isDir = e is Directory;
        final st = await e.stat();
        rows.add(_Row(e, isDir, isDir ? 0 : st.size, st.modified,
            recognizeFile(p.relative(e.path, from: widget.rootPath), isDir)));
      }
      rows.sort((a, b) => a.isDir != b.isDir
          ? (a.isDir ? -1 : 1)
          : p.basename(a.entity.path).toLowerCase().compareTo(p.basename(b.entity.path).toLowerCase()));
      _error = null;
    } on FileSystemException catch (e) {
      _error = '${e.path}: ${e.osError?.message ?? e.message}';
    }
    if (mounted) setState(() => _rows = rows);
  }

  bool get _atRoot => p.equals(_dir, widget.rootPath);

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final shown = _rows.where((r) => p.basename(r.entity.path).toLowerCase().contains(_filter.toLowerCase())).toList();
    return PopScope(
      canPop: _atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _dir = p.dirname(_dir);
          _load();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(s.t('files'))),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s.t('filterName')),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          Align(alignment: AlignmentDirectional.centerStart,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: LtrText(p.relative(_dir, from: p.dirname(widget.rootPath))))),
          if (_error != null) Padding(padding: const EdgeInsets.all(12), child: LtrText(_error!)),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (_, i) {
                final r = shown[i];
                return ListTile(
                  dense: true,
                  leading: Icon(r.isDir ? Icons.folder : Icons.insert_drive_file_outlined),
                  title: LtrText(p.basename(r.entity.path)),
                  subtitle: Text('${r.type}${r.isDir ? '' : '  ·  ${formatBytes(r.size)}'}  ·  ${r.modified?.toLocal().toString().split('.').first ?? s.t('unknown')}'),
                  onTap: r.isDir
                      ? () {
                          _dir = r.entity.path;
                          _load();
                        }
                      : () => _details(r, s),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _details(_Row r, AppStrings s) async {
    final file = r.entity as File;
    final rel = p.relative(file.path, from: widget.rootPath);
    String? hash;
    String? preview;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(shrinkWrap: true, children: [
            LtrText(rel, style: Theme.of(ctx).textTheme.titleMedium),
            Text('${r.type} · ${r.size} B'),
            Wrap(spacing: 8, children: [
              OutlinedButton(
                  onPressed: () async {
                    final d = await sha256.bind(file.openRead()).first;
                    set(() => hash = d.toString());
                  },
                  child: Text(s.t('computeHash'))),
              OutlinedButton(
                  onPressed: () async {
                    final raf = await file.open();
                    try {
                      final b = await raf.read(512);
                      set(() => preview = _text(r) ? utf8.decode(b, allowMalformed: true) : _hexDump(b));
                    } finally {
                      await raf.close();
                    }
                  },
                  child: Text(s.t('preview'))),
              OutlinedButton(onPressed: () => _export(ctx, file, rel, s), child: Text(s.t('exportCopy'))),
            ]),
            if (hash != null) ...[
              LtrText('SHA-256: $hash'),
              TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: hash!)), child: Text(s.t('copyHex'))),
            ],
            if (preview != null) LtrText(preview!, style: const TextStyle(fontFamily: 'monospace')),
          ]),
        ),
      ),
    );
  }

  bool _text(_Row r) => _textTypes.contains(r.type);

  String _hexDump(Uint8List b) {
    final sb = StringBuffer();
    for (var i = 0; i < b.length; i += 16) {
      final end = i + 16 < b.length ? i + 16 : b.length;
      final chunk = b.sublist(i, end);
      sb.writeln('${i.toRadixString(16).padLeft(6, '0')}  '
          '${chunk.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ').padRight(47)}  '
          '${String.fromCharCodes(chunk.map((x) => x >= 32 && x < 127 ? x : 46))}');
    }
    return sb.toString();
  }

  Future<void> _export(BuildContext ctx, File file, String rel, AppStrings s) async {
    if (p.split(rel).first == 'db') {
      final ok = await showDialog<bool>(
        context: ctx,
        builder: (d) => AlertDialog(
          content: Text(s.t('sensitiveWarn')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(s.t('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(s.t('ok'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final dest = File(p.join(base.path, 'exports', p.basename(p.dirname(widget.rootPath)),
        '${DateTime.now().millisecondsSinceEpoch}_${p.basename(file.path)}'));
    await dest.parent.create(recursive: true);
    await file.copy(dest.path); // never overwrites: unique timestamped name
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${s.t('exported')}: ${dest.path}')));
    }
  }
}
