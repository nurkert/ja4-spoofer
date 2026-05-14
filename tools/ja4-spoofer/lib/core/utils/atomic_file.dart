import 'dart:convert';
import 'dart:io';

/// Writes [json] to [target] via a temp-and-rename dance, so a crash or
/// disk-full event mid-write can never leave a partially-written JSON in
/// place of a previously-valid one.
///
/// On success [target] is replaced atomically (on POSIX, `rename(2)`).
/// On failure the temp file is removed and the exception is rethrown.
Future<void> writeJsonAtomic(File target, Map<String, dynamic> json) async {
  final parent = target.parent;
  if (!parent.existsSync()) {
    parent.createSync(recursive: true);
  }
  final encoded = const JsonEncoder.withIndent('  ').convert(json);
  final tmp = File('${target.path}.tmp');
  try {
    await tmp.writeAsString(encoded, flush: true);
    await tmp.rename(target.path);
  } catch (_) {
    if (tmp.existsSync()) {
      try {
        await tmp.delete();
      } catch (_) {
        // Best-effort cleanup; the original target is untouched either way.
      }
    }
    rethrow;
  }
}

/// Profile IDs are used as filenames under `profiles/`. Permit only the
/// characters that the in-app ID generators emit (`manual-…`, `captured-…`,
/// `nss-dump-…`, `random-…`); anything else likely came from a hand-crafted
/// import and could escape the directory via `..` or `/`.
String sanitizeProfileId(String raw) {
  if (raw.isEmpty || !_safeProfileIdPattern.hasMatch(raw)) {
    throw FormatException('invalid profile id: "$raw"');
  }
  return raw;
}

final _safeProfileIdPattern = RegExp(r'^[A-Za-z0-9_-]+$');
