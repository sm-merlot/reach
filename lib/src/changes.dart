import 'dart:io';

/// The files a branch changes, relative to the project root.
class Changes {
  Changes(this.files, {this.problem});

  /// Every path added, modified, deleted or renamed (both sides of a rename).
  final List<String> files;

  /// Set when the changes could not be worked out. The caller runs everything.
  final String? problem;
}

/// Lists what changed in [root] since it branched from [base]: committed on
/// the branch, staged, unstaged and untracked. Locally that is "what would
/// this push run"; in CI the tree is clean, so it is the PR's diff.
///
/// [root] may be a subdirectory of the repository (a package in a monorepo);
/// paths come back relative to it, and changes outside it are dropped.
Future<Changes> changesSince(String base, {required String root}) async {
  Future<ProcessResult> git(List<String> args) =>
      Process.run('git', args, workingDirectory: root);

  final top = await git(['rev-parse', '--is-inside-work-tree']);
  if (top.exitCode != 0) {
    return Changes(const [], problem: 'not a git repository: $root');
  }

  final mb = await git(['merge-base', base, 'HEAD']);
  if (mb.exitCode != 0) {
    return Changes(const [],
        problem: 'no merge base with $base. In CI, fetch the history '
            '(actions/checkout with fetch-depth: 0) or the base branch. '
            '${(mb.stderr as String).trim()}');
  }
  final mergeBase = (mb.stdout as String).trim();

  // Against the working tree, not HEAD, so local edits count too.
  final diff = await git(
      ['diff', '--name-only', '--no-renames', '--relative', mergeBase]);
  final untracked = await git(['ls-files', '--others', '--exclude-standard']);
  for (final r in [diff, untracked]) {
    if (r.exitCode != 0) {
      return Changes(const [],
          problem: 'git failed: ${(r.stderr as String).trim()}');
    }
  }
  final files = <String>{
    ..._lines(diff.stdout as String),
    ..._lines(untracked.stdout as String),
  }.toList()
    ..sort();
  // Both are relative to [root] and limited to it: `--relative` for the
  // diff, and ls-files does that by default.
  return Changes(files);
}

Iterable<String> _lines(String s) =>
    s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
