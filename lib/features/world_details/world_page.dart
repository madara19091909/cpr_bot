import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_controller.dart';
import '../../app/localization.dart';
import '../../parsers/level_dat_parser.dart';
import '../../parsers/nbt/nbt.dart';
import '../../services/backup_service.dart';
import '../../services/world_mutation_service.dart';
import '../../services/mcworld_export_service.dart';
import 'level_dat_editor_page.dart';
import 'icon_catalog_page.dart';
import '../../services/world_scanner.dart';
import '../database_explorer/database_page.dart';
import '../map/map_page.dart';
import '../world_files/files_page.dart';
import '../library/library_page.dart' show formatBytes;

class WorldPage extends StatefulWidget {
  const WorldPage({super.key, required this.controller, required this.world});
  final AppController controller;
  final WorldInfo world;
  @override
  State<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends State<WorldPage> {
  LevelDat? _level;
  String? _parseError;
  List<BackupInfo> _backups = [];
  bool _working = false;
  double? _progress;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(p.join(widget.world.path, 'level.dat')).readAsBytes();
      _level = LevelDat.parse(bytes);
    } on Object catch (e) {
      _parseError = e is NbtException ? e.toString() : '$e';
    }
    _backups = await c.backups.list(await c.backupsRoot());
    if (mounted) setState(() {});
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _working = true;
      _progress = null;
    });
    try {
      await job();
    } on Object catch (e) {
      _toast('$e');
    }
    _backups = await c.backups.list(await c.backupsRoot());
    if (mounted) setState(() => _working = false);
  }

  Future<void> _create() => _run(() async {
        final info = await c.backups.createBackup(
          source: Directory(widget.world.path),
          backupsRoot: await c.backupsRoot(),
          name: widget.world.displayName ?? widget.world.folderName,
          onProgress: (d, t) => setState(() => _progress = t == 0 ? 1 : d / t),
        );
        _toast('${info.name}: ${info.fileCount} files, ${formatBytes(info.totalBytes)}');
      });

  Future<void> _verify(BackupInfo b) => _run(() async {
        final r = await c.backups.verify(b.directory);
        _toast(r.ok
            ? 'OK: ${r.filesChecked} files verified'
            : '${r.problems.length} problem(s): ${r.problems.first}');
      });

  Future<void> _restore(BackupInfo b) => _run(() async {
        final root = await c.restoresRoot();
        final dest = Directory(p.join(root.path, '${b.name}_restored'));
        await root.create(recursive: true);
        await c.backups.restore(backupDir: b.directory, destination: dest);
        _toast('Restored to ${dest.path}');
      });

  Future<void> _delete(BackupInfo b, AppStrings s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s.t('confirmDelete')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('delete'))),
        ],
      ),
    );
    if (ok == true) await _run(() => c.backups.delete(b.directory));
  }


  Future<void> _editLevelDat() async {
    final backupRoot = await c.backupsRoot();
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => LevelDatEditorPage(
        worldPath: widget.world.path,
        backupsRoot: backupRoot,
        mutations: WorldMutationService(c.backups),
      ),
    ));
    if (changed == true) await _load();
  }

  Future<void> _exportMcworld() async {
    await _run(() async {
      final base = await getExternalStorageDirectory() ?? await Directory.systemTemp.createTemp('mcmanger');
      final file = await McWorldExportService().exportWorld(
        Directory(widget.world.path), Directory(p.join(base.path, 'exports', 'mcworld')));
      await Share.shareXFiles([XFile(file.path)],
          text: 'MC Manger world export — import this .mcworld into Minecraft.');
      _toast('Created .mcworld: ${file.path}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final w = widget.world;
    final u = s.t('unknown');
    String v(Object? x) => x?.toString() ?? u;
    final l = _level;
    return Scaffold(
      appBar: AppBar(title: Text(w.displayName ?? w.folderName)),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(child: Column(children: [
          _row(s.t('size'), formatBytes(w.sizeBytes)),
          _row(s.t('files'), '${w.fileCount}'),
          _row(s.t('modified'), v(w.lastModified?.toLocal())),
          _row(s.t('hasLevelDat'), s.t(w.hasLevelDat ? 'yes' : 'no')),
          _row(s.t('hasDb'), s.t(w.hasDb ? 'yes' : 'no')),
          _row(s.t('readable'), s.t(w.levelDatReadable ? 'yes' : 'no')),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(s.t('editLevelDat')),
            subtitle: const Text('Edits are backed up and verified before writing'),
            onTap: _working ? null : _editLevelDat,
          ),
          ListTile(
            leading: const Icon(Icons.grid_view),
            title: const Text('Block & item icons'),
            subtitle: const Text('Offline catalog of common Minecraft IDs'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const IconCatalogPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text(s.t('exportMcworld')),
            subtitle: const Text('Builds a Minecraft-importable archive without changing the source'),
            onTap: _working ? null : _exportMcworld,
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(s.t('files')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => FilesPage(rootPath: w.path))),
          ),
          ListTile(
            enabled: w.hasDb,
            leading: const Icon(Icons.map),
            title: Text(s.t('map')),
            trailing: const Icon(Icons.chevron_right),
            onTap: w.hasDb
                ? () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MapPage(worldPath: w.path)))
                : null,
          ),
          ListTile(
            enabled: w.hasDb,
            leading: const Icon(Icons.storage),
            title: Text(s.t('database')),
            trailing: const Icon(Icons.chevron_right),
            onTap: w.hasDb
                ? () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DatabasePage(worldPath: w.path)))
                : null,
          ),
        ])),
        const SizedBox(height: 8),
        Card(child: Column(children: [
          ListTile(title: Text(s.t('metadata'), style: Theme.of(context).textTheme.titleMedium)),
          if (_parseError != null)
            ListTile(title: Text(s.t('parseFailed')), subtitle: LtrText(_parseError!)),
          if (l != null) ...[
            _row(s.t('levelName'), v(l.levelName)),
            _row(s.t('gameType'), v(l.gameType)),
            _row(s.t('difficulty'), v(l.difficulty)),
            _row(s.t('spawn'),
                l.spawnX == null ? u : '${l.spawnX}, ${v(l.spawnY)}, ${v(l.spawnZ)}'),
            _row(s.t('seed'), v(l.randomSeed)),
            _row(s.t('lastVersion'), v(l.lastOpenedWithVersionString)),
            ListTile(
              dense: true,
              title: Text(s.t('otherKeys')),
              subtitle: LtrText(l.uninterpretedKeys.join(', ')),
            ),
          ],
        ])),
        const SizedBox(height: 8),
        Card(child: Column(children: [
          ListTile(
            title: Text(s.t('backups'), style: Theme.of(context).textTheme.titleMedium),
            trailing: FilledButton(
                onPressed: _working ? null : _create, child: Text(s.t('createBackup'))),
          ),
          ListTile(dense: true, title: Text(s.t('unverifiedNote'))),
          if (_working) LinearProgressIndicator(value: _progress),
          for (final b in _backups) _backupTile(s, b),
        ])),
        if (w.errors.isNotEmpty)
          ExpansionTile(
            title: Text('${s.t('errors')} (${w.errors.length})'),
            children: [for (final e in w.errors) ListTile(title: LtrText(e))],
          ),
      ]),
    );
  }

  Widget _row(String k, String val) => ListTile(
      dense: true, title: Text(k), trailing: LtrText(val));

  Widget _backupTile(AppStrings s, BackupInfo b) => ListTile(
        title: LtrText(b.name),
        subtitle: Text(b.incomplete
            ? s.t('incomplete')
            : '${b.fileCount} ${s.t('files')} · ${formatBytes(b.totalBytes)}'),
        trailing: Wrap(children: [
          if (!b.incomplete) ...[
            IconButton(
                tooltip: s.t('verify'),
                onPressed: _working ? null : () => _verify(b),
                icon: const Icon(Icons.verified_outlined)),
            IconButton(
                tooltip: s.t('restore'),
                onPressed: _working ? null : () => _restore(b),
                icon: const Icon(Icons.restore)),
          ],
          IconButton(
              tooltip: s.t('delete'),
              onPressed: _working ? null : () => _delete(b, s),
              icon: const Icon(Icons.delete_outline)),
        ]),
      );
}
