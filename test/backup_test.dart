import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mc_manger/core/filesystem/safe_path.dart';
import 'package:mc_manger/core/jobs/cancel_token.dart';
import 'package:mc_manger/services/backup_service.dart';
import 'package:mc_manger/services/world_scanner.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late Directory world;
  late Directory backups;
  final svc = BackupService();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mcm_test_');
    world = Directory(p.join(tmp.path, 'worlds', 'abc123'))..createSync(recursive: true);
    File(p.join(world.path, 'level.dat')).writeAsBytesSync(List.generate(100, (i) => i));
    File(p.join(world.path, 'levelname.txt')).writeAsStringSync('My World\n');
    Directory(p.join(world.path, 'db')).createSync();
    File(p.join(world.path, 'db', 'CURRENT')).writeAsStringSync('MANIFEST-000001\n');
    File(p.join(world.path, 'db', '000003.ldb')).writeAsBytesSync(List.filled(5000, 7));
    Directory(p.join(world.path, 'empty_dir')).createSync();
    backups = Directory(p.join(tmp.path, 'backups'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, String> snapshot(Directory d) => {
        for (final f in d.listSync(recursive: true, followLinks: false).whereType<File>())
          p.relative(f.path, from: d.path): f.readAsBytesSync().join(','),
      };

  test('safe path rules', () {
    expect(isSafeRelativePath('db/000003.ldb'), isTrue);
    for (final bad in ['', '/etc/passwd', '../x', 'a/../b', 'a//b', r'a\b', 'C:x', './a']) {
      expect(isSafeRelativePath(bad), isFalse, reason: bad);
    }
    expect(sanitizeFileName('../../My World!'), 'My_World');
  });

  test('scanner finds world, reads name, and does not modify it', () async {
    final before = snapshot(world);
    final res = await WorldScanner().scan(Directory(p.join(tmp.path, 'worlds')));
    expect(res.worlds, hasLength(1));
    final w = res.worlds.single;
    expect(w.displayName, 'My World');
    expect(w.hasDb, isTrue);
    expect(w.fileCount, 4);
    expect(w.sizeBytes, 100 + 9 + 16 + 5000);
    expect(snapshot(world), before);
  });

  test('scanner reports missing directory instead of throwing', () async {
    final res = await WorldScanner().scan(Directory(p.join(tmp.path, 'nope')));
    expect(res.worlds, isEmpty);
    expect(res.errors, isNotEmpty);
  });

  test('backup -> verify -> restore yields identical files; source untouched', () async {
    final before = snapshot(world);
    final info = await svc.createBackup(source: world, backupsRoot: backups, name: 'My World');
    expect(info.fileCount, 4);
    expect(info.consistency, 'unverified_snapshot');
    expect((await svc.verify(info.directory)).ok, isTrue);

    final dest = Directory(p.join(tmp.path, 'restored'));
    await svc.restore(backupDir: info.directory, destination: dest);
    expect(snapshot(dest), before);
    expect(Directory(p.join(dest.path, 'empty_dir')).existsSync(), isTrue);
    expect(snapshot(world), before);
    expect(Directory('${dest.path}.partial').existsSync(), isFalse);
  });

  test('verify detects corruption, deletion and extra files', () async {
    final info = await svc.createBackup(source: world, backupsRoot: backups);
    final ldb = File(p.join(info.directory.path, 'world', 'db', '000003.ldb'));
    ldb.writeAsBytesSync(List.filled(5000, 8)); // same size, different content
    var r = await svc.verify(info.directory);
    expect(r.ok, isFalse);
    expect(r.problems.single, startsWith('Hash mismatch'));

    ldb.deleteSync();
    r = await svc.verify(info.directory);
    expect(r.problems.single, startsWith('Missing file'));

    File(p.join(info.directory.path, 'world', 'extra.bin')).writeAsBytesSync([1]);
    r = await svc.verify(info.directory);
    expect(r.problems.any((e) => e.startsWith('Extra file')), isTrue);
  });

  test('restore refuses corrupt backup and leaves no destination', () async {
    final info = await svc.createBackup(source: world, backupsRoot: backups);
    File(p.join(info.directory.path, 'world', 'level.dat')).writeAsBytesSync([0]);
    final dest = Directory(p.join(tmp.path, 'restored'));
    await expectLater(svc.restore(backupDir: info.directory, destination: dest),
        throwsA(isA<BackupException>()));
    expect(dest.existsSync(), isFalse);
    expect(Directory('${dest.path}.partial').existsSync(), isFalse);
  });

  test('restore never overwrites an existing destination', () async {
    final info = await svc.createBackup(source: world, backupsRoot: backups);
    final dest = Directory(p.join(tmp.path, 'existing'))..createSync();
    File(p.join(dest.path, 'keep.txt')).writeAsStringSync('keep');
    await expectLater(svc.restore(backupDir: info.directory, destination: dest),
        throwsA(isA<BackupException>()));
    expect(File(p.join(dest.path, 'keep.txt')).readAsStringSync(), 'keep');
  });

  test('refuses recursive backup into the source world', () async {
    await expectLater(
        svc.createBackup(source: world, backupsRoot: Directory(p.join(world.path, 'bk'))),
        throwsA(isA<BackupException>()));
  });

  test('refuses non-world source and does not overwrite same-named backup', () async {
    final notWorld = Directory(p.join(tmp.path, 'plain'))..createSync();
    await expectLater(svc.createBackup(source: notWorld, backupsRoot: backups),
        throwsA(isA<BackupException>()));
    final t = DateTime.utc(2026, 1, 1);
    await svc.createBackup(source: world, backupsRoot: backups, now: t);
    await expectLater(svc.createBackup(source: world, backupsRoot: backups, now: t),
        throwsA(isA<BackupException>()));
  });

  test('cancellation cleans up partial output', () async {
    final token = CancelToken()..cancel();
    await expectLater(
        svc.createBackup(source: world, backupsRoot: backups, cancel: token),
        throwsA(isA<OperationCancelled>()));
    final leftovers = backups.existsSync() ? backups.listSync() : [];
    expect(leftovers, isEmpty);
  });

  test('tampered manifest with traversal path is rejected', () async {
    final info = await svc.createBackup(source: world, backupsRoot: backups);
    final mf = File(p.join(info.directory.path, 'manifest.json'));
    final m = jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>;
    (m['files'] as List).add({'path': '../../evil', 'size': 1, 'sha256': 'x'});
    mf.writeAsStringSync(jsonEncode(m));
    final r = await svc.verify(info.directory);
    expect(r.ok, isFalse);
    expect(r.problems.any((e) => e.startsWith('Unsafe path')), isTrue);
  });

  test('list reports incomplete .partial backups; delete refuses non-backups', () async {
    Directory(p.join(backups.path, 'x_20260101_000000.partial')).createSync(recursive: true);
    final l = await svc.list(backups);
    expect(l.single.incomplete, isTrue);
    final other = Directory(p.join(tmp.path, 'not_a_backup'))..createSync();
    await expectLater(svc.delete(other), throwsA(isA<BackupException>()));
    expect(other.existsSync(), isTrue);
  });
}
