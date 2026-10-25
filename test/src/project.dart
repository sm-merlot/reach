import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A throwaway project on disk with its own git repository.
class TempProject {
  TempProject._(this.root);

  final String root;

  /// Creates a project named `app` with [files] committed on `main`.
  static Future<TempProject> create(Map<String, String> files) async {
    final dir = await Directory.systemTemp.createTemp('reach_test_');
    addTearDown(() => dir.delete(recursive: true));
    final t = TempProject._(dir.path);
    t.write({'pubspec.yaml': 'name: app\n', ...files});
    await t.git(['init', '-q', '-b', 'main']);
    await t.git(['config', 'user.email', 'test@example.com']);
    await t.git(['config', 'user.name', 'test']);
    await t.git(['config', 'commit.gpgsign', 'false']);
    await t.commit('initial');
    return t;
  }

  void write(Map<String, String> files) {
    for (final MapEntry(key: path, value: text) in files.entries) {
      final f = File(p.join(root, path));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(text);
    }
  }

  void delete(String path) => File(p.join(root, path)).deleteSync();

  Future<void> commit(String message) async {
    await git(['add', '-A']);
    await git(['commit', '-q', '--allow-empty', '-m', message]);
  }

  Future<String> git(List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: root);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
    }
    return (r.stdout as String).trim();
  }
}
