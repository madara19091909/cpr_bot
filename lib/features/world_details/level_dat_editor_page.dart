import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/localization.dart';
import '../../parsers/level_dat_parser.dart';
import '../../parsers/nbt/nbt.dart';
import '../../services/world_mutation_service.dart';

class LevelDatEditorPage extends StatefulWidget {
  const LevelDatEditorPage({
    super.key,
    required this.worldPath,
    required this.backupsRoot,
    required this.mutations,
  });
  final String worldPath;
  final Directory backupsRoot;
  final WorldMutationService mutations;

  @override
  State<LevelDatEditorPage> createState() => _LevelDatEditorPageState();
}

class _LevelDatEditorPageState extends State<LevelDatEditorPage> {
  final _name = TextEditingController();
  final _seed = TextEditingController();
  final _x = TextEditingController();
  final _y = TextEditingController();
  final _z = TextEditingController();
  LevelDat? _original;
  int? _gameType;
  int? _difficulty;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _seed, _x, _y, _z]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final dat = LevelDat.parse(await File(p.join(widget.worldPath, 'level.dat')).readAsBytes());
      _original = dat;
      _name.text = dat.levelName ?? '';
      _seed.text = dat.randomSeed?.toString() ?? '';
      _x.text = dat.spawnX?.toString() ?? '';
      _y.text = dat.spawnY?.toString() ?? '';
      _z.text = dat.spawnZ?.toString() ?? '';
      _gameType = dat.gameType;
      _difficulty = dat.difficulty;
    } on Object catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  int? _intOrNull(String text, String label) {
    if (text.trim().isEmpty) return null;
    final value = int.tryParse(text.trim());
    if (value == null) throw FormatException('$label must be an integer.');
    return value;
  }

  Future<void> _save() async {
    final original = _original;
    if (original == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final root = Map<String, NbtTag>.from(original.document.root);
      void update(String key, NbtTag? tag) {
        if (tag == null) {
          root.remove(key);
        } else {
          root[key] = tag;
        }
      }

      update('LevelName', _name.text.trim().isEmpty ? null : NbtTag.string(_name.text.trim()));
      update('RandomSeed', _intOrNull(_seed.text, 'Seed') == null
          ? null
          : NbtTag.long(_intOrNull(_seed.text, 'Seed')!));
      update('SpawnX', _intOrNull(_x.text, 'Spawn X') == null
          ? null
          : NbtTag.int32(_intOrNull(_x.text, 'Spawn X')!));
      update('SpawnY', _intOrNull(_y.text, 'Spawn Y') == null
          ? null
          : NbtTag.int32(_intOrNull(_y.text, 'Spawn Y')!));
      update('SpawnZ', _intOrNull(_z.text, 'Spawn Z') == null
          ? null
          : NbtTag.int32(_intOrNull(_z.text, 'Spawn Z')!));
      if (_gameType != null) update('GameType', NbtTag.int32(_gameType!));
      if (_difficulty != null) update('Difficulty', NbtTag.int32(_difficulty!));

      final updated = LevelDat(original.headerVersion, NbtDocument(original.document.rootName, root));
      await widget.mutations.updateLevelDat(
        world: Directory(widget.worldPath),
        backupsRoot: widget.backupsRoot,
        updated: updated,
      );
      _original = LevelDat.parse(await File(p.join(widget.worldPath, 'level.dat')).readAsBytes());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved. A verified pre-write backup was created.')),
        );
        Navigator.pop(context, true);
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(s.t('levelDatEditor'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('Only known top-level fields are edited. Unknown NBT fields are preserved. '
                'Close Minecraft first. Every save creates and verifies a SHA-256 backup before writing.'),
          )),
          if (_error != null) Card(color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!))),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'LevelName')),
          TextField(controller: _seed, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'RandomSeed (integer)')),
          DropdownButtonFormField<int>(
            value: _gameType,
            decoration: const InputDecoration(labelText: 'GameType'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('0 — Survival')),
              DropdownMenuItem(value: 1, child: Text('1 — Creative')),
              DropdownMenuItem(value: 2, child: Text('2 — Adventure')),
              DropdownMenuItem(value: 3, child: Text('3 — Spectator')),
            ],
            onChanged: (v) => setState(() => _gameType = v),
          ),
          DropdownButtonFormField<int>(
            value: _difficulty,
            decoration: const InputDecoration(labelText: 'Difficulty'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('0 — Peaceful')),
              DropdownMenuItem(value: 1, child: Text('1 — Easy')),
              DropdownMenuItem(value: 2, child: Text('2 — Normal')),
              DropdownMenuItem(value: 3, child: Text('3 — Hard')),
            ],
            onChanged: (v) => setState(() => _difficulty = v),
          ),
          const SizedBox(height: 8),
          Text('World spawn', style: Theme.of(context).textTheme.titleMedium),
          Row(children: [
            Expanded(child: TextField(controller: _x, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'SpawnX'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _y, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'SpawnY'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _z, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'SpawnZ'))),
          ]),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_saving ? s.t('saving') : s.t('saveChanges')),
          ),
        ],
      ),
    );
  }
}
