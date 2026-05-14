import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/app_descriptor.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
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

    const profile = FingerprintProfile(
      profileId: 'test-profile',
      metadata: FingerprintProfileMetadata(name: 'test'),
      inputs: TlsClientHelloInputs(
        tlsMinVersion: '1.2',
        tlsMaxVersion: '1.3',
        cipherSuites: [4865, 4866],
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
