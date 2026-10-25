import 'package:reach/reach.dart';
import 'package:test/test.dart';

final _config = ReachConfig.fromYaml(null);

ImportGraph _graph(Map<String, String> files) =>
    ImportGraph.fromSources(files, _config, packageName: 'app');

void main() {
  group('resolve', () {
    String? r(String uri, String from) =>
        ImportGraph.resolve(uri, from: from, packageName: 'app');

    test('own package goes to lib', () {
      expect(r('package:app/src/a.dart', 'test/x_test.dart'), 'lib/src/a.dart');
    });
    test('relative, including up a level', () {
      expect(r('../b.dart', 'lib/src/a.dart'), 'lib/b.dart');
      expect(r('helper.dart', 'test/widgets/x_test.dart'),
          'test/widgets/helper.dart');
    });
    test('outside the project', () {
      expect(r('dart:io', 'lib/a.dart'), isNull);
      expect(r('package:flutter/material.dart', 'lib/a.dart'), isNull);
      expect(r('../../outside.dart', 'lib/a.dart'), isNull);
      expect(r('https://example.com/a.dart', 'lib/a.dart'), isNull);
    });
  });

  test('a test reaches lib code through a helper in test/', () {
    final g = _graph({
      'lib/panel.dart': '',
      'test/support/harness.dart': "import 'package:app/panel.dart';",
      'test/panel_test.dart': "import 'support/harness.dart';",
      'test/other_test.dart': '',
    });
    expect(g.reachedBy(['lib/panel.dart']), {
      'lib/panel.dart',
      'test/support/harness.dart',
      'test/panel_test.dart'
    });
  });

  test('a part file reaches whoever imports its library', () {
    final g = _graph({
      'lib/lib.dart': "part 'src/part.dart';",
      'lib/src/part.dart': "part of '../lib.dart';",
      'test/lib_test.dart': "import 'package:app/lib.dart';",
    });
    expect(g.reachedBy(['lib/src/part.dart']), contains('test/lib_test.dart'));
  });

  test('every branch of a conditional import counts', () {
    final g = _graph({
      'lib/io.dart': '',
      'lib/web.dart': '',
      'lib/store.dart':
          "import 'stub.dart' if (dart.library.io) 'io.dart' if (dart.library.js_interop) 'web.dart';",
      'lib/stub.dart': '',
      'test/store_test.dart': "import 'package:app/store.dart';",
    });
    for (final f in ['lib/io.dart', 'lib/web.dart', 'lib/stub.dart']) {
      expect(g.reachedBy([f]), contains('test/store_test.dart'), reason: f);
    }
  });

  test('exports pass reach through', () {
    final g = _graph({
      'lib/a.dart': '',
      'lib/barrel.dart': "export 'a.dart';",
      'test/a_test.dart': "import 'package:app/barrel.dart';",
    });
    expect(g.reachedBy(['lib/a.dart']), contains('test/a_test.dart'));
  });

  test('import cycles terminate', () {
    final g = _graph({
      'lib/a.dart': "import 'b.dart';",
      'lib/b.dart': "import 'a.dart';",
      'test/a_test.dart': "import 'package:app/a.dart';",
    });
    expect(g.reachedBy(['lib/b.dart']), contains('test/a_test.dart'));
    expect(g.closureOf('test/a_test.dart'),
        {'test/a_test.dart', 'lib/a.dart', 'lib/b.dart'});
  });

  test('tests are the files matching the tests glob', () {
    final g = _graph(
        {'test/a_test.dart': '', 'test/helper.dart': '', 'lib/a.dart': ''});
    expect(g.tests, ['test/a_test.dart']);
  });
}
