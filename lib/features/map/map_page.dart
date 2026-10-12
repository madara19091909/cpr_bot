import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/localization.dart';
import '../../parsers/bedrock_leveldb/bedrock_keys.dart';
import '../../services/map_renderer.dart';

/// Top-down block map built from real SubChunkPrefix records (read-only).
class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.worldPath});
  final String worldPath;
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  MapResult? _result;
  ui.Image? _image;
  int _dim = 0;
  bool _busy = false;
  String? _fatal;
  String _tapInfo = '';
  final _cx = TextEditingController();
  final _cz = TextEditingController();

  @override
  void initState() {
    super.initState();
    _render();
  }

  Future<void> _render() async {
    setState(() {
      _busy = true;
      _fatal = null;
    });
    final req = MapRequest(p.join(widget.worldPath, 'db'), _dim,
        centerBlockX: int.tryParse(_cx.text), centerBlockZ: int.tryParse(_cz.text));
    try {
      final r = await Isolate.run(() => renderMap(req));
      ui.Image? img;
      if (r.width > 0) {
        final c = Completer<ui.Image>();
        ui.decodeImageFromPixels(r.rgba, r.width, r.height, ui.PixelFormat.rgba8888, c.complete);
        img = await c.future;
      }
      if (!mounted) return;
      setState(() {
        _result = r;
        _image = img;
        _busy = false;
        _tapInfo = '';
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _fatal = '$e';
          _busy = false;
        });
      }
    }
  }

  void _onTap(Offset o) {
    final r = _result;
    if (r == null) return;
    final x = o.dx.floor(), z = o.dy.floor();
    if (x < 0 || z < 0 || x >= r.width || z >= r.height) return;
    final i = z * r.width + x;
    final n = r.nameIdx[i];
    setState(() => _tapInfo = n == 0xFFFF
        ? 'x=${r.originX + x} z=${r.originZ + z}: no data'
        : 'x=${r.originX + x} z=${r.originZ + z} y=${r.heights[i]}  ${r.names[n]}');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('map'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<int>(
              value: _dim,
              items: [
                for (final d in {0, 1, 2, ...?r?.availableDimensions})
                  DropdownMenuItem(value: d, child: Text(dimensionName(d))),
              ],
              onChanged: _busy ? null : (v) => setState(() => _dim = v ?? 0),
            ),
            SizedBox(width: 90, child: TextField(controller: _cx, keyboardType: TextInputType.number,
                decoration: InputDecoration(hintText: s.t('centerX')))),
            SizedBox(width: 90, child: TextField(controller: _cz, keyboardType: TextInputType.number,
                decoration: InputDecoration(hintText: s.t('centerZ')))),
            FilledButton(onPressed: _busy ? null : _render, child: Text(s.t('render'))),
          ]),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_fatal != null) Padding(padding: const EdgeInsets.all(8), child: LtrText(_fatal!)),
        if (r != null && !_busy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(r.width == 0
                ? s.t('mapEmpty')
                : '${s.t('chunksDrawn')}: ${r.chunksDrawn} / ${r.chunksInDimension}'
                    '${r.errors.isNotEmpty ? '  ·  ${s.t('errors')}: ${r.errors.length}' : ''}'
                    '${r.unmappedBlocks.isNotEmpty ? '  ·  ${s.t('unmapped')}: ${r.unmappedBlocks.length}' : ''}'),
          ),
        Expanded(
          child: _image == null
              ? const SizedBox.shrink()
              : ClipRect(
                  child: InteractiveViewer(
                    constrained: false,
                    minScale: 0.1,
                    maxScale: 24,
                    child: GestureDetector(
                      onTapDown: (d) => _onTap(d.localPosition),
                      child: SizedBox(
                        width: _image!.width.toDouble(),
                        height: _image!.height.toDouble(),
                        child: RawImage(image: _image, filterQuality: FilterQuality.none, fit: BoxFit.fill),
                      ),
                    ),
                  ),
                ),
        ),
        if (_tapInfo.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: LtrText(_tapInfo)),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(s.t('mapNote'), style: Theme.of(context).textTheme.bodySmall),
        ),
        if (r != null && r.errors.isNotEmpty)
          ExpansionTile(
            title: Text('${s.t('errors')} (${r.errors.length})'),
            children: [for (final e in r.errors.take(20)) ListTile(dense: true, title: LtrText(e))],
          ),
      ]),
    );
  }
}
