import 'dart:io';

/// Find `scripts/run_firefox_with_ja4.sh` from likely execution roots.
///
/// Search order:
/// 1) JA4_SCRIPT_PATH env var (if file exists)
/// 2) walk upwards from current directory, platform script path, executable path
String discoverScriptPath() {
  final env = Platform.environment['JA4_SCRIPT_PATH'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) {
    return env;
  }

  final seeds = <Directory>{
    Directory.current,
    File(Platform.script.toFilePath()).parent,
    File(Platform.resolvedExecutable).parent,
  };

  for (final seed in seeds) {
    var dir = seed;
    for (var depth = 0; depth < 12; depth++) {
      final candidate = File('${dir.path}/scripts/run_firefox_with_ja4.sh');
      if (candidate.existsSync()) {
        return candidate.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }
  }
  return '';
}
