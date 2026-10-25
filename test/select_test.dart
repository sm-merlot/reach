import 'package:reach/reach.dart';
import 'package:test/test.dart';

final _files = {
  'lib/a.dart': '',
  'lib/b.dart': '',
  'test/a_test.dart': "import 'package:app/a.dart';",
  'test/b_test.dart': "import 'package:app/b.dart';",
  'test/eval/eval_test.dart': "import 'package:app/b.dart';",
};

Selection _select(List<String> changed,
    {String? yaml, List<String>? only, String? forceFull, String? problem}) {
  final config = ReachConfig.fromYaml(yaml);
  return select(
    changed: changed,
    config: config,
    graph: ImportGraph.fromSources(_files, config, packageName: 'app'),
    only: only,
    forceFull: forceFull,
    changesProblem: problem,
  );
}

void main() {
  test('selects the tests a code change reaches', () {
    final s = _select(['lib/a.dart']);
    expect(s.mode, Mode.selected);
    expect(s.tests, ['test/a_test.dart']);
    expect(s.total, 3);
  });

  test('a changed test selects itself', () {
    expect(_select(['test/b_test.dart']).tests, ['test/b_test.dart']);
  });

  test('nothing to run when only ignored files change', () {
    final s = _select(['README.md', 'docs/notes.md']);
    expect(s.mode, Mode.none);
    expect(s.tests, isEmpty);
    expect(s.changed.values, everyElement(FileKind.ignored));
  });

  test('pubspec.lock runs everything, whatever reach.yaml says', () {
    final s = _select(['pubspec.lock'], yaml: 'full_run: [tool/**]');
    expect(s.mode, Mode.full);
    expect(s.tests, hasLength(3));
    expect(s.fullReasons.single, contains('pubspec.lock'));
  });

  test('an unlisted non-Dart file runs everything', () {
    for (final f in [
      'test/fixtures/chart.pdf',
      'assets/icon.png',
      'lib/l10n/en.arb',
      'Makefile'
    ]) {
      final s = _select([f]);
      expect(s.mode, Mode.full, reason: f);
      expect(s.changed[f], FileKind.unknown, reason: f);
    }
  });

  test('ignore and full_run in reach.yaml', () {
    const yaml =
        'ignore: [android/**, site/**]\nfull_run: [.github/workflows/test.yml]';
    expect(
        _select(['android/app/build.gradle', 'site/index.html'], yaml: yaml)
            .mode,
        Mode.none);
    expect(_select(['.github/workflows/test.yml'], yaml: yaml).mode, Mode.full);
  });

  test('full_run wins over ignore', () {
    final s = _select(['x.md'], yaml: 'full_run: ["*.md"]');
    expect(s.mode, Mode.full);
  });

  test('a deleted Dart file under a root runs nothing for itself', () {
    final s = _select(['lib/gone.dart', 'test/gone_test.dart']);
    expect(s.mode, Mode.none);
    expect(s.changed.values, everyElement(FileKind.removed));
  });

  test('a Dart file outside the roots runs everything', () {
    expect(_select(['tool/script.dart']).mode, Mode.full);
  });

  test('only narrows the tests considered', () {
    const eval = ['test/eval/eval_test.dart'];
    expect(_select(['lib/a.dart'], only: eval).mode, Mode.none);
    final s = _select(['lib/b.dart'], only: eval);
    expect(s.mode, Mode.selected);
    expect(s.tests, eval);
    expect(s.total, 1);
  });

  test('a forced full run and a changes problem both give reasons', () {
    final s = _select(['lib/a.dart'],
        forceFull: 'release PR', problem: 'no merge base');
    expect(s.mode, Mode.full);
    expect(s.fullReasons, ['release PR', 'no merge base']);
  });

  test('reach.yaml rejects unknown keys and bad types', () {
    expect(() => ReachConfig.fromYaml('full-run: [x]'), throwsFormatException);
    expect(() => ReachConfig.fromYaml('roots: lib'), throwsFormatException);
    expect(() => ReachConfig.fromYaml('tests: [a]'), throwsFormatException);
  });
}
