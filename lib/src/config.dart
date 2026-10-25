import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// What `reach.yaml` says, or the defaults when there is none.
///
/// Every changed file lands in exactly one of four places, checked in this
/// order:
///
/// 1. [fullRun]: the whole suite runs. Files every test depends on without
///    importing them (`pubspec.lock`, `dart_test.yaml`).
/// 2. [ignore]: no test can see it (docs, native code a VM test never loads).
/// 3. A `.dart` file under one of the [roots]: the tests that reach it run.
/// 4. Anything else: the whole suite runs. A fixture, an asset or a file type
///    nobody listed costs a full run rather than a skipped test.
class ReachConfig {
  ReachConfig({
    required this.roots,
    required this.tests,
    required this.fullRun,
    required this.ignore,
  });

  /// Directories whose `.dart` files make up the graph. Test helpers live
  /// here too, which is why `test` is a root and not only the tests in it.
  final List<String> roots;

  /// Which files in the graph are tests.
  final Glob tests;

  final List<Glob> fullRun;
  final List<Glob> ignore;

  static const fileName = 'reach.yaml';

  static const defaultRoots = ['lib', 'test'];
  static const defaultTests = 'test/**_test.dart';
  static const defaultFullRun = [
    'pubspec.yaml',
    'pubspec.lock',
    'analysis_options.yaml',
    'dart_test.yaml',
    'build.yaml',
    fileName,
  ];
  static const defaultIgnore = ['**.md', 'LICENSE'];

  /// Reads `reach.yaml` from [projectRoot], or returns the defaults.
  ///
  /// `full_run` and `ignore` in the file add to the defaults rather than
  /// replace them, so a project cannot forget `pubspec.lock` by listing its
  /// own extras.
  static ReachConfig load(String projectRoot) {
    final file = File(p.join(projectRoot, fileName));
    if (!file.existsSync()) return fromYaml(null);
    return fromYaml(file.readAsStringSync(), source: file.path);
  }

  static ReachConfig fromYaml(String? text, {String source = fileName}) {
    final doc =
        text == null ? null : loadYaml(text, sourceUrl: Uri.file(source));
    if (doc != null && doc is! YamlMap) {
      throw FormatException('$source: expected a map at the top level');
    }
    final map = doc as YamlMap?;
    List<String> strings(String key) {
      final v = map?[key];
      if (v == null) return const [];
      if (v is YamlList && v.every((e) => e is String)) {
        return v.cast<String>().toList();
      }
      throw FormatException('$source: "$key" must be a list of strings');
    }

    final known = {'roots', 'tests', 'full_run', 'ignore'};
    for (final key in map?.keys ?? const <Object?>[]) {
      if (!known.contains(key)) {
        throw FormatException(
            '$source: unknown key "$key" (expected ${known.join(', ')})');
      }
    }

    final roots = strings('roots');
    final tests = map?['tests'];
    if (tests != null && tests is! String) {
      throw FormatException('$source: "tests" must be a glob string');
    }
    return ReachConfig(
      roots: roots.isEmpty ? defaultRoots : roots,
      tests: Glob((tests as String?) ?? defaultTests),
      fullRun:
          [...defaultFullRun, ...strings('full_run')].map(Glob.new).toList(),
      ignore: [...defaultIgnore, ...strings('ignore')].map(Glob.new).toList(),
    );
  }

  bool isUnderRoot(String path) =>
      roots.any((r) => path == r || p.posix.isWithin(r, path));

  bool isTest(String path) => tests.matches(path);
}
