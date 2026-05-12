import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../core/models/app_descriptor.dart';
import '../../core/models/fingerprint_profile.dart';
import '../../core/services/app_descriptor_service.dart';
import '../../core/services/patch_service.dart';
import '../../core/services/script_launcher_service.dart';
import '../../core/utils/profile_args.dart';

enum AppBuildState { checking, notBuilt, patching, building, built, running }

class AppState {
  AppState({
    required this.descriptor,
    this.buildState = AppBuildState.checking,
  });

  final AppDescriptor descriptor;
  AppBuildState buildState;

  /// Whether the corresponding SSL library submodule has been patched.
  bool patched = false;

  String output = '';
  String launchArguments = '';
  RunningScript? runningScript;
  StreamSubscription<String>? stdoutSub;
  StreamSubscription<String>? stderrSub;

  /// Guards against concurrent smartLaunch calls (e.g. double-clicks).
  bool smartLaunchInProgress = false;

  bool get isRunning => runningScript != null;
  bool get isCli => descriptor.launch.runtime.isCli;

  /// The submodule name derived from the app's profile format.
  String? get submoduleName => switch (descriptor.launch.profileFormat) {
    'nss' => 'nss',
    'boringssl' => 'boringssl',
    'openssl' => 'openssl',
    _ => null,
  };
}

class AppLauncherController extends ChangeNotifier {
  static const int _kMaxOutputBytes = 400000;

  AppLauncherController({
    AppDescriptorService? descriptorService,
    ScriptLauncherService? launcherService,
    PatchService? patchService,
    this.repoRoot,
  }) : _descriptorService = descriptorService ?? AppDescriptorService(),
       _launcherService = launcherService ?? const ScriptLauncherService(),
       _patchService = patchService ?? const PatchService();

  final AppDescriptorService _descriptorService;
  final ScriptLauncherService _launcherService;
  final PatchService _patchService;

  /// Runtime root with scripts/, patches/, configs/, and writable libs/.
  final String? repoRoot;

  bool get hasRepoRoot => repoRoot != null;

  bool loading = true;
  List<AppState> apps = [];

  /// Per-submodule mutex queue. Two apps that share a submoduleName
  /// (e.g. Chromium and any future Brave-style build, both BoringSSL)
  /// must not run patch + build concurrently — they would interleave
  /// writes to `libs/<sub>` and corrupt each other's source tree.
  ///
  /// Each entry holds the future of the currently active or queued
  /// holder; new callers chain after it.
  final Map<String, Future<void>> _submoduleLocks = {};

  void updateLaunchArguments(AppState app, String value) {
    if (app.launchArguments == value) return;
    app.launchArguments = value;
    notifyListeners();
  }

