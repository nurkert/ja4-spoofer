import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/app_descriptor.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/utils/ja4_dump_verifier.dart';
import 'package:ja4_spoofer/features/app_launcher/app_launcher_controller.dart';
import 'package:ja4_spoofer/core/services/script_launcher_service.dart';

class _RecordingLauncherService extends ScriptLauncherService {
  List<String>? lastArgs;
  String? lastScriptPath;

  @override
  Future<RunningScript> start({
    required String scriptPath,
    required List<String> args,
    Map<String, String>? environment,
  }) async {
    lastScriptPath = scriptPath;
    lastArgs = List<String>.from(args);
    final process = await Process.start('/bin/sh', ['-c', 'exit 0']);
    return RunningScript(
      process: process,
      stdout: process.stdout.transform(utf8.decoder),
      stderr: process.stderr.transform(utf8.decoder),
    );
  }
}

void main() {
  test('smartLaunch appends CLI launch arguments after profile args', () async {
    final tempDir = Directory.systemTemp.createTempSync('ja4_app_launcher_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final launchScript = File('${tempDir.path}/launch.sh')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');

    final launcherService = _RecordingLauncherService();
    final controller = AppLauncherController(launcherService: launcherService);

    final descriptor = AppDescriptor(
      appId: 'curl-openssl-ja4',
      metadata: const AppDescriptorMetadata(name: 'curl (OpenSSL)'),
      build: const AppBuildConfig(script: 'build.sh', builtBinaryPaths: []),
      launch: AppLaunchConfig(
        script: launchScript.path,
        profileFormat: 'openssl',
        runtime: const AppLaunchRuntimeConfig(
          kind: AppRuntimeKind.cli,
          passUserArgsAfterDoubleDash: true,
        ),
      ),
    );
    final app = AppState(
      descriptor: descriptor,
      buildState: AppBuildState.built,
    )..launchArguments = r'-I "https://example.com/raw?x=1"';
    controller.apps = [app];

    // cipher_mode must be explicit: without it the launcher's pre-flight
    // check blocks the launch, because "reorder" would leave the library's
    // own cipher defaults on the wire.
    const profile = FingerprintProfile(
      profileId: 'test-profile',
      metadata: FingerprintProfileMetadata(name: 'test'),
      inputs: TlsClientHelloInputs(
        tlsMinVersion: '1.2',
        tlsMaxVersion: '1.3',
        cipherSuites: [4865, 4866],
        cipherMode: 'exact',
      ),
    );

    await controller.smartLaunch(app, profile: profile);

    expect(launcherService.lastScriptPath, launchScript.path);
    expect(
      launcherService.lastArgs,
      containsAllInOrder([
        '--tls-min',
        '1.2',
        '--tls-max',
        '1.3',
        '--cipher-suites',
        '4865,4866',
        '--',
        '-I',
        'https://example.com/raw?x=1',
      ]),
    );
    expect(launcherService.lastArgs, isNot(contains('--profile-dir')));
    expect(launcherService.lastArgs, isNot(contains('--kill-existing')));
  });

  test('smartLaunch appends browser safety args for GUI apps', () async {
    final tempDir = Directory.systemTemp.createTempSync('ja4_app_launcher_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final launchScript = File('${tempDir.path}/launch.sh')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');

    final launcherService = _RecordingLauncherService();
    final controller = AppLauncherController(launcherService: launcherService);

    final descriptor = AppDescriptor(
      appId: 'firefox-nss-ja4',
      metadata: const AppDescriptorMetadata(name: 'Firefox'),
      build: const AppBuildConfig(script: 'build.sh', builtBinaryPaths: []),
      launch: AppLaunchConfig(
        script: launchScript.path,
        profileFormat: 'nss',
        runtime: const AppLaunchRuntimeConfig(kind: AppRuntimeKind.gui),
      ),
    );
    final app = AppState(
      descriptor: descriptor,
      buildState: AppBuildState.built,
    );
    controller.apps = [app];

    await controller.smartLaunch(app);

    expect(launcherService.lastScriptPath, launchScript.path);
    expect(launcherService.lastArgs, contains('--profile-dir'));
    expect(launcherService.lastArgs, contains('--kill-existing'));
  });

  test('smartLaunch drains stdout emitted after process exit', () async {
    // Regression: long Chromium/Firefox builds were losing the tail of
    // their stdout because the controller awaited `process.exitCode`
    // before its listeners had drained buffered output. Inject a
    // launcher whose stdout stream deliberately emits data AFTER the
    // child has exited; the controller must wait for stream onDone.
    final tempDir = Directory.systemTemp.createTempSync('ja4_drain_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final launchScript = File('${tempDir.path}/launch.sh')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');

    final stdoutCtl = StreamController<String>();
    final stderrCtl = StreamController<String>.broadcast();

    final launcherService = _DelayedStreamLauncherService(
      stdoutCtl: stdoutCtl,
      stderrCtl: stderrCtl,
    );
    final controller = AppLauncherController(launcherService: launcherService);

    final descriptor = AppDescriptor(
      appId: 'curl-openssl-ja4',
      metadata: const AppDescriptorMetadata(name: 'curl (OpenSSL)'),
      build: const AppBuildConfig(script: 'build.sh', builtBinaryPaths: []),
      launch: AppLaunchConfig(
        script: launchScript.path,
        profileFormat: 'openssl',
        runtime: const AppLaunchRuntimeConfig(kind: AppRuntimeKind.cli),
      ),
    );
    final app = AppState(
      descriptor: descriptor,
      buildState: AppBuildState.built,
    );
    controller.apps = [app];

    // Schedule a late stdout emission: arrives after process.exitCode
    // already resolved. Without the drain fix, the controller would
    // return before receiving this last line.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 50)).then((_) async {
        stdoutCtl.add('late stdout chunk\n');
        await stdoutCtl.close();
        await stderrCtl.close();
      }),
    );

    await controller.smartLaunch(app);

    expect(app.output, contains('late stdout chunk'));
  });

  group('fingerprint enforcement gate', () {
    late Directory tempDir;
    late File launchScript;
    late _RecordingLauncherService launcherService;
    late AppLauncherController controller;

    AppState buildApp({String? dumpPath}) {
      final descriptor = AppDescriptor(
        appId: 'curl-openssl-ja4',
        metadata: const AppDescriptorMetadata(name: 'curl (OpenSSL)'),
        build: const AppBuildConfig(script: 'build.sh', builtBinaryPaths: []),
        launch: AppLaunchConfig(
          script: launchScript.path,
          profileFormat: 'openssl',
          dumpPath: dumpPath,
          runtime: const AppLaunchRuntimeConfig(kind: AppRuntimeKind.cli),
        ),
      );
      final app = AppState(
        descriptor: descriptor,
        buildState: AppBuildState.built,
      );
      controller.apps = [app];
      return app;
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ja4_enforce_');
      launchScript = File('${tempDir.path}/launch.sh')
        ..writeAsStringSync('#!/bin/sh\nexit 0\n');
      launcherService = _RecordingLauncherService();
      controller = AppLauncherController(launcherService: launcherService);
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('a profile that cannot reach the wire intact is held back', () async {
      final app = buildApp();
      const profile = FingerprintProfile(
        profileId: 'p',
        metadata: FingerprintProfileMetadata(name: 'p'),
        // No cipher_mode → reorder → library defaults stay on the wire.
        inputs: TlsClientHelloInputs(cipherSuites: [4865, 4866]),
      );

      await controller.smartLaunch(app, profile: profile);

      expect(launcherService.lastScriptPath, isNull);
      expect(app.enforcementAwaitingDecision, isTrue);
      expect(app.enforcement!.hasBlockers, isTrue);
      expect(
        app.enforcement!.blockers.map((i) => i.field),
        contains('cipher_mode'),
      );
    });

    test('force launches anyway and keeps the verdict visible', () async {
      final app = buildApp();
      const profile = FingerprintProfile(
        profileId: 'p',
        metadata: FingerprintProfileMetadata(name: 'p'),
        inputs: TlsClientHelloInputs(cipherSuites: [4865, 4866]),
      );

      await controller.smartLaunch(app, profile: profile, force: true);

      expect(launcherService.lastScriptPath, launchScript.path);
      expect(app.enforcementAwaitingDecision, isFalse);
      expect(app.enforcement!.hasBlockers, isTrue);
    });

    test('a clean profile launches without a prompt', () async {
      final app = buildApp();
      const profile = FingerprintProfile(
        profileId: 'p',
        metadata: FingerprintProfileMetadata(name: 'p'),
        inputs: TlsClientHelloInputs(
          cipherSuites: [4865, 4866],
          cipherMode: 'exact',
        ),
      );

      await controller.smartLaunch(app, profile: profile);

      expect(launcherService.lastScriptPath, launchScript.path);
      expect(app.enforcementAwaitingDecision, isFalse);
      expect(app.enforcement!.hasBlockers, isFalse);
    });

    test('a launch that writes no dump is reported as unverified, not as '
        'success', () async {
      final dumpPath = '${tempDir.path}/effective.conf';
      final app = buildApp(dumpPath: dumpPath);
      const profile = FingerprintProfile(
        profileId: 'p',
        metadata: FingerprintProfileMetadata(name: 'p'),
        inputs: TlsClientHelloInputs(cipherSuites: [4865], cipherMode: 'exact'),
      );

      await controller.smartLaunch(app, profile: profile);

      expect(app.dumpVerdict, isNotNull);
      expect(app.dumpVerdict!.status, DumpVerdictStatus.noDump);
      expect(app.dumpVerdict!.matches, isFalse);
      expect(app.output, contains('Nicht verifizierbar'));
    });

    test('a stale dump from a previous run cannot fake a success', () async {
      final dumpPath = '${tempDir.path}/effective.conf';
      // Left over from an earlier, successful run.
      File(dumpPath).writeAsStringSync(
        'active=1\napply_ok=1\nmismatch_mask=0\n'
        'requested_cipher_suites=4865\nfinal_cipher_suites=4865\n',
      );

      final app = buildApp(dumpPath: dumpPath);
      const profile = FingerprintProfile(
        profileId: 'p',
        metadata: FingerprintProfileMetadata(name: 'p'),
        inputs: TlsClientHelloInputs(cipherSuites: [4865], cipherMode: 'exact'),
      );

      await controller.smartLaunch(app, profile: profile);

      expect(File(dumpPath).existsSync(), isFalse);
      expect(app.dumpVerdict!.status, DumpVerdictStatus.noDump);
    });

    test('no profile means no gate and no verification', () async {
      final app = buildApp(dumpPath: '${tempDir.path}/effective.conf');

      await controller.smartLaunch(app);

      expect(launcherService.lastScriptPath, launchScript.path);
      expect(app.enforcement, isNull);
      expect(app.dumpVerdict, isNull);
    });
  });
}

class _DelayedStreamLauncherService extends ScriptLauncherService {
  _DelayedStreamLauncherService({
    required this.stdoutCtl,
    required this.stderrCtl,
  });

  final StreamController<String> stdoutCtl;
  final StreamController<String> stderrCtl;

  @override
  Future<RunningScript> start({
    required String scriptPath,
    required List<String> args,
    Map<String, String>? environment,
  }) async {
    // Real Process that exits immediately so `process.exitCode` resolves
    // promptly. The interesting stream timing happens on the stdout
    // controller we own.
    final process = await Process.start('/bin/sh', ['-c', 'exit 0']);
    return RunningScript(
      process: process,
      stdout: stdoutCtl.stream,
      stderr: stderrCtl.stream,
    );
  }
}
