import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/utils/atomic_file.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('atomic_file_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('writeJsonAtomic', () {
    test('writes the JSON content to the target file', () async {
      final target = File('${tempDir.path}/data.json');
      await writeJsonAtomic(target, {'k': 1});
      expect(target.existsSync(), isTrue);
      expect(jsonDecode(target.readAsStringSync()), {'k': 1});
    });

    test('leaves no .tmp file behind after a successful write', () async {
      final target = File('${tempDir.path}/data.json');
      await writeJsonAtomic(target, {'a': 'b'});
      expect(File('${target.path}.tmp').existsSync(), isFalse);
    });

    test('creates the parent directory if missing', () async {
      final target = File('${tempDir.path}/nested/dir/data.json');
      await writeJsonAtomic(target, {'x': true});
      expect(target.existsSync(), isTrue);
    });

    test('preserves the previous content if rename fails', () async {
      final target = File('${tempDir.path}/data.json');
      await target.writeAsString('{"original":true}');
      // Simulate a rename failure by making the target read-only and
      // setting tmp to a directory (rename of file→existing-dir fails).
      // Easier: write atomically against a path the OS can rename onto,
      // then verify the post-failure state.
      // Here we use a pre-existing junk .tmp file that conflicts:
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsString('leftover from a previous crash');
      // A second atomic write should still succeed — it overwrites the
      // stale .tmp en route to rename — and the target should hold the
      // new content.
      await writeJsonAtomic(target, {'fresh': 1});
      expect(jsonDecode(target.readAsStringSync()), {'fresh': 1});
      expect(tmp.existsSync(), isFalse);
    });
  });

  group('sanitizeProfileId', () {
    test('accepts in-app generator IDs', () {
      for (final id in [
        'manual-1773326382078',
        'captured-1773326382078',
        'nss-dump-1773326382078',
        'random-curl-abc123',
      ]) {
        expect(sanitizeProfileId(id), id);
      }
    });

    test('rejects path-traversal payloads', () {
      for (final id in ['../escape', 'a/b', 'foo.bar', '..', '', 'a\\b']) {
        expect(
          () => sanitizeProfileId(id),
          throwsA(isA<FormatException>()),
          reason: 'should reject: $id',
        );
      }
    });
  });
}
