# reach

Runs the tests a change can reach, instead of the whole suite.

```
$ reach --base origin/main
reach: 17/258 tests (6.6%)
changed:
  code      lib/screens/workspace_screen.dart
  code      lib/widgets/sidebar/file_sidebar.dart
tests:
  test/screens/workspace_panel_tab_test.dart
  ...
```

reach follows `import`, `export` and `part` directives from every changed
`.dart` file to every test that depends on it, directly or through other files.
Test helpers count: a test that reaches app code through
`test/support/harness.dart` is found, because `test/` is part of the graph,
not only the `*_test.dart` files in it.

Anything it cannot follow runs everything. That is the point of the design:
reach may run more than it needed to, but it should never skip a test that
could have failed.

## How a changed file is counted

Checked in this order:

| Changed file | Counted as | Effect |
| --- | --- | --- |
| Matches `full_run` (`pubspec.lock`, `dart_test.yaml`, ...) | full_run | run everything |
| Matches `ignore` (`**.md`, ...) | ignored | nothing |
| A `.dart` file under a root | code | the tests that reach it |
| A `.dart` file under a root that is gone | removed | nothing (nothing at HEAD imports it) |
| Anything else: fixtures, assets, `.arb`, scripts, unknown types | unknown | run everything |

The last row is deliberate. A test that reads a fixture or an asset has no
import to follow, so reach cannot tell which tests use it, and runs them all.
List what really cannot affect tests under `ignore` to stop that.

Other packages and the SDK are outside the graph. Changing them means changing
`pubspec.lock`, which runs everything.

Conditional imports count every branch (`import 'stub.dart' if
(dart.library.io) 'io.dart'` depends on both), since which one loads depends on
the platform a test runs on.

## Commands

```
reach [affected]   which tests the branch's changes reach
reach missed       did a full run fail anywhere the selection would have skipped?
reach hotspots     the files and tests with the widest reach
```

Common options:

- `--base <ref>`: what to diff against. Default `origin/$GITHUB_BASE_REF` in a
  pull request, else `origin/main`. Changes are everything since the merge
  base: commits, staged, unstaged and untracked files. Locally that answers
  "what would this push run".
- `--root <dir>`: the project (where `pubspec.yaml` is). Default `.`. Works for
  a package inside a monorepo.
- `--only <test>`: consider only these tests. For a job that runs a fixed set:
  `reach --only test/eval/eval_test.dart` says whether that job needs to run.
- `--full <reason>`: run everything, for this reason (a release PR).

Output: text by default, `--json`, `--github-output` (writes `mode`, `count`,
`total` and `tests` to `$GITHUB_OUTPUT`), `--summary` (Markdown to
`$GITHUB_STEP_SUMMARY`), `--hotspots` (adds the widest-reach tables).

`mode` is `selected`, `full` or `none`.

## Configuration

Optional `reach.yaml` next to `pubspec.yaml`:

```yaml
# Directories whose .dart files make up the graph. Default: [lib, test]
roots: [lib, test]

# Which files in the graph are tests. Default: test/**_test.dart
tests: test/**_test.dart

# Added to the defaults (pubspec.yaml, pubspec.lock, analysis_options.yaml,
# dart_test.yaml, build.yaml, reach.yaml).
full_run:
  - .github/workflows/test.yml

# Added to the defaults (**.md, LICENSE).
ignore:
  - .changeset/**
  - android/**
  - ios/**
  - site/**
```

Globs use [package:glob](https://pub.dev/packages/glob) syntax, matched
against paths relative to the project root.

## In CI

reach needs the history back to the merge base:

```yaml
jobs:
  reach:
    runs-on: ubuntu-latest
    outputs:
      mode: ${{ steps.reach.outputs.mode }}
      tests: ${{ steps.reach.outputs.tests }}
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0
      - uses: dart-lang/setup-dart@v1
      - run: dart pub global activate --source git https://github.com/sm-merlot/reach --git-ref <sha>
      - id: reach
        run: reach --github-output --summary --hotspots

  test:
    needs: reach
    if: needs.reach.outputs.mode != 'none'
    steps:
      # ...
      - run: flutter test ${{ needs.reach.outputs.mode == 'selected' && needs.reach.outputs.tests || '' }}
```

### Trying it without trusting it

Run the whole suite as before, have reach say what it would have picked, and
check that afterwards:

```yaml
      - run: flutter test --file-reporter json:build/test-results.json
      - if: always()
        run: reach missed --results build/test-results.json
```

`missed` reads the full run's results and flags, as an error annotation and in
the job summary, any failing test file the selection would have skipped. A week
of runs with no `missed` warnings is the evidence for switching selection on.
Pass `--fail` to make it fail the job instead.

## Limits

- Static only. A test that reaches a file by a path string at runtime (a
  fixture, `Isolate.spawnUri`) has no import to follow. A non-Dart file changed
  that way counts as unknown and runs everything, which is safe. A `.dart` file
  used that way is the trap: under a root, nothing imports it, so changing it
  runs nothing. Keep such files outside the roots, where they count as unknown.
- Generated code is followed like any other file when it is committed. If it is
  generated in CI, add the generator's inputs to `full_run`.
- File-level, not symbol-level: changing one function reaches every test that
  imports its file. Coarser than it could be, never finer.

## Development

```
dart pub get
dart test
dart run bin/reach.dart --root <some project> hotspots
```
