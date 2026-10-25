import 'package:reach/reach.dart';
import 'package:test/test.dart';

import 'src/project.dart';

void main() {
  test('committed, staged, unstaged and untracked changes all count', () async {
    final t = await TempProject.create({
      'lib/a.dart': '',
      'lib/b.dart': '',
      'lib/c.dart': '',
      'lib/old.dart': '',
    });
    await t.git(['checkout', '-q', '-b', 'feature']);
    t.write({'lib/a.dart': '// committed'});
    t.delete('lib/old.dart');
    await t.commit('feature work');
    t.write({'lib/b.dart': '// staged'});
    await t.git(['add', 'lib/b.dart']);
    t.write({'lib/c.dart': '// unstaged', 'lib/new.dart': '// untracked'});

    final c = await changesSince('main', root: t.root);
    expect(c.problem, isNull);
    expect(c.files, [
      'lib/a.dart',
      'lib/b.dart',
      'lib/c.dart',
      'lib/new.dart',
      'lib/old.dart'
    ]);
  });

  test('changes on the base branch since branching do not count', () async {
    final t = await TempProject.create({'lib/a.dart': '', 'lib/b.dart': ''});
    await t.git(['checkout', '-q', '-b', 'feature']);
    t.write({'lib/a.dart': '// mine'});
    await t.commit('mine');
    await t.git(['checkout', '-q', 'main']);
    t.write({'lib/b.dart': '// someone else'});
    await t.commit('theirs');
    await t.git(['checkout', '-q', 'feature']);

    expect((await changesSince('main', root: t.root)).files, ['lib/a.dart']);
  });

  test('a rename counts as both paths', () async {
    final t = await TempProject.create({'lib/a.dart': 'class A {}'});
    await t.git(['checkout', '-q', '-b', 'feature']);
    await t.git(['mv', 'lib/a.dart', 'lib/renamed.dart']);
    await t.commit('rename');
    expect((await changesSince('main', root: t.root)).files,
        ['lib/a.dart', 'lib/renamed.dart']);
  });

  test('an unknown base is a problem, not an empty change list', () async {
    final t = await TempProject.create({});
    final c = await changesSince('origin/nope', root: t.root);
    expect(c.problem, contains('no merge base with origin/nope'));
  });

  test('a package inside a monorepo sees only its own paths', () async {
    final t = await TempProject.create({
      'packages/app/pubspec.yaml': 'name: app\n',
      'packages/app/lib/a.dart': '',
      'packages/other/lib/b.dart': '',
    });
    await t.git(['checkout', '-q', '-b', 'feature']);
    t.write({
      'packages/app/lib/a.dart': '// changed',
      'packages/other/lib/b.dart': '// changed',
    });
    final c = await changesSince('main', root: '${t.root}/packages/app');
    expect(c.files, ['lib/a.dart']);
  });
}
