import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'script_launcher_service.dart';

/// Runs `apply_patches.sh` for SSL library submodules.
class PatchService {
  const PatchService();

  static const managedSubmodules = <String>['nss', 'boringssl', 'openssl'];

  /// Discovers managed SSL library submodules that are present in `libs/`.
  static List<String> discoverManagedSubmodules(String repoRoot) {
    final result = <String>[];
    for (final name in managedSubmodules) {
      final dir = Directory('$repoRoot/libs/$name');
      if (dir.existsSync()) result.add(name);
    }
    result.sort();
    return result;
  }

  /// Whether a submodule currently has at least one exported patch file.
  static bool hasPatchFiles(String repoRoot, String submodule) {
    final patchesDir = Directory('$repoRoot/patches/$submodule');
    if (!patchesDir.existsSync()) return false;
    return patchesDir.listSync().any(
      (f) => f is File && f.path.endsWith('.patch'),
    );
  }

  /// Discovers the repo root by walking upwards from cwd until scripts/lib.sh is found.
  static String? discoverRepoRoot() {
    var dir = Directory.current;
    for (var i = 0; i < 12; i++) {
      final candidate = File('${dir.path}/scripts/lib.sh');
      if (candidate.existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  Future<RunningScript> applyPatches({
    required String repoRoot,
    required String submodule,
  }) async {
    final process = await Process.start(
      '$repoRoot/scripts/apply_patches.sh',
      ['--only', submodule],
      workingDirectory: repoRoot,
      runInShell: false,
    );
    return RunningScript(
      process: process,
      stdout: process.stdout.transform(utf8.decoder),
      stderr: process.stderr.transform(utf8.decoder),
    );
  }
}
