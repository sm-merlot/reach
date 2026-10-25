import 'config.dart';
import 'graph.dart';

/// What to run.
enum Mode {
  /// Only [Selection.tests].
  selected,

  /// Everything, for the reasons in [Selection.fullReasons].
  full,

  /// Nothing: no change can reach a test.
  none,
}

/// How one changed file was classified.
enum FileKind {
  /// Matches `full_run`.
  fullRun,

  /// Matches `ignore`.
  ignored,

  /// A `.dart` file in the graph.
  graph,

  /// A `.dart` file under a root that no longer exists: deleted or renamed
  /// away. Nothing at HEAD imports it, or HEAD would not compile.
  removed,

  /// None of the above, so it runs everything.
  unknown,
}

class Selection {
  Selection({
    required this.mode,
    required this.tests,
    required this.total,
    required this.changed,
    required this.fullReasons,
  });

  final Mode mode;

  /// The tests to run in [Mode.selected]; every test in [Mode.full]; empty in
  /// [Mode.none]. Sorted.
  final List<String> tests;

  /// How many tests the project has (within any `--only` restriction).
  final int total;

  /// Every changed file and how it was classified.
  final Map<String, FileKind> changed;

  /// Why the mode is [Mode.full]: one line per cause.
  final List<String> fullReasons;
}

FileKind classify(String path, ReachConfig config, ImportGraph graph) {
  if (config.fullRun.any((g) => g.matches(path))) return FileKind.fullRun;
  if (config.ignore.any((g) => g.matches(path))) return FileKind.ignored;
  if (path.endsWith('.dart') && config.isUnderRoot(path)) {
    return graph.contains(path) ? FileKind.graph : FileKind.removed;
  }
  return FileKind.unknown;
}

/// Picks the tests [changed] can reach.
///
/// [only] limits the tests considered, for a job that runs a fixed set (one
/// eval file): the answer is then whether any of those is reached. [forceFull]
/// is a reason to run everything regardless, such as a release PR.
Selection select({
  required List<String> changed,
  required ReachConfig config,
  required ImportGraph graph,
  List<String>? only,
  String? forceFull,
  String? changesProblem,
}) {
  final universe =
      only == null ? graph.tests : graph.tests.where(only.contains).toList();
  final kinds = {for (final f in changed) f: classify(f, config, graph)};

  final reasons = <String>[
    if (forceFull != null) forceFull,
    if (changesProblem != null) changesProblem,
    for (final MapEntry(key: f, value: k) in kinds.entries)
      if (k == FileKind.fullRun)
        '$f is listed under full_run'
      else if (k == FileKind.unknown)
        '$f is not Dart code in the graph and not ignored',
  ];
  if (reasons.isNotEmpty) {
    return Selection(
      mode: Mode.full,
      tests: universe,
      total: universe.length,
      changed: kinds,
      fullReasons: reasons,
    );
  }

  final reached = graph.reachedBy([
    for (final e in kinds.entries)
      if (e.value == FileKind.graph) e.key
  ]);
  final tests = universe.where(reached.contains).toList();
  return Selection(
    mode: tests.isEmpty ? Mode.none : Mode.selected,
    tests: tests,
    total: universe.length,
    changed: kinds,
    fullReasons: const [],
  );
}
