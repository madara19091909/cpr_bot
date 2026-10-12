import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../parsers/bedrock_leveldb/leveldb_reader.dart';
import '../../parsers/nbt/nbt.dart';
import '../../parsers/nbt/nbt_text.dart';

/// Edits a record value as a local draft. It intentionally does not overwrite
/// LevelDB files: a MANIFEST-aware Bedrock LevelDB writer is required first.
class DatabaseRecordEditorPage extends StatefulWidget {
  const DatabaseRecordEditorPage({
    super.key,
    required this.worldPath,
    required this.keyBytes,
    required this.valueBytes,
  });
  final String worldPath;
  final Uint8List keyBytes;
  final Uint8List valueBytes;

  @override
  State<DatabaseRecordEditorPage> createState() => _DatabaseRecordEditorPageState();
}

class _DatabaseRecordEditorPageState extends State<DatabaseRecordEditorPage> {
  late final TextEditingController _hex =
      TextEditingController(text: LevelDbReader.hex(widget.valueBytes));
  String? _error;
  String? _parsed;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _updateParsed(widget.valueBytes);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  Uint8List _decodeHex(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    if (compact.length.isOdd) throw const FormatException('Hex must contain pairs of digits.');
    if (!RegExp(r'^[0-9a-fA-F]*$').hasMatch(compact)) {
      throw const FormatException('Only hexadecimal characters are allowed.');
    }
    return Uint8List.fromList([
      for (var i = 0; i < compact.length; i += 2)
        int.parse(compact.substring(i, i + 2), radix: 16),
    ]);
  }

  void _updateParsed(Uint8List bytes) {
    try {
      final docs = NbtReader(bytes).readAllDocuments();
      _parsed = docs.map(nbtToText).join('\n---\n');
    } on Object {
      _parsed = null;
    }
  }

  Future<void> _saveDraft() async {
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final bytes = _decodeHex(_hex.text);
      final base = await getApplicationDocumentsDirectory();
      final draftDir = Directory(p.join(base.path, 'db-edit-drafts'));
      await draftDir.create(recursive: true);
      final worldName = p.basename(widget.worldPath).replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      final id = DateTime.now().millisecondsSinceEpoch;
      final out = File(p.join(draftDir.path, '${worldName}_$id.json'));
      await out.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'format': 1,
        'kind': 'mcmanger_db_record_draft',
        'worldPath': widget.worldPath,
        'keyHex': LevelDbReader.hex(widget.keyBytes),
        'originalValueSha256Note': 'Compare with the source before any future apply.',
        'valueHex': LevelDbReader.hex(bytes),
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'appliedToWorld': false,
      }));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Draft saved locally: ${out.path}. World database was not changed.')),
        );
        Navigator.pop(context);
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DB record editor')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Card(child: Padding(
        padding: EdgeInsets.all(12),
        child: Text('Draft editor only. Bedrock LevelDB records cannot safely be written back yet; '
            'saving here creates a local patch file and does NOT modify the world or .mcworld export. '
            'Do not treat this draft as applied.'),
      )),
      SelectableText('Key: ${LevelDbReader.hex(widget.keyBytes)}',
        style: const TextStyle(fontFamily: 'monospace')),
      const SizedBox(height: 12),
      TextField(
        controller: _hex,
        minLines: 6,
        maxLines: 14,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Value bytes (hex)',
          hintText: '0a 00 00 …',
        ),
        onChanged: (value) {
          try {
            final bytes = _decodeHex(value);
            setState(() {
              _updateParsed(bytes);
              _error = null;
            });
          } on Object catch (e) {
            setState(() => _error = '$e');
          }
        },
      ),
      if (_error != null) Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ),
      const SizedBox(height: 12),
      Text('Parsed NBT preview', style: Theme.of(context).textTheme.titleMedium),
      SelectableText(_parsed ?? 'Value is not valid NBT; raw hex draft is still possible.',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _saving || _error != null ? null : _saveDraft,
        icon: const Icon(Icons.save_as),
        label: Text(_saving ? 'Saving draft…' : 'Save local draft (not applied)'),
      ),
    ]),
  );
}
