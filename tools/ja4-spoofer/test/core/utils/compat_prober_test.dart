import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/app_descriptor.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/utils/compat_prober.dart';

class _FakeRunner implements ProbeRunner {
  _FakeRunner(this._exitsByEndpoint);

  /// Map endpoint suffix → exit code to return for that probe.
  final Map<String, int> _exitsByEndpoint;
  int callCount = 0;

  @override
  Future<ProcessResult> run({
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
    required Duration timeout,
  }) async {
    callCount++;
    // Last arg is the endpoint.
    final endpoint = arguments.last;
    final code = _exitsByEndpoint.entries
        .firstWhere(
          (e) => endpoint.contains(e.key),
          orElse: () => const MapEntry('', 0),
        )
        .value;
    return ProcessResult(0, code, '', code == 0 ? '' : 'mock-error');
  }
}

class _ThrowingRunner implements ProbeRunner {
  @override
  Future<ProcessResult> run({
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
    required Duration timeout,
  }) async {
    throw Exception('boom');
  }
}

late Directory _tmp;
late String _fakeCurlBin;

AppDescriptor _appWithBin(String binPath) => AppDescriptor(
  appId: 'test',
  metadata: const AppDescriptorMetadata(name: 'Test'),
  build: AppBuildConfig(script: 'b.sh', builtBinaryPaths: [binPath]),
  launch: const AppLaunchConfig(script: 'r.sh', profileFormat: 'curl'),
);

FingerprintProfile _profile() => FingerprintProfile(
  profileId: 'p',
  metadata: const FingerprintProfileMetadata(name: 'P'),
  inputs: const TlsClientHelloInputs(
    tlsMinVersion: '1.2',
    tlsMaxVersion: '1.3',
    cipherSuites: [0x1301, 0x1302, 0x1303],
    extensions: [0, 10, 13, 43, 51],
    signatureAlgorithms: [0x0403, 0x0804],
    alpnProtocols: ['h2'],
  ),
);

void main() {
  setUpAll(() {
    _tmp = Directory.systemTemp.createTempSync('compat_prober_test_');
    _fakeCurlBin = '${_tmp.path}/fake-curl';
    File(_fakeCurlBin).writeAsStringSync('#!/bin/sh\nexit 0\n');
  });

  tearDownAll(() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  group('CompatProber.probe', () {
    test('all-zero exit → 3/3 compatible', () async {
      final prober = CompatProber(runner: _FakeRunner({}));
      final score = await prober.probe(
        app: _appWithBin(_fakeCurlBin),
        profile: _profile(),
      );
      expect(score.total, 3);
      expect(score.compatibleCount, 3);
      expect(score.incompatibleCount, 0);
      expect(score.label, '3/3');
      expect(score.isInconclusive, isFalse);
    });

    test('exit 35 on cloudflare → 2/3 compatible', () async {
      final prober = CompatProber(runner: _FakeRunner({'cloudflare': 35}));
      final score = await prober.probe(
        app: _appWithBin(_fakeCurlBin),
        profile: _profile(),
      );
      expect(score.compatibleCount, 2);
      expect(score.incompatibleCount, 1);
      final cf = score.perEndpoint.firstWhere(
        (r) => r.endpoint.contains('cloudflare'),
      );
      expect(cf.outcome, ProbeOutcome.incompatible);
      expect(cf.exitCode, 35);
    });

    test('exit 28 (timeout) → inconclusive, not incompatible', () async {
      final prober = CompatProber(runner: _FakeRunner({'google': 28}));
      final score = await prober.probe(
        app: _appWithBin(_fakeCurlBin),
        profile: _profile(),
      );
      final google = score.perEndpoint.firstWhere(
        (r) => r.endpoint.contains('google'),
      );
      expect(google.outcome, ProbeOutcome.inconclusive);
      expect(score.compatibleCount, 2);
      expect(score.incompatibleCount, 0);
      expect(score.inconclusiveCount, 1);
    });

    test('all inconclusive (Internet-down) → label "?/3"', () async {
      final prober = CompatProber(
        runner: _FakeRunner({'google': 28, 'cloudflare': 6, 'example': 7}),
      );
      final score = await prober.probe(
        app: _appWithBin(_fakeCurlBin),
        profile: _profile(),
      );
      expect(score.isInconclusive, isTrue);
      expect(score.label, '?/3');
      expect(score.compatibleCount, 0);
      expect(score.incompatibleCount, 0);
    });

    test('runner throws → all probes inconclusive (graceful)', () async {
      final prober = CompatProber(runner: _ThrowingRunner());
      final score = await prober.probe(
        app: _appWithBin(_fakeCurlBin),
        profile: _profile(),
      );
      expect(score.isInconclusive, isTrue);
      for (final r in score.perEndpoint) {
        expect(r.outcome, ProbeOutcome.inconclusive);
        expect(r.errorMessage, contains('boom'));
      }
    });

    test(
      'curl binary missing → all inconclusive without subprocess call',
      () async {
        final runner = _FakeRunner({});
        final prober = CompatProber(runner: runner);
        final score = await prober.probe(
          app: _appWithBin('/nonexistent/path/to/curl'),
          profile: _profile(),
        );
        expect(score.isInconclusive, isTrue);
        expect(
          runner.callCount,
          0,
          reason: 'must not invoke runner if binary is missing',
        );
        expect(score.perEndpoint.first.errorMessage, contains('not found'));
      },
    );

    test('respects custom endpoint list', () async {
      final runner = _FakeRunner({});
      final prober = CompatProber(runner: runner);
      final score = await prober.probe(
        app: _appWithBin(_fakeCurlBin),
        profile: _profile(),
        endpoints: const [
          'https://test.example.org',
          'https://other.example.org',
        ],
      );
      expect(score.total, 2);
      expect(runner.callCount, 2);
    });
  });

  group('CompatScore label semantics', () {
    test('mixed counts produce correct label', () {
      final s = CompatScore([
        const ProbeResult(
          endpoint: 'a',
          outcome: ProbeOutcome.compatible,
          exitCode: 0,
        ),
        const ProbeResult(
          endpoint: 'b',
          outcome: ProbeOutcome.incompatible,
          exitCode: 35,
        ),
        const ProbeResult(
          endpoint: 'c',
          outcome: ProbeOutcome.inconclusive,
          exitCode: 28,
        ),
      ]);
      expect(s.label, '1/3');
      expect(s.compatibleCount, 1);
      expect(s.incompatibleCount, 1);
      expect(s.inconclusiveCount, 1);
      expect(s.isInconclusive, isFalse);
    });
  });

  group('defaultProbeEndpoints', () {
    test('does not contain project-owned observation endpoints', () {
      for (final endpoint in defaultProbeEndpoints) {
        expect(
          endpoint,
          isNot(contains('project-observer.example')),
          reason:
              'compatibility probes must not depend on a project-owned observation endpoint',
        );
      }
    });
  });
}
