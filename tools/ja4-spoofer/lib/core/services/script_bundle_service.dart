import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';

/// Extracts bundled runtime files from Flutter assets to disk so they can be
/// executed via [Process.start] and used by the patch/build shell scripts.
///
/// Returns a writable "virtual repo root" containing `scripts/`, `configs/`,
/// and `patches/`. Packaged builds use it in place of a manually configured
/// repository checkout.
class ScriptBundleService {
  static const _assetPrefix = 'assets/bundled-runtime';
  static const _runtimeBaseDir = '.ja4-spoofer/runtime';

  /// Extracts bundled runtime files to `~/.ja4-spoofer/runtime/<version>/`
  /// and returns that directory.
  Future<String> ensureExtracted() async {
    final home = Platform.environment['HOME']!;

    // Read app version from pubspec (baked into the binary).
    const appVersion = String.fromEnvironment(
      'BUNDLE_VERSION',
      defaultValue: 'dev',
    );
    final root = '$home/$_runtimeBaseDir/$appVersion';
    final versionFile = File('$root/.bundle-version');

    // Skip extraction if version matches.
    if (appVersion != 'dev' &&
        versionFile.existsSync() &&
        versionFile.readAsStringSync().trim() == appVersion &&
        Directory('$root/scripts').existsSync() &&
        Directory('$root/configs').existsSync() &&
        Directory('$root/patches').existsSync()) {
      return root;
    }

    // Discover all bundled-script assets.
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assetKeys = manifest
        .listAssets()
        .where((k) => k.startsWith('$_assetPrefix/'))
        .toList();

    for (final key in assetKeys) {
      // Strip prefix to get the repo-relative path, e.g. "scripts/lib/env.sh".
      final relative = key.substring('$_assetPrefix/'.length);
      final outFile = File('$root/$relative');

      // Ensure parent directories exist.
      await outFile.parent.create(recursive: true);

      // Load asset bytes and write to disk.
      final data = await rootBundle.load(key);
      await outFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );

      if ((Platform.isLinux || Platform.isMacOS) &&
          (relative.endsWith('.sh') || relative.endsWith('.py'))) {
        // Flutter asset I/O writes 0644. Without re-asserting the
        // execute bit here, bash refuses to run apply_patches.sh on
        // first launch after a fresh install. Skip on Windows where
        // POSIX perms don't apply.
        final result = await Process.run('chmod', ['+x', outFile.path]);
        if (result.exitCode != 0) {
          developer.log(
            'chmod +x failed for ${outFile.path}: ${result.stderr}',
            name: 'ScriptBundleService',
          );
        }
      }
    }

    // Write version marker.
    await versionFile.create(recursive: true);
    await versionFile.writeAsString(appVersion);

    return root;
  }
}
