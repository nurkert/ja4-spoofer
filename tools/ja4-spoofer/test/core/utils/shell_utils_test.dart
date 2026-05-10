import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/utils/shell_utils.dart';

void main() {
  group('shellQuote', () {
    test("empty string → \"''\"", () {
      expect(shellQuote(''), "''");
    });

    test('simple word → unquoted', () {
      expect(shellQuote('simple'), 'simple');
    });

    test('has space → single-quoted', () {
      expect(shellQuote('has space'), "'has space'");
    });

    test("it's → POSIX escape", () {
      expect(shellQuote("it's"), "'it'\"'\"'s'");
    });

    test('/path/to/file → unquoted (safe chars)', () {
      expect(shellQuote('/path/to/file'), '/path/to/file');
    });

    test('path with colon and dash → unquoted', () {
      expect(shellQuote('key:val-123'), 'key:val-123');
    });

    test('contains = → unquoted', () {
      expect(shellQuote('a=b'), 'a=b');
    });

    test('@-char → unquoted', () {
      expect(shellQuote('user@host'), 'user@host');
    });
  });

  group('shellSplit', () {
    test("empty string → []", () {
      expect(shellSplit(''), isEmpty);
    });

    test("'a b c' → ['a', 'b', 'c']", () {
      expect(shellSplit('a b c'), ['a', 'b', 'c']);
    });

    test("single-quoted preserves space", () {
      expect(shellSplit("'a b'"), ['a b']);
    });

    test("double-quoted preserves space", () {
      expect(shellSplit('"a b"'), ['a b']);
    });

    test(r"backslash escape 'a\ b' → ['a b']", () {
      expect(shellSplit(r'a\ b'), ['a b']);
    });

    test("multiple spaces → single token per word", () {
      expect(shellSplit('a   b   c'), ['a', 'b', 'c']);
    });

    test("mixed quotes and plain tokens", () {
      expect(shellSplit("hello 'world foo' end"), [
        'hello',
        'world foo',
        'end',
      ]);
    });

    test("double-quoted multi-word", () {
      expect(shellSplit('"hello world"'), ['hello world']);
    });
  });
}