  Future<void> loadApps() async {
    loading = true;
    notifyListeners();

    try {
      final descriptors = await _descriptorService.loadAll();
      apps = descriptors.map((d) => AppState(descriptor: d)).toList();
      notifyListeners();

      for (final app in apps) {
        await _checkBuildStatus(app);
        await _checkPatchStatus(app);
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _checkBuildStatus(AppState app) async {
    app.buildState = AppBuildState.checking;
    notifyListeners();

    for (final path in app.descriptor.build.builtBinaryPaths) {
      final expanded = _expandHome(path);
      if (File(expanded).existsSync() || Directory(expanded).existsSync()) {
        app.buildState = AppBuildState.built;
        notifyListeners();
        return;
      }
    }

    app.buildState = AppBuildState.notBuilt;
    notifyListeners();
  }

  /// Checks whether the SSL library submodule has the `my-changes` branch
  /// (created by apply_patches.sh).
  Future<void> _checkPatchStatus(AppState app) async {
    final root = repoRoot;
    final sub = app.submoduleName;
    if (root == null || sub == null) {
      app.patched = false;
      return;
    }
    final subPath = '$root/libs/$sub';
    try {
      final result = await Process.run('git', [
        'rev-parse',
        '--verify',
        'my-changes',
      ], workingDirectory: subPath);
      app.patched = result.exitCode == 0;
    } catch (_) {
      app.patched = false;
    }
    notifyListeners();
  }

  /// Applies patches for the SSL library submodule of this app.
  Future<bool> _applyPatches(AppState app) async {
    final root = repoRoot;
    final sub = app.submoduleName;
    if (root == null || sub == null) {
      _appendAppOutput(
        app,
        '[error] cannot patch: runtime root or submodule unknown\n',
      );
      return false;
    }

    _appendAppOutput(app, '[info] applying patches for $sub...\n');
    final code = await _runScript(
      app,
      startScript: () =>
          _patchService.applyPatches(repoRoot: root, submodule: sub),
    );
    if (code == 0) {
      app.patched = true;
      _appendAppOutput(app, '[ok] patches applied\n');
      notifyListeners();
      return true;
    }
    _appendAppOutput(app, '[error] patch failed (code=$code)\n');
    return false;
  }

  Future<void> buildApp(AppState app) async {
    if (app.buildState == AppBuildState.building) return;

    if (!hasRepoRoot) {
      app.output =
          '[error] Runtime root not configured.\n'
          '[hint]  Use the packaged app or set a source checkout in Settings.\n';
      app.buildState = AppBuildState.notBuilt;
      notifyListeners();
      return;
    }

    final scriptPath = app.descriptor.build.script;
    if (!File(scriptPath).existsSync()) {
      _appendAppOutput(app, '[error] build script not found: $scriptPath\n');
      app.buildState = AppBuildState.notBuilt;
      notifyListeners();
      return;
    }

    app.buildState = AppBuildState.building;
    notifyListeners();

    final code = await _runScript(
      app,
      startScript: () =>
          _launcherService.start(scriptPath: scriptPath, args: []),
    );
    _appendAppOutput(app, '[info] build exited (code=$code)\n');
    await _checkBuildStatus(app);

    // After a successful build, write the patch-stamp so smartLaunch can
    // detect when the on-disk binary becomes stale relative to patches/.
    if (app.buildState == AppBuildState.built) {
      await _writePatchStamp(app);
    }
  }

  Future<void> launchApp(
    AppState app,
    List<String> extraArgs, {
    bool clearOutput = true,
  }) async {
    if (app.isRunning) return;
    if (app.buildState != AppBuildState.built) return;

    final scriptPath = app.descriptor.launch.script;
    if (!File(scriptPath).existsSync()) {
      _appendAppOutput(app, '[error] launch script not found: $scriptPath\n');
      return;
    }

    app.buildState = AppBuildState.running;
    if (clearOutput) app.output = '';
    notifyListeners();

    final finalArgs = <String>[...extraArgs];
    if (!app.isCli) {
      // Browser launchers benefit from isolated profile dirs and process cleanup.
      final tempProfileDir = Directory.systemTemp.createTempSync(
        'ja4-profile-',
      );
      if (!_hasFlag(finalArgs, '--profile-dir')) {
        finalArgs.addAll(['--profile-dir', tempProfileDir.path]);
      }
      if (!_hasFlag(finalArgs, '--kill-existing') &&
          !_hasFlag(finalArgs, '--allow-existing')) {
        finalArgs.add('--kill-existing');
      }
    }

    final code = await _runScript(
      app,
      startScript: () =>
          _launcherService.start(scriptPath: scriptPath, args: finalArgs),
    );
    _appendAppOutput(app, '[info] process exited (code=$code)\n');
    app.buildState = AppBuildState.built;
    notifyListeners();
  }

  /// Single smart action: patches if needed, builds if needed, then launches.
  ///
  /// Stale-binary detection: a binary that exists on disk but was built
  /// against older patches is treated as "not built" — smartLaunch falls
  /// through to re-patch + rebuild. The freshness signal is the patch-stamp
  /// written by [buildApp] on success.
  Future<void> smartLaunch(AppState app, {FingerprintProfile? profile}) async {
    if (app.smartLaunchInProgress) return;
    app.smartLaunchInProgress = true;

    final sub = app.submoduleName;
    Completer<void>? release;
    try {
      final userArgs = _parseUserArgs(app.launchArguments);
      final args = [
        if (profile != null) ..._profileArgsForApp(app, profile),
        if (userArgs.isNotEmpty &&
            app.descriptor.launch.runtime.passUserArgsAfterDoubleDash)
          '--',
        ...userArgs,
      ];

      // Already built AND patch-stamp matches current patches → just launch.
      // The launch step does not touch the shared submodule tree, so we can
      // skip the per-submodule mutex in this fast path.
      if (app.buildState == AppBuildState.built &&
          await _patchStampMatches(app)) {
        await launchApp(app, args);
        return;
      }

      // Acquire per-submodule lock before any patch/build work. This
      // serializes apps that share `libs/<sub>` — concurrent patch runs
      // would otherwise interleave writes and corrupt the source tree.
      if (sub != null) {
        final previous = _submoduleLocks[sub];
        release = Completer<void>();
        _submoduleLocks[sub] = release.future;
        if (previous != null) {
          try {
            await previous;
          } catch (_) {
            // Previous holder may have thrown; we still get our turn.
          }
        }
      }

      // 1. Patch if needed (always run when stamp mismatched, even if patched flag is true).
      app.buildState = AppBuildState.patching;
      app.output = '';
      notifyListeners();
      final ok = await _applyPatches(app);
      if (!ok) {
        app.buildState = AppBuildState.notBuilt;
        notifyListeners();
        return;
      }
      // Reset so buildApp's guard doesn't skip the build.
      app.buildState = AppBuildState.notBuilt;
      notifyListeners();

      // 2. Build
      await buildApp(app);
      if (app.buildState != AppBuildState.built) return;

      // 3. Launch (keep prior output from patch + build steps)
      await launchApp(app, args, clearOutput: false);
    } finally {
      if (release != null && sub != null) {
        if (_submoduleLocks[sub] == release.future) {
          _submoduleLocks.remove(sub);
        }
        release.complete();
      }
      app.smartLaunchInProgress = false;
      notifyListeners();
    }
  }

  /// Runs a script by attaching its lifecycle to [app]: pipes stdout/stderr
  /// into the app's output buffer, awaits exit, and clears subscriptions.
  /// Returns the process exit code (or -1 on exception).
  Future<int> _runScript(
    AppState app, {
    required Future<RunningScript> Function() startScript,
  }) async {
    try {
      final running = await startScript();
      app.runningScript = running;
      app.stdoutSub = running.stdout.listen((t) => _appendAppOutput(app, t));
      app.stderrSub = running.stderr.listen((t) => _appendAppOutput(app, t));
      notifyListeners();

      final code = await running.process.exitCode;
      await app.stdoutSub?.cancel();
      await app.stderrSub?.cancel();
      app.runningScript = null;
      app.stdoutSub = null;
      app.stderrSub = null;
      notifyListeners();
      return code;
    } catch (e) {
      _appendAppOutput(app, '[error] $e\n');
      await app.stdoutSub?.cancel();
      await app.stderrSub?.cancel();
      app.runningScript = null;
      app.stdoutSub = null;
      app.stderrSub = null;
      notifyListeners();
      return -1;
    }
  }

  /// Computes the SHA256 of all inputs that influence the built binary:
  /// every `patches/<sub>/*.patch` file (sorted by filename), and the
  /// build script itself. Returns null if patches dir missing.
  ///
  /// Including the build script means a toolchain or SDK fix in the
  /// shell scripts auto-invalidates stale binaries on `git pull` —
  /// users don't have to manually clean to pick up build improvements.
  String? _currentPatchHash(AppState app) {
    final root = repoRoot;
    final sub = app.submoduleName;
    if (root == null || sub == null) return null;
    final patchesDir = Directory('$root/patches/$sub');
    if (!patchesDir.existsSync()) return null;

    final patchFiles =
        patchesDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.patch'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (patchFiles.isEmpty) return null;

    final inputs = <int>[...patchFiles.expand((f) => f.readAsBytesSync())];
    final buildScript = File(app.descriptor.build.script);
    if (buildScript.existsSync()) {
      inputs.addAll(buildScript.readAsBytesSync());
    }
    return sha256.convert(inputs).toString();
  }

  String _patchStampPath(AppState app) {
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/.ja4-spoofer/stamps/${app.descriptor.appId}.stamp';
  }

  Future<void> _writePatchStamp(AppState app) async {
    final hash = _currentPatchHash(app);
    if (hash == null) return;
    try {
      final file = File(_patchStampPath(app));
      await file.parent.create(recursive: true);
      await file.writeAsString(hash);
    } catch (e) {
      _appendAppOutput(app, '[warn] could not write patch stamp: $e\n');
    }
  }

  /// True iff a patch-stamp exists for [app] AND it matches the current
  /// hash of patches/<sub>/*.patch. False on first run, after patches
  /// change, or if patches dir is missing.
  Future<bool> _patchStampMatches(AppState app) async {
    final current = _currentPatchHash(app);
    if (current == null) return true; // No patches → vacuously fresh.
    final file = File(_patchStampPath(app));
    if (!file.existsSync()) return false;
    try {
      final stored = (await file.readAsString()).trim();
      return stored == current;
    } catch (_) {
      return false;
    }
  }

  List<String> _profileArgsForApp(AppState app, FingerprintProfile profile) {
    final args = List<String>.from(profileToArgs(profile));
    final isOpenSsl = app.descriptor.launch.profileFormat == 'openssl';
    final isCaptured = profile.metadata.source == 'captured';
    final shouldForceExactExtensions =
        isOpenSsl &&
        isCaptured &&
        profile.inputs.extensions.isNotEmpty &&
        (profile.inputs.extensionMode == null ||
            profile.inputs.extensionMode!.isEmpty) &&
        !args.contains('--extension-mode');
    if (shouldForceExactExtensions) {
      args.addAll(const ['--extension-mode', 'exact']);
    }
    // Don't auto-force strict=1 here. Captured profiles often contain ciphers
    // or extensions the patched lib's cipher table doesn't know (RC4, 3DES,
    // SCSV markers, vendor-private IDs). Strict turns those into hard
    // handshake aborts; for launch we prefer best-effort replay so the user
    // actually gets a connection. Strict is still available via explicit
    // --strict 1 from the configurator or extra args.
    return args;
  }

  List<String> _parseUserArgs(String raw) {
    final tokens = <String>[];
    final current = StringBuffer();
    bool inSingle = false;
    bool inDouble = false;
    bool escaping = false;

    void flush() {
      if (current.isEmpty) return;
      tokens.add(current.toString());
      current.clear();
    }

    for (final rune in raw.runes) {
      final char = String.fromCharCode(rune);
      if (escaping) {
        current.write(char);
        escaping = false;
        continue;
      }
      if (char == r'\') {
        escaping = true;
        continue;
      }
      if (char == "'" && !inDouble) {
        inSingle = !inSingle;
        continue;
      }
      if (char == '"' && !inSingle) {
        inDouble = !inDouble;
        continue;
      }
      if (!inSingle && !inDouble && RegExp(r'\s').hasMatch(char)) {
        flush();
        continue;
      }
      current.write(char);
    }

    if (escaping) {
      current.write(r'\');
    }
    flush();
    return tokens;
  }

  bool _hasFlag(List<String> args, String flag) => args.contains(flag);

  static String _expandHome(String path) {
    if (!path.startsWith('~/') && path != '~') return path;
    final home = Platform.environment['HOME'] ?? '';
    return path == '~' ? home : '$home${path.substring(1)}';
  }

  void stopApp(AppState app) {
    final running = app.runningScript;
    if (running == null) return;
    _appendAppOutput(app, '[info] stopping...\n');
    _launcherService.stop(running.process);
  }

  void clearAppOutput(AppState app) {
    app.output = '';
    notifyListeners();
  }

  void _appendAppOutput(AppState app, String text) {
    final next = app.output + text;
    app.output = next.length > (_kMaxOutputBytes * 5 ~/ 4)
        ? next.substring(next.length - _kMaxOutputBytes)
        : next;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final app in apps) {
      app.stdoutSub?.cancel();
      app.stderrSub?.cancel();
      if (app.runningScript != null) {
        _launcherService.stop(app.runningScript!.process, force: true);
      }
    }
    super.dispose();
  }
}
