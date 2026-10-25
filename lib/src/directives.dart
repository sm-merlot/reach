/// The URIs a Dart file's `import`, `export` and `part` directives name.
///
/// A conditional import names every URI it can resolve to
/// (`import 'a.dart' if (dart.library.io) 'b.dart';` gives both), since which
/// one is used depends on the platform the test runs on.
///
/// `part of` names the library a part belongs to, not a file this one depends
/// on, so it is skipped: the library's own `part` directive already links the
/// two in the right direction.
///
/// This is a scanner, not a parser. It skips comments and string contents so a
/// directive inside either is not mistaken for one, and it only takes a
/// directive keyword followed directly by a string literal, so an identifier
/// that happens to be called `import` is not one either.
List<String> directiveUris(String source) {
  // A script's `#!` line would otherwise end in a word, and the first import
  // after it would not look like the start of a statement.
  if (source.startsWith('#!')) {
    final end = source.indexOf('\n');
    source = end < 0 ? '' : source.substring(end + 1);
  }
  final tokens = _tokenize(source);
  final uris = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t.kind != _Kind.word) continue;
    if (t.text != 'import' && t.text != 'export' && t.text != 'part') {
      continue;
    }
    if (i > 0 && !_startsStatement(tokens[i - 1])) continue;
    if (i + 1 >= tokens.length || tokens[i + 1].kind != _Kind.string) continue;
    // Every string up to the `;` belongs to this directive: the main URI and
    // any conditional ones.
    for (var j = i + 1; j < tokens.length; j++) {
      final u = tokens[j];
      if (u.kind == _Kind.punct && u.text == ';') break;
      if (u.kind == _Kind.string && u.text.isNotEmpty) uris.add(u.text);
    }
  }
  return uris;
}

/// Directives start a statement: the file's start, or after a `;`, a `}`, or
/// an annotation's closing `)` (an annotated import, `@deprecated import`).
bool _startsStatement(_Token previous) {
  if (previous.kind == _Kind.punct) {
    return previous.text == ';' || previous.text == '}' || previous.text == ')';
  }
  // `@Deprecated` with no arguments ends in a word.
  return previous.kind == _Kind.word && previous.afterAt;
}

enum _Kind { word, string, punct }

class _Token {
  _Token(this.kind, this.text, {this.afterAt = false});
  final _Kind kind;
  final String text;

  /// A word written straight after `@`: an annotation's name.
  final bool afterAt;
}

List<_Token> _tokenize(String s) {
  final out = <_Token>[];
  var i = 0;
  var sawAt = false;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    // Whitespace.
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      i++;
      continue;
    }
    // Comments: `//` to end of line, `/* */` nested as Dart allows.
    if (c == 0x2F && i + 1 < s.length) {
      final n = s.codeUnitAt(i + 1);
      if (n == 0x2F) {
        final end = s.indexOf('\n', i);
        i = end < 0 ? s.length : end + 1;
        continue;
      }
      if (n == 0x2A) {
        var depth = 1;
        i += 2;
        while (i < s.length && depth > 0) {
          if (s.startsWith('/*', i)) {
            depth++;
            i += 2;
          } else if (s.startsWith('*/', i)) {
            depth--;
            i += 2;
          } else {
            i++;
          }
        }
        continue;
      }
    }
    // Strings, with an optional `r` prefix and single or triple quotes.
    final raw = (c == 0x72 || c == 0x52) &&
        i + 1 < s.length &&
        (s.codeUnitAt(i + 1) == 0x27 || s.codeUnitAt(i + 1) == 0x22);
    if (raw || c == 0x27 || c == 0x22) {
      final start = raw ? i + 1 : i;
      final q = s[start];
      final triple = s.startsWith('$q$q$q', start);
      final close = triple ? '$q$q$q' : q;
      var j = start + close.length;
      final buf = StringBuffer();
      var interpolated = false;
      while (j < s.length) {
        if (!raw && s.codeUnitAt(j) == 0x5C) {
          // Escape: keep the escaped character, skip the backslash.
          if (j + 1 < s.length) buf.write(s[j + 1]);
          j += 2;
          continue;
        }
        if (s.startsWith(close, j)) break;
        if (!triple && s.codeUnitAt(j) == 0x0A) break; // unterminated
        if (!raw && s.codeUnitAt(j) == 0x24) interpolated = true;
        buf.write(s[j]);
        j++;
      }
      i = j + close.length;
      // An interpolated string is never a directive URI; record it empty so
      // it still ends a run of directive strings correctly.
      out.add(_Token(_Kind.string, interpolated ? '' : buf.toString()));
      sawAt = false;
      continue;
    }
    // Words: identifiers and keywords.
    if (_isWordStart(c)) {
      var j = i + 1;
      while (j < s.length && _isWordPart(s.codeUnitAt(j))) {
        j++;
      }
      out.add(_Token(_Kind.word, s.substring(i, j), afterAt: sawAt));
      sawAt = false;
      i = j;
      continue;
    }
    // Everything else is one character of punctuation.
    sawAt = c == 0x40;
    out.add(_Token(_Kind.punct, s[i]));
    i++;
  }
  return out;
}

bool _isWordStart(int c) =>
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x61 && c <= 0x7A) || // a-z
    c == 0x5F || // _
    c == 0x24; // $

bool _isWordPart(int c) => _isWordStart(c) || (c >= 0x30 && c <= 0x39);
