import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/filesystem/saf_channel.dart';
import '../services/backup_service.dart';
import '../services/world_scanner.dart';

class AppController extends ChangeNotifier {
  AppController({SafChannel? saf, WorldScanner? scanner, BackupService? backups})
      : saf = saf ?? SafChannel(),
        scanner = scanner ?? WorldScanner(),
        backups = backups ?? BackupService();

  final SafChannel saf;
  final WorldScanner scanner;
  final BackupService backups;

  Locale locale = const Locale('ar'); // default Arabic
  bool busy = false;
  String? status;
  List<WorldInfo> worlds = [];
  List<String> scanErrors = [];
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    locale = Locale(_prefs!.getString('lang') ?? 'ar');
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    locale = Locale(code);
    await _prefs?.setString('lang', code);
    notifyListeners();
  }

  Future<Directory> importsRoot() async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'imports'));
  }

  Future<Directory> backupsRoot() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'backups'));
  }

  Future<Directory> restoresRoot() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'restored'));
  }

  Future<void> _scan(List<Directory> roots) async {
    busy = true;
    notifyListeners();
    final all = <WorldInfo>[];
    final errs = <String>[];
    for (final r in roots) {
      final res = await scanner.scan(r);
      all.addAll(res.worlds);
      errs.addAll(res.errors);
    }
    worlds = all;
    scanErrors = errs;
    busy = false;
    notifyListeners();
  }

  Future<void> scanCommon() =>
      _scan([for (final s in commonBedrockWorldPaths) Directory(s)]);

  Future<void> scanImports() async => _scan([await importsRoot()]);

  /// SAF pick -> read-only copy into app storage -> scan the copy.
  Future<void> pickAndImport() async {
    final uri = await saf.pickTree();
    if (uri == null) return;
    busy = true;
    status = 'copying';
    notifyListeners();
    try {
      final name = (await saf.treeName(uri)) ?? 'world';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final dest = Directory(p.join((await importsRoot()).path, '${stamp}_$name'));
      await dest.create(recursive: true);
      final r = await saf.copyTree(uri, dest.path);
      scanErrors = r.errors;
    } on Object catch (e) {
      scanErrors = ['$e'];
    }
    status = null;
    await scanImports();
  }
}
