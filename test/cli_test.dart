import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/project.dart';

void main() {
  // The CLI reads $GITHUB_OUTPUT and $GITHUB_STEP_SUMMARY from the real
  // environment, which a test cannot set in-process, so these run the
  // executable instead.
  Future<ProcessResult> reach(String root, List<String> args) => Process.run(
        Platform.resolvedExecutable,
        ['run', p.join(Directory.current.path, 'bin', 'reach.dart'), ...args],
        workingDirectory: root,
        environment: {
          'GITHUB_OUTPUT': p.join(root, '.gh_output'),
          'GITHUB_STEP_SUMMARY': p.join(root, '.gh_summary'),
          'GITHUB_BASE_REF': '',
        },
      );

  Future<TempProject> project() async {
    final t = await TempProject.create({
      '.gitignore': '.gh_*\n',
      'lib/a.dart': '',
      'lib/b.dart': '',
      'test/a_test.dart': "import 'package:app/a.dart';",
      'test/b_test.dart': "import 'package:app/b.dart';",
    });
    await t.git(['checkout', '-q', '-b', 'feature']);
    return t;
  }

  String read(TempProject t, String name) =>
      File(p.join(t.root, name)).existsSync()
          ? File(p.join(t.root, name)).readAsStringSync()
          : '';

  test('affected writes GitHub outputs and a summary', () async {
    final t = await project();
    t.write({'lib/a.dart': '// changed'});
    final r = await reach(t.root,
        ['--base', 'main', '--github-output', '--summary', '--hotspots']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout, contains('reach: 1/2 tests (50.0%)'));
    expect(
        read(t, '.gh_output'),
        allOf(contains('mode=selected\n'), contains('count=1\n'),
            contains('tests=test/a_test.dart\n')));
    expect(read(t, '.gh_summary'),
        allOf(contains('1/2 tests'), contains('Widest reach')));
  });

  test('json output', () async {
    final t = await project();
    t.write({'pubspec.lock': '# changed'});
    final r = await reach(t.root, ['affected', '--base', 'main', '--json']);
    final j = jsonDecode(r.stdout as String) as Map<String, Object?>;
    expect(j['mode'], 'full');
    expect(j['tests'], ['test/a_test.dart', 'test/b_test.dart']);
  });

  test('missed flags a failure the selection skipped', () async {
    final t = await project();
    t.write({'lib/a.dart': '// changed'});
    final results = p.join(t.root, '.gh_results.json');
    File(results).writeAsStringSync([
      {
        'type': 'suite',
        'suite': {'id': 1, 'path': p.join(t.root, 'test/b_test.dart')}
      },
      {
        'type': 'testStart',
        'test': {'id': 2, 'suiteID': 1}
      },
      {'type': 'testDone', 'testID': 2, 'result': 'failure'},
    ].map(jsonEncode).join('\n'));

    final r =
        await reach(t.root, ['missed', '--base', 'main', '--results', results]);
    expect(r.exitCode, 0, reason: 'report only without --fail');
    expect(r.stdout, contains('::error file=test/b_test.dart::'));
    expect(read(t, '.gh_summary'), contains('reach missed a failure'));

    final strict = await reach(
        t.root, ['missed', '--base', 'main', '--results', results, '--fail']);
    expect(strict.exitCode, 1);
  });

  test('missed is quiet when the failure was selected', () async {
    final t = await project();
    t.write({'lib/b.dart': '// changed'});
    final results = p.join(t.root, '.gh_results.json');
    File(results).writeAsStringSync([
      {
        'type': 'suite',
        'suite': {'id': 1, 'path': 'test/b_test.dart'}
      },
      {
        'type': 'testStart',
        'test': {'id': 2, 'suiteID': 1}
      },
      {'type': 'testDone', 'testID': 2, 'result': 'failure'},
    ].map(jsonEncode).join('\n'));
    final r = await reach(
        t.root, ['missed', '--base', 'main', '--results', results, '--fail']);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('no failure outside the selection'));
  });

  test('a bad reach.yaml exits 2 with the reason', () async {
    final t = await project();
    t.write({'reach.yaml': 'nope: 1\n'});
    final r = await reach(t.root, ['--base', 'main']);
    expect(r.exitCode, 2);
    expect(r.stderr, contains('unknown key "nope"'));
  });

  test('--full forces a full run with the reason', () async {
    final t = await project();
    final r = await reach(t.root, ['--base', 'main', '--full', 'release PR']);
    expect(
        r.stdout, allOf(contains('full run'), contains('because release PR')));
  });
}
