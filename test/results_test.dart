import 'dart:convert';

import 'package:reach/reach.dart';
import 'package:test/test.dart';

String _events(List<Map<String, Object?>> events) =>
    events.map(jsonEncode).join('\n');

void main() {
  test('failing, erroring and unloadable files; passing and skipped are not',
      () {
    final out = _events([
      {'type': 'start'},
      {
        'type': 'suite',
        'suite': {'id': 0, 'path': '/repo/test/pass_test.dart'}
      },
      {
        'type': 'suite',
        'suite': {'id': 1, 'path': '/repo/test/fail_test.dart'}
      },
      {
        'type': 'suite',
        'suite': {'id': 2, 'path': 'test/broken_test.dart'}
      },
      {
        'type': 'suite',
        'suite': {'id': 3, 'path': '/repo/test/throw_test.dart'}
      },
      {
        'type': 'testStart',
        'test': {'id': 10, 'suiteID': 0, 'name': 'ok'}
      },
      {'type': 'testDone', 'testID': 10, 'result': 'success', 'skipped': false},
      {
        'type': 'testStart',
        'test': {'id': 11, 'suiteID': 0, 'name': 'skip'}
      },
      {'type': 'testDone', 'testID': 11, 'result': 'success', 'skipped': true},
      {
        'type': 'testStart',
        'test': {'id': 12, 'suiteID': 1, 'name': 'bad'}
      },
      {'type': 'testDone', 'testID': 12, 'result': 'failure'},
      {
        'type': 'testStart',
        'test': {
          'id': 13,
          'suiteID': 2,
          'name': 'loading test/broken_test.dart'
        }
      },
      {'type': 'error', 'testID': 13, 'error': 'compile error'},
      {'type': 'testDone', 'testID': 13, 'result': 'error'},
      {
        'type': 'testStart',
        'test': {'id': 14, 'suiteID': 3, 'name': 'throws'}
      },
      {'type': 'testDone', 'testID': 14, 'result': 'error'},
      {'type': 'done', 'success': false},
    ]);
    expect(failedTestFiles('$out\nsome runner chatter\n', root: '/repo'), {
      'test/fail_test.dart',
      'test/broken_test.dart',
      'test/throw_test.dart'
    });
  });
}
