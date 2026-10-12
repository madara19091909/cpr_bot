import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/localization.dart';
import '../../services/world_scanner.dart';
import '../world_details/world_page.dart';

String formatBytes(int b) {
  const u = ['B', 'KiB', 'MiB', 'GiB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.scanImports(); // show previously imported copies
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(s.t('library')),
          actions: [
            PopupMenuButton<String>(
              tooltip: s.t('language'),
              icon: const Icon(Icons.language),
              onSelected: c.setLanguage,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'ar', child: Text('العربية')),
                PopupMenuItem(value: 'en', child: Text('English')),
              ],
            ),
          ],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                  onPressed: c.busy ? null : c.pickAndImport,
                  icon: const Icon(Icons.folder_open),
                  label: Text(s.t('pick'))),
              OutlinedButton(
                  onPressed: c.busy ? null : c.scanCommon,
                  child: Text(s.t('scanCommon'))),
              OutlinedButton(
                  onPressed: c.busy ? null : c.scanImports,
                  child: Text(s.t('scanImports'))),
            ]),
          ),
          if (c.busy) ...[
            const LinearProgressIndicator(),
            if (c.status != null)
              Padding(padding: const EdgeInsets.all(8), child: Text(s.t(c.status!))),
          ],
          Expanded(child: _list(s)),
        ]),
      ),
    );
  }

  Widget _list(AppStrings s) {
    final items = <Widget>[];
    if (c.worlds.isEmpty && !c.busy) {
      items.add(Padding(
          padding: const EdgeInsets.all(24), child: Text(s.t('noWorlds'))));
    }
    for (final w in c.worlds) {
      items.add(_card(s, w));
    }
    if (c.scanErrors.isNotEmpty) {
      items.add(ExpansionTile(
        title: Text('${s.t('errors')} (${c.scanErrors.length})'),
        children: [for (final e in c.scanErrors) ListTile(title: LtrText(e))],
      ));
    }
    return ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: items);
  }

  Widget _card(AppStrings s, WorldInfo w) => Card(
        child: ListTile(
          leading: Icon(w.levelDatReadable ? Icons.public : Icons.error_outline),
          title: Text(w.displayName ?? w.folderName),
          subtitle: LtrText(
              '${formatBytes(w.sizeBytes)} · ${w.fileCount} ${s.t('files')}\n${w.path}'),
          isThreeLine: true,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => WorldPage(controller: c, world: w))),
        ),
      );
}
