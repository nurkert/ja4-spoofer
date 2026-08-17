import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../core/models/app_descriptor.dart';
import '../../core/models/fingerprint_profile.dart';
import '../../core/models/ja4_stack.dart';
import '../../core/services/app_descriptor_service.dart';
import '../../core/services/dump_watcher_service.dart';
import '../../core/services/ja4_verification_probe.dart';
import '../../core/services/patch_service.dart';
import '../../core/services/script_launcher_service.dart';
import '../../core/utils/fingerprint_enforcement.dart';
import '../../core/utils/ja4_dump_verifier.dart';
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

  /// Pre-flight result for the profile that is about to be launched. Set
  /// whenever a launch is attempted; when it carries blockers the launch is
  /// held back until the user acknowledges or auto-fixes them.
  EnforcementReport? enforcement;

  /// True while a blocking pre-flight result is waiting for the user's
  /// decision. The UI shows the deviation dialog for this state.
  bool enforcementAwaitingDecision = false;

  /// Post-launch verdict: what the patched library reports it actually put on
  /// the wire. Null while no verified ClientHello has been observed yet.
  DumpVerdict? dumpVerdict;

  /// Independent measurement of the emitted ClientHello, read off a socket by
  /// the local probe rather than reported by the library. Outranks
  /// [dumpVerdict] whenever both are present.
  WireObservation? wireObservation;

  /// True while a probe run is in flight.
  bool measuring = false;

  /// Profile whose fingerprint the running process is supposed to carry.
  FingerprintProfile? launchedProfile;

  DumpWatcherService? dumpWatcher;
  StreamSubscription<String>? dumpSub;

  bool get isRunning => runningScript != null;
  bool get isCli => descriptor.launch.runtime.isCli;

  /// Patched TLS stack behind this target, or null when it is not one of the
  /// three supported libraries.
  Ja4Stack? get stack =>
      Ja4Stack.fromProfileFormat(descriptor.launch.profileFormat);

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

  /// IANA-registered extension codepoints, used to warn about extensions the
  /// stacks can only emit as empty synthetic stubs. Null until the registry
  /// has loaded; the check is skipped rather than guessed while unset.
  Set<int>? knownExtensionIds;

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

    // Write the patch-stamp only when the build actually succeeded. The
    // build-state probe merely tests whether a binary path exists, and a
    // half-finished Chromium leaves `Chromium.app` behind — stamping that
    // would certify an unpatched or stale binary as fresh and let every later
    // launch skip the rebuild.
    if (code != 0) {
      _appendAppOutput(
        app,
        '[warn] build failed — binary is not certified fresh, '
        'the next launch will rebuild\n',
      );
      await _clearPatchStamp(app);
      app.buildState = AppBuildState.notBuilt;
      notifyListeners();
      return;
    }
    if (app.buildState == AppBuildState.built) {
      await _writePatchStamp(app);
    }
  }

  Future<void> launchApp(
    AppState app,
    List<String> extraArgs, {
    bool clearOutput = true,
    FingerprintProfile? profile,
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
    _startDumpVerification(app, profile);
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
    await _finishDumpVerification(app);
    app.buildState = AppBuildState.built;
    notifyListeners();
  }

  /// Arms the fingerprint read-back for a launch.
  ///
  /// The stale dump from a previous run is removed first: without that, a
  /// process that never applies the config at all would be verified against
  /// the previous run's file and reported as a success.
  void _startDumpVerification(AppState app, FingerprintProfile? profile) {
    _stopDumpVerification(app);
    app.dumpVerdict = null;
    app.launchedProfile = profile;
    if (profile == null) return;

    final dumpPath = app.descriptor.launch.dumpPath;
    if (dumpPath == null) return;

    try {
      final file = File(dumpPath);
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      _appendAppOutput(app, '[warn] could not clear stale dump: $e\n');
    }

    final watcher = DumpWatcherService();
    app.dumpWatcher = watcher;
    app.dumpSub = watcher.onChange.listen((content) {
      final verdict = const Ja4DumpVerifier().verify(
        dumpContent: content,
        profile: profile,
      );
      app.dumpVerdict = verdict;
      _appendAppOutput(app, '[ja4] ${verdict.headline}\n');
      for (final deviation in verdict.deviations) {
        _appendAppOutput(
          app,
          '[ja4]   ${deviation.field}: angefordert=${deviation.requested} '
          'gesendet=${deviation.actual}\n',
        );
      }
      notifyListeners();
    });
    watcher.start(dumpPath);
  }

  /// Called when the launched process is gone. A launch that produced no dump
  /// at all never applied the fingerprint — that has to read as a failure, not
  /// as an absent result.
  Future<void> _finishDumpVerification(AppState app) async {
    final hadProfile = app.launchedProfile != null;
    final hasDumpPath = app.descriptor.launch.dumpPath != null;
    _stopDumpVerification(app);
    if (hadProfile && hasDumpPath && app.dumpVerdict == null) {
      app.dumpVerdict = const Ja4DumpVerifier().noDump();
      _appendAppOutput(app, '[ja4] ${app.dumpVerdict!.headline}\n');
    }
  }

  void _stopDumpVerification(AppState app) {
    unawaited(app.dumpSub?.cancel() ?? Future<void>.value());
    app.dumpSub = null;
    app.dumpWatcher?.dispose();
    app.dumpWatcher = null;
  }

  /// Re-runs the pre-flight check for [app] against [profile] without
  /// launching anything. Used by the UI to keep the deviation panel live while
  /// the user edits the profile.
  EnforcementReport refreshEnforcement(
    AppState app,
    FingerprintProfile profile,
  ) {
    final report = checkFingerprintEnforcement(
      profile: profile,
      stack: app.stack,
      knownExtensionIds: knownExtensionIds,
    );
    app.enforcement = report;
    notifyListeners();
    return report;
  }

  /// Clears a held-back launch after the user decided against it.
  void dismissEnforcement(AppState app) {
    app.enforcementAwaitingDecision = false;
    notifyListeners();
  }

  /// Measures the fingerprint [app] actually emits and compares it against
  /// [profile].
  ///
  /// This is the only check here that does not depend on the patched library
  /// telling the truth about itself: a loopback sniffer reads the ClientHello
  /// off the socket and hashes it with the same JA4 implementation the profile
  /// is hashed with. On OpenSSL it is the only way to see an ALPN or cipher
  /// drift at all, because that stack's dump echoes those values back from the
  /// request instead of re-reading the wire.
  ///
  /// The client is started against `https://127.0.0.1:<port>/` and will report
  /// a TLS error — the probe answers every ClientHello with a fatal alert. The
  /// handshake is not the point; the ClientHello is.
  Future<WireObservation?> verifyFingerprint(
    AppState app,
    FingerprintProfile profile, {
    Ja4VerificationProbe probe = const Ja4VerificationProbe(),
  }) async {
    if (app.measuring || app.isRunning) return null;
    if (app.buildState != AppBuildState.built) {
      _appendAppOutput(app, '[ja4] cannot measure: build the target first\n');
      return null;
    }

    final scriptPath = app.descriptor.launch.script;
    if (!File(scriptPath).existsSync()) {
      _appendAppOutput(app, '[error] launch script not found: $scriptPath\n');
      return null;
    }

    app.measuring = true;
    app.wireObservation = null;
    refreshEnforcement(app, profile);
    _appendAppOutput(app, '[ja4] measuring emitted ClientHello...\n');

    try {
      final observation = await probe.measure(
        profile: profile,
        launchClient: (probeUrl) async {
          final args = [
            ..._profileArgsForApp(app, profile),
            ..._probeClientArgs(app, probeUrl),
          ];
          await _runScript(
            app,
            startScript: () =>
                _launcherService.start(scriptPath: scriptPath, args: args),
          );
        },
      );
      app.wireObservation = observation;
      _appendAppOutput(app, '[ja4] ${observation.headline}\n');
      if (observation.observedJa4 != null) {
        _appendAppOutput(
          app,
          '[ja4]   ausgewählt: ${observation.intendedJa4}\n'
          '[ja4]   gemessen:   ${observation.observedJa4}\n',
        );
      }
      for (final deviation in observation.deviations) {
        _appendAppOutput(
          app,
          '[ja4]   ${deviation.field}: profil=${deviation.requested} '
          'draht=${deviation.actual}\n',
        );
      }
      return observation;
    } finally {
      app.measuring = false;
      notifyListeners();
    }
  }

  /// Arguments that point the client at the probe URL for one short request.
  ///
  /// Both runner scripts forward everything after `--` to the client itself,
  /// so a browser receives the URL as its start page and curl receives it as
  /// its request target.
  List<String> _probeClientArgs(AppState app, String probeUrl) {
    if (app.isCli) {
      return [
        '--',
        '-sS',
        '-o',
        Platform.isWindows ? 'NUL' : '/dev/null',
        '--max-time',
        '15',
        probeUrl,
      ];
    }
    final tempProfileDir = Directory.systemTemp.createTempSync('ja4-probe-');
    return [
      '--profile-dir',
      tempProfileDir.path,
      '--kill-existing',
      '--',
      probeUrl,
    ];
  }

  /// Single smart action: patches if needed, builds if needed, then launches.
  ///
  /// Stale-binary detection: a binary that exists on disk but was built
  /// against older patches is treated as "not built" — smartLaunch falls
  /// through to re-patch + rebuild. The freshness signal is the patch-stamp
  /// written by [buildApp] on success.
  /// Set [force] to launch despite a blocking pre-flight verdict.
  Future<void> smartLaunch(
    AppState app, {
    FingerprintProfile? profile,
    bool force = false,
  }) async {
    if (app.smartLaunchInProgress) return;

    // Pre-flight: refuse to launch a profile that provably cannot reach the
    // wire intact. Measuring against a fingerprint the stack silently rewrote
    // is worse than not measuring at all, so the user has to see what will
    // deviate and why before this proceeds.
    if (profile != null) {
      final report = refreshEnforcement(app, profile);
      if (report.hasBlockers && !force) {
        app.enforcementAwaitingDecision = true;
        notifyListeners();
        return;
      }
    }
    app.enforcementAwaitingDecision = false;
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
        await launchApp(app, args, profile: profile);
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
      await launchApp(app, args, clearOutput: false, profile: profile);
    } finally {
      if (release != null && sub != null) {
        if (_submoduleLocks[sub] == release.future) {
          // Map<K, Future<void>>.remove returns the removed Future; we
          // don't need to wait on it, just drop the entry.
          unawaited(_submoduleLocks.remove(sub) ?? Future<void>.value());
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
      // `process.exitCode` resolves when the OS reaps the child, but
      // buffered stdout/stderr can still be in flight to our listeners
      // at that moment. Track stream completion separately so the tail
      // of long builds (Chromium emits hundreds of lines after its final
      // status message) lands in the output buffer before we tear down
      // the subscriptions.
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      app.stdoutSub = running.stdout.listen(
        (t) => _appendAppOutput(app, t),
        onDone: () {
          if (!stdoutDone.isCompleted) stdoutDone.complete();
        },
      );
      app.stderrSub = running.stderr.listen(
        (t) => _appendAppOutput(app, t),
        onDone: () {
          if (!stderrDone.isCompleted) stderrDone.complete();
        },
      );
      notifyListeners();

      final code = await running.process.exitCode;
      await stdoutDone.future;
      await stderrDone.future;
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

  /// Drops a stale stamp so the next launch is forced through patch + build.
  Future<void> _clearPatchStamp(AppState app) async {
    try {
      final file = File(_patchStampPath(app));
      if (file.existsSync()) await file.delete();
    } catch (e) {
      _appendAppOutput(app, '[warn] could not clear patch stamp: $e\n');
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
    // Don't auto-force strict=1 here. Captured profiles often contain ciphers
    // or extensions the patched lib's cipher table doesn't know (RC4, 3DES,
    // SCSV markers, vendor-private IDs). Strict turns those into hard
    // handshake aborts; for launch we prefer best-effort replay so the user
    // actually gets a connection. Strict is still available via explicit
    // --strict 1 from the configurator or extra args. The post-launch
    // verification is what turns that tolerance into a visible result:
    // whatever the library silently substituted shows up in the dump verdict.
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
      unawaited(app.stdoutSub?.cancel() ?? Future<void>.value());
      unawaited(app.stderrSub?.cancel() ?? Future<void>.value());
      _stopDumpVerification(app);
      if (app.runningScript != null) {
        _launcherService.stop(app.runningScript!.process, force: true);
      }
    }
    super.dispose();
  }
}
