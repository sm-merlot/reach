import 'package:reach/reach.dart';
import 'package:test/test.dart';

void main() {
  test('import, export and part', () {
    expect(directiveUris('''
import 'package:app/a.dart';
import "b.dart" as b show B;
export 'c.dart' hide C;
part 'd.dart';
'''), ['package:app/a.dart', 'b.dart', 'c.dart', 'd.dart']);
  });

  test('part of names the library, not a dependency', () {
    expect(directiveUris("part of 'lib.dart';\n"), isEmpty);
    expect(directiveUris('part of app.lib;\n'), isEmpty);
  });

  test('a conditional import names every URI it can resolve to', () {
    expect(
        directiveUris("import 'stub.dart'\n"
            "    if (dart.library.io) 'io.dart'\n"
            "    if (dart.library.js_interop) 'web.dart';\n"),
        ['stub.dart', 'io.dart', 'web.dart']);
  });

  test('directives in comments and strings are not directives', () {
    expect(directiveUris('''
// import 'line_comment.dart';
/* import 'block.dart'; /* nested */ import 'still_block.dart'; */
/// import 'doc.dart';
const s = "import 'in_string.dart';";
const t = \'\'\'
import 'in_triple.dart';
\'\'\';
import 'real.dart';
'''), ['real.dart']);
  });

  test('an identifier called import is not a directive', () {
    expect(
        directiveUris("final import = 1;\nvoid f() { part('x'); }\n"), isEmpty);
  });

  test('annotated directives', () {
    expect(
        directiveUris("@Deprecated('old') import 'a.dart';\n"
            "@deprecated export 'b.dart';\n"),
        ['a.dart', 'b.dart']);
  });

  test('a library directive and a script line before the imports', () {
    expect(
        directiveUris("#!/usr/bin/env dart\nlibrary app;\nimport 'a.dart';\n"),
        ['a.dart']);
  });

  test('raw and escaped strings', () {
    expect(directiveUris("import r'a.dart';\nimport 'b\\'s.dart';\n"),
        ['a.dart', "b's.dart"]);
  });

  test('a declaration after the directives does not end the scan early', () {
    expect(directiveUris("import 'a.dart';\nclass A {}\nimport 'late.dart';\n"),
        ['a.dart', 'late.dart']);
  });
}
