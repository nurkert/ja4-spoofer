/// Quote a token for a shell-like preview string.
String shellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  final safe = RegExp(r'^[A-Za-z0-9_./:@=-]+$');
  if (safe.hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

/// Minimal shell split that supports:
/// - spaces as separators
/// - single quotes
/// - double quotes
/// - escaping with backslash outside single quotes
List<String> shellSplit(String input) {
  final out = <String>[];
  final current = StringBuffer();
  var inSingle = false;
  var inDouble = false;
  var escaped = false;

  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    if (escaped) {
      current.write(ch);
      escaped = false;
      continue;
    }
    if (ch == r'\' && !inSingle) {
      escaped = true;
      continue;
    }
    if (ch == "'" && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (ch == '"' && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (ch.trim().isEmpty && !inSingle && !inDouble) {
      if (current.isNotEmpty) {
        out.add(current.toString());
        current.clear();
      }
      continue;
    }
    current.write(ch);
  }
  if (current.isNotEmpty) {
    out.add(current.toString());
  }
  return out;
}
