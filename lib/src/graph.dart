import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config.dart';
import 'directives.dart';

/// Every `.dart` file under the configured roots and what each one imports,
/// exports or includes as a part, as paths relative to the project root.
///
/// Only edges between files in the graph are kept. Other packages and the SDK
/// are outside it: a change to them is a `pubspec.lock` change, which runs
/// everything anyway.
class ImportGraph {
  ImportGraph._(this.files, this._deps, this.tests);

  /// Every file in the graph, sorted.
  final List<String> files;

  /// The test files in the graph, sorted.
  final List<String> tests;

  final Map<String, Set<String>> _deps;
  Map<String, Set<String>>? _dependents;

  /// What [file] imports, exports or includes, within the graph.
  Set<String> depsOf(String file) => _deps[file] ?? const {};

  bool contains(String file) => _deps.containsKey(file);

  /// Builds the graph for the project at [root].
  static ImportGraph build(String root, ReachConfig config) {
    final package = _packageName(root);
    final sources = <String, String>{};
    for (final r in config.roots) {
      final dir = Directory(p.join(root, r));
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final rel = p.posix.joinAll(p.split(p.relative(e.path, from: root)));
        sources[rel] = e.readAsStringSync();
      }
    }
    return fromSources(sources, config, packageName: package);
  }

  /// Builds the graph from file contents keyed by relative path. The
  /// filesystem-free half of [build], for tests.
  static ImportGraph fromSources(
    Map<String, String> sources,
    ReachConfig config, {
    String? packageName,
  }) {
    final deps = <String, Set<String>>{};
    for (final MapEntry(key: file, value: text) in sources.entries) {
      final out = <String>{};
      for (final uri in directiveUris(text)) {
        final target = resolve(uri, from: file, packageName: packageName);
        if (target != null && sources.containsKey(target) && target != file) {
          out.add(target);
        }
      }
      deps[file] = out;
    }
    final files = deps.keys.toList()..sort();
    final tests = files.where(config.isTest).toList();
    return ImportGraph._(files, deps, tests);
  }

  /// The project-relative path [uri] points at, or null when it is outside
  /// the project (`dart:`, another package, a URL).
  static String? resolve(String uri,
      {required String from, String? packageName}) {
    if (uri.startsWith('dart:')) return null;
    if (uri.startsWith('package:')) {
      final rest = uri.substring('package:'.length);
      final slash = rest.indexOf('/');
      if (slash < 0 || packageName == null) return null;
      if (rest.substring(0, slash) != packageName) return null;
      return p.posix.normalize('lib/${rest.substring(slash + 1)}');
    }
    if (Uri.tryParse(uri)?.hasScheme ?? true) return null;
    final joined = p.posix.normalize(p.posix.join(p.posix.dirname(from), uri));
    return joined.startsWith('../') ? null : joined;
  }

  /// Files that depend on [file], directly.
  Set<String> dependentsOf(String file) {
    final d = _dependents ??= () {
      final m = <String, Set<String>>{};
      for (final MapEntry(key: from, value: to) in _deps.entries) {
        for (final t in to) {
          (m[t] ??= {}).add(from);
        }
      }
      return m;
    }();
    return d[file] ?? const {};
  }

  /// Every file that depends on any of [changed], directly or through others,
  /// plus the changed files themselves.
  Set<String> reachedBy(Iterable<String> changed) {
    final seen = <String>{};
    final queue = Queue<String>();
    for (final c in changed) {
      if (seen.add(c)) queue.add(c);
    }
    while (queue.isNotEmpty) {
      for (final d in dependentsOf(queue.removeFirst())) {
        if (seen.add(d)) queue.add(d);
      }
    }
    return seen;
  }

  /// Every file [file] depends on, directly or through others, plus itself.
  Set<String> closureOf(String file) {
    final seen = <String>{file};
    final queue = Queue<String>.of([file]);
    while (queue.isNotEmpty) {
      for (final d in depsOf(queue.removeFirst())) {
        if (seen.add(d)) queue.add(d);
      }
    }
    return seen;
  }

  static String? _packageName(String root) {
    final f = File(p.join(root, 'pubspec.yaml'));
    if (!f.existsSync()) return null;
    final doc = loadYaml(f.readAsStringSync());
    return doc is YamlMap && doc['name'] is String
        ? doc['name'] as String
        : null;
  }
}
