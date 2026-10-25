import 'dart:convert';

import 'graph.dart';
import 'select.dart';

/// Which files the most tests depend on, and which tests depend on the most.
///
/// A file reached by most of the suite is one a change to which runs most of
/// the suite: the place to split responsibilities. A test that reaches most of
/// the code is either an end-to-end test on purpose, or a unit test pulling in
/// far more than it tests.
class Hotspots {
  Hotspots._(this.files, this.tests, this.testCount, this.sourceCount);

  /// Non-test files and how many tests reach each, widest first.
  final List<(String, int)> files;

  /// Tests and how many non-test files each reaches, widest first.
  final List<(String, int)> tests;

  final int testCount;
  final int sourceCount;

  static Hotspots of(ImportGraph graph) {
    final testSet = graph.tests.toSet();
    final sources = graph.files.where((f) => !testSet.contains(f)).toList();
    final reach = {for (final f in sources) f: 0};
    final perTest = <(String, int)>[];
    for (final t in graph.tests) {
      final closure = graph.closureOf(t);
      var n = 0;
      for (final f in closure) {
        if (reach.containsKey(f)) {
          reach[f] = reach[f]! + 1;
          n++;
        }
      }
      perTest.add((t, n));
    }
    int byCount((String, int) a, (String, int) b) =>
        b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1);
    return Hotspots._(
      [for (final e in reach.entries) (e.key, e.value)]..sort(byCount),
      perTest..sort(byCount),
      graph.tests.length,
      sources.length,
    );
  }
}

String _pct(int n, int of) =>
    of == 0 ? '0%' : '${(100 * n / of).toStringAsFixed(1)}%';

String headline(Selection s) => switch (s.mode) {
      Mode.full => 'reach: full run, ${s.total} tests',
      Mode.none => 'reach: 0/${s.total} tests',
      Mode.selected =>
        'reach: ${s.tests.length}/${s.total} tests (${_pct(s.tests.length, s.total)})',
    };

/// Plain text for a terminal.
String textReport(Selection s,
    {Hotspots? hotspots, int top = 10, bool listTests = true}) {
  final b = StringBuffer()..writeln(headline(s));
  for (final r in s.fullReasons) {
    b.writeln('  because $r');
  }
  if (s.changed.isNotEmpty) {
    b.writeln('changed:');
    for (final MapEntry(key: f, value: k) in s.changed.entries) {
      b.writeln('  ${_kindLabel(k).padRight(9)} $f');
    }
  }
  if (listTests && s.mode == Mode.selected) {
    b.writeln('tests:');
    for (final t in s.tests) {
      b.writeln('  $t');
    }
  }
  if (hotspots != null) {
    b
      ..writeln()
      ..writeln(
          'Widest reach (files by tests that reach them, of ${hotspots.testCount})');
    for (final (f, n) in hotspots.files.take(top)) {
      b.writeln('  ${n.toString().padLeft(5)}  $f');
    }
    b
      ..writeln()
      ..writeln(
          'Widest tests (by files they reach, of ${hotspots.sourceCount})');
    for (final (t, n) in hotspots.tests.take(top)) {
      b.writeln('  ${n.toString().padLeft(5)}  $t');
    }
  }
  return b.toString();
}

/// Markdown for `$GITHUB_STEP_SUMMARY`.
String markdownReport(Selection s,
    {Hotspots? hotspots,
    int top = 15,
    String? title,
    bool reportOnly = false}) {
  final b = StringBuffer()
    ..writeln('### ${title ?? 'reach'}')
    ..writeln();
  b.writeln('**${headline(s).replaceFirst('reach: ', '')}**'
      '${reportOnly && s.mode != Mode.full ? ' (report only: everything ran)' : ''}');
  b.writeln();
  if (s.fullReasons.isNotEmpty) {
    b.writeln('Full run because:');
    for (final r in s.fullReasons) {
      b.writeln('- $r');
    }
    b.writeln();
  }
  if (s.changed.isNotEmpty) {
    b
      ..writeln('<details><summary>${s.changed.length} changed files</summary>')
      ..writeln()
      ..writeln('| File | Counted as |')
      ..writeln('| --- | --- |');
    for (final MapEntry(key: f, value: k) in s.changed.entries) {
      b.writeln('| `$f` | ${_kindLabel(k)} |');
    }
    b
      ..writeln()
      ..writeln('</details>')
      ..writeln();
  }
  if (s.mode == Mode.selected) {
    b
      ..writeln('<details><summary>${s.tests.length} tests selected</summary>')
      ..writeln();
    for (final t in s.tests) {
      b.writeln('- `$t`');
    }
    b
      ..writeln()
      ..writeln('</details>')
      ..writeln();
  }
  if (hotspots != null) {
    b
      ..writeln('<details><summary>Widest reach</summary>')
      ..writeln()
      ..writeln('Files reached by the most tests (of ${hotspots.testCount}): '
          'a change to one of these runs that many.')
      ..writeln()
      ..writeln('| Tests | File |')
      ..writeln('| ---: | --- |');
    for (final (f, n) in hotspots.files.take(top)) {
      b.writeln('| $n | `$f` |');
    }
    b
      ..writeln()
      ..writeln('Tests that reach the most files (of ${hotspots.sourceCount}).')
      ..writeln()
      ..writeln('| Files | Test |')
      ..writeln('| ---: | --- |');
    for (final (t, n) in hotspots.tests.take(top)) {
      b.writeln('| $n | `$t` |');
    }
    b
      ..writeln()
      ..writeln('</details>');
  }
  return b.toString();
}

String jsonReport(Selection s, {Hotspots? hotspots}) =>
    const JsonEncoder.withIndent('  ').convert({
      'mode': s.mode.name,
      'selected': s.tests.length,
      'total': s.total,
      'tests': s.tests,
      'full_reasons': s.fullReasons,
      'changed': {for (final e in s.changed.entries) e.key: e.value.name},
      if (hotspots != null)
        'hotspots': {
          'files': [
            for (final (f, n) in hotspots.files) {'file': f, 'tests': n}
          ],
          'tests': [
            for (final (t, n) in hotspots.tests) {'test': t, 'files': n}
          ],
        },
    });

String _kindLabel(FileKind k) => switch (k) {
      FileKind.fullRun => 'full_run',
      FileKind.ignored => 'ignored',
      FileKind.graph => 'code',
      FileKind.removed => 'removed',
      FileKind.unknown => 'unknown',
    };
