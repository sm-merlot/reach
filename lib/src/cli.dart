import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'changes.dart';
import 'config.dart';
import 'graph.dart';
import 'report.dart';
import 'results.dart';
import 'select.dart';

const _usage = '''
reach: run the tests a change can reach.

Usage:
  reach [affected] [options]   which tests the branch's changes reach
  reach missed --results F     did a full run fail anywhere the selection skipped?
  reach hotspots               the files and tests with the widest reach

Selection follows import, export and part directives from each changed .dart
file to every test that depends on it. Changes it cannot follow (pubspec.lock,
fixtures, unknown files) run everything. See reach.yaml in the README.
''';

ArgParser _parser() {
  ArgParser common() => ArgParser()
    ..addOption('root',
        help: 'Project root (where pubspec.yaml is).', defaultsTo: '.')
    ..addOption('base',
        help: 'Branch to diff against. Default: origin/\$GITHUB_BASE_REF in a '
            'pull request, else origin/main.')
    ..addMultiOption('only',
        help: 'Only consider these test files (a job that runs a fixed set).')
    ..addOption('full', help: 'Run everything, for this reason (a release PR).')
    ..addFlag('help', abbr: 'h', negatable: false);
  ArgParser withOutput(ArgParser a) => a
    ..addFlag('json', negatable: false, help: 'Print JSON instead of text.')
    ..addFlag('github-output',
        negatable: false,
        help: 'Write mode, count, total and tests to \$GITHUB_OUTPUT.')
    ..addFlag('summary',
        negatable: false,
        help: 'Append a Markdown report to \$GITHUB_STEP_SUMMARY.')
    ..addOption('title', help: 'Heading for the summary.')
    ..addFlag('report-only',
        negatable: false,
        help: 'Say in the summary that everything ran anyway (a trial period).')
    ..addFlag('hotspots',
        negatable: false, help: 'Add the widest-reach report.');

  return ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('affected', withOutput(common()))
    ..addCommand(
        'missed',
        common()
          ..addOption('results',
              mandatory: true,
              help:
                  'JSON reporter output of the full run (--file-reporter json:F).')
          ..addFlag('fail',
              negatable: false, help: 'Exit 1 when a skipped test failed.'))
    ..addCommand('hotspots', withOutput(common()));
}

/// Runs the CLI and returns its exit code.
Future<int> run(List<String> argv) async {
  final parser = _parser();
  // `reach --base x` with no command means `reach affected --base x`.
  final args = argv.isEmpty ||
          argv.first.startsWith('-') &&
              argv.first != '-h' &&
              argv.first != '--help'
      ? ['affected', ...argv]
      : argv;
  final ArgResults top;
  try {
    top = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n\n$_usage');
    return 64;
  }
  final cmd = top.command;
  if (top['help'] as bool || cmd == null || cmd['help'] as bool) {
    stdout.writeln(_usage);
    if (cmd != null) stdout.writeln(parser.commands[cmd.name]!.usage);
    return 0;
  }

  final root = p.normalize(p.absolute(cmd['root'] as String));
  final ReachConfig config;
  try {
    config = ReachConfig.load(root);
  } on FormatException catch (e) {
    stderr.writeln('reach: ${e.message}');
    return 2;
  }
  final graph = ImportGraph.build(root, config);

  if (cmd.name == 'hotspots') {
    final h = Hotspots.of(graph);
    stdout.write(cmd['json'] as bool
        ? jsonReport(_emptySelection(graph), hotspots: h)
        : textReport(_emptySelection(graph),
                hotspots: h, top: 25, listTests: false)
            .split('\n')
            .skip(1)
            .join('\n'));
    return 0;
  }

  final base = (cmd['base'] as String?) ??
      switch (Platform.environment['GITHUB_BASE_REF']) {
        final b? when b.isNotEmpty => 'origin/$b',
        _ => 'origin/main',
      };
  final changes = await changesSince(base, root: root);
  final only = (cmd['only'] as List<String>).map(_posix).toList();
  final selection = select(
    changed: changes.files,
    config: config,
    graph: graph,
    only: only.isEmpty ? null : only,
    forceFull: cmd['full'] as String?,
    changesProblem: changes.problem,
  );

  if (cmd.name == 'missed') {
    final file = File(cmd['results'] as String);
    if (!file.existsSync()) {
      stderr.writeln('reach: no results at ${file.path}');
      return 2;
    }
    final failed = failedTestFiles(file.readAsStringSync(),
        root: root, knownTests: graph.tests);
    final skipped = selection.mode == Mode.full
        ? <String>{}
        : failed.difference(selection.tests.toSet());
    if (skipped.isEmpty) {
      stdout.writeln('reach: no failure outside the selection '
          '(${failed.length} failed file${failed.length == 1 ? '' : 's'}, '
          '${headline(selection).replaceFirst('reach: ', '')})');
      return 0;
    }
    for (final f in skipped) {
      // A GitHub annotation, so it shows on the run page.
      stdout.writeln(
          '::error file=$f::reach would have skipped $f, which failed');
    }
    _appendEnv(
        'GITHUB_STEP_SUMMARY',
        [
          '### reach missed a failure',
          '',
          'These failed, and the selection would not have run them:',
          '',
          for (final f in skipped) '- `$f`',
          '',
        ].join('\n'));
    return cmd['fail'] as bool ? 1 : 0;
  }

  final hotspots = cmd['hotspots'] as bool ? Hotspots.of(graph) : null;
  stdout.write(cmd['json'] as bool
      ? '${jsonReport(selection, hotspots: hotspots)}\n'
      : textReport(selection, hotspots: hotspots));
  if (cmd['github-output'] as bool) {
    _appendEnv(
        'GITHUB_OUTPUT',
        [
          'mode=${selection.mode.name}',
          'count=${selection.tests.length}',
          'total=${selection.total}',
          'tests=${selection.tests.join(' ')}',
          '',
        ].join('\n'));
  }
  if (cmd['summary'] as bool) {
    _appendEnv(
        'GITHUB_STEP_SUMMARY',
        markdownReport(selection,
            hotspots: hotspots,
            title: cmd['title'] as String?,
            reportOnly: cmd['report-only'] as bool));
  }
  return 0;
}

Selection _emptySelection(ImportGraph g) => Selection(
    mode: Mode.none,
    tests: const [],
    total: g.tests.length,
    changed: const {},
    fullReasons: const []);

String _posix(String path) => p.posix.joinAll(p.split(p.normalize(path)));

void _appendEnv(String name, String text) {
  final path = Platform.environment[name];
  if (path == null || path.isEmpty) {
    stderr.writeln('reach: \$$name is not set; skipping');
    return;
  }
  File(path).writeAsStringSync(text, mode: FileMode.append);
}
