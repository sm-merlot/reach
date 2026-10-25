import 'dart:convert';

import 'package:path/path.dart' as p;

/// The test files that failed, from `dart test` / `flutter test` JSON reporter
/// output (`--file-reporter json:<path>` or `--reporter json`): one JSON
/// event per line.
///
/// A file that failed to load (a compile error) counts as failed: its
/// "loading" test fails like any other.
///
/// Paths come back relative to [root], in posix form.
Set<String> failedTestFiles(String eventsJsonLines, {required String root}) {
  final suitePath = <int, String>{};
  final testSuite = <int, int>{};
  final failed = <String>{};
  for (final line in const LineSplitter().convert(eventsJsonLines)) {
    if (!line.startsWith('{')) continue; // the runner's own chatter
    final Object? e;
    try {
      e = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (e is! Map<String, Object?>) continue;
    switch (e['type']) {
      case 'suite':
        final s = e['suite'];
        if (s is Map<String, Object?> &&
            s['id'] is int &&
            s['path'] is String) {
          suitePath[s['id'] as int] = s['path'] as String;
        }
      case 'testStart':
        final t = e['test'];
        if (t is Map<String, Object?> &&
            t['id'] is int &&
            t['suiteID'] is int) {
          testSuite[t['id'] as int] = t['suiteID'] as int;
        }
      case 'testDone' when e['result'] != 'success':
      case 'error':
        final suite = testSuite[e['testID']];
        final path = suite == null ? null : suitePath[suite];
        if (path != null) failed.add(_relative(path, root));
    }
  }
  return failed;
}

String _relative(String path, String root) {
  final abs = p.isAbsolute(path) ? path : p.join(root, path);
  return p.posix.joinAll(p.split(p.relative(abs, from: root)));
}
