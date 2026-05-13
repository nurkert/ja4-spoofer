import 'dart:async';
import 'dart:io';

import '../models/app_descriptor.dart';
import '../models/fingerprint_profile.dart';
import 'profile_args.dart';

/// Outcome eines einzelnen Compat-Probes.
enum ProbeOutcome {
  /// Connection succeeded and the server returned 2xx/3xx.
  compatible,

  /// TLS-Handshake-Failure / SSL-Error → Server lehnt diesen ClientHello ab.
  incompatible,

  /// Network or timeout error; no compatibility conclusion possible.
  inconclusive,
}

class ProbeResult {
  const ProbeResult({
    required this.endpoint,
    required this.outcome,
    this.exitCode,
    this.errorMessage,
  });

  final String endpoint;
  final ProbeOutcome outcome;
  final int? exitCode;
  final String? errorMessage;
}

/// Aggregat aller Probes pro Random-Roll.
class CompatScore {
  CompatScore(this.perEndpoint);

  final List<ProbeResult> perEndpoint;

  int get compatibleCount =>
      perEndpoint.where((r) => r.outcome == ProbeOutcome.compatible).length;
  int get incompatibleCount =>
      perEndpoint.where((r) => r.outcome == ProbeOutcome.incompatible).length;
  int get inconclusiveCount =>
      perEndpoint.where((r) => r.outcome == ProbeOutcome.inconclusive).length;
  int get total => perEndpoint.length;

  /// True when all probes are inconclusive. This is not a compatibility
  /// failure; it usually means network state prevented a useful result.
  bool get isInconclusive => inconclusiveCount == total;

  /// Status label such as "3/3" or "2/3".
  String get label => isInconclusive ? '?/$total' : '$compatibleCount/$total';
}

/// Default endpoints for compatibility probes. Hardcoded, no UI setting.
///
/// These are stable public domains that should be reachable in normal
/// Internet-connected environments. The tool must not depend on a project-owned
/// observation endpoint for compatibility probing.
const defaultProbeEndpoints = [
  'https://www.google.com',
  'https://www.cloudflare.com',
  'https://example.com',
];

/// Subprocess runner interface for tests.
abstract class ProbeRunner {
  Future<ProcessResult> run({
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
    required Duration timeout,
  });
}

class _RealProbeRunner implements ProbeRunner {
  const _RealProbeRunner();

  @override
  Future<ProcessResult> run({
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
    required Duration timeout,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      environment: environment,
      runInShell: false,
    );
    final stdoutFut = process.stdout.transform(SystemEncoding().decoder).join();
    final stderrFut = process.stderr.transform(SystemEncoding().decoder).join();
    final exitFut = process.exitCode;

    final exitCode = await exitFut.timeout(
      timeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    final stdout = await stdoutFut;
    final stderr = await stderrFut;
    return ProcessResult(process.pid, exitCode, stdout, stderr);
  }
}

/// Runs HEAD probes against endpoints with the rolled profile.
///
/// For each endpoint, patched curl is called with the profile args plus
/// `-sS -I --max-time`. Exit-code mapping:
/// * 0 → compatible
/// * 35 (CURLE_SSL_CONNECT_ERROR) / 60 (CURLE_PEER_FAILED_VERIFICATION)
///   → incompatible
/// * 6 (CURLE_COULDNT_RESOLVE_HOST), 7, 28 (CURLE_OPERATION_TIMEDOUT), -1
///   (Process-Timeout) → inconclusive
/// * everything else -> inconclusive to avoid false incompatibility signals
class CompatProber {
  const CompatProber({this.runner = const _RealProbeRunner()});

  final ProbeRunner runner;

  /// Runs one probe per endpoint in parallel.
  Future<CompatScore> probe({
    required AppDescriptor app,
    required FingerprintProfile profile,
    List<String> endpoints = defaultProbeEndpoints,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final curlBin = _resolveCurlBinary(app);
    if (curlBin == null) {
      return CompatScore(
        endpoints
            .map(
              (e) => ProbeResult(
                endpoint: e,
                outcome: ProbeOutcome.inconclusive,
                errorMessage: 'patched curl binary not found',
              ),
            )
            .toList(),
      );
    }

    final libDir = _resolveLibDir(curlBin);
    final env = <String, String>{...Platform.environment};
    if (libDir != null) {
      env['DYLD_LIBRARY_PATH'] = libDir;
      env['LD_LIBRARY_PATH'] = libDir;
    }

    final argsBase = profileToArgs(profile);

    final futures = endpoints.map((endpoint) async {
      final args = [
        ...argsBase,
        '-sS',
        '-I',
        '--max-time',
        timeout.inSeconds.toString(),
        endpoint,
      ];
      try {
        final result = await runner.run(
          executable: curlBin,
          arguments: args,
          environment: env,
          timeout: timeout + const Duration(seconds: 2),
        );
        return _classify(endpoint, result);
      } catch (e) {
        return ProbeResult(
          endpoint: endpoint,
          outcome: ProbeOutcome.inconclusive,
          errorMessage: e.toString(),
        );
      }
    });

    final results = await Future.wait(futures);
    return CompatScore(results);
  }

  ProbeResult _classify(String endpoint, ProcessResult result) {
    final exit = result.exitCode;
    if (exit == 0) {
      // HEAD success — Status-Code aus stdout grob parsen, aber selbst 4xx
      // bedeutet TLS-Handshake hat geklappt (kompatibel auf Wire-Ebene).
      return ProbeResult(
        endpoint: endpoint,
        outcome: ProbeOutcome.compatible,
        exitCode: 0,
      );
    }
    // Klare TLS-/SSL-Errors → incompatible
    if (exit == 35 || exit == 51 || exit == 60 || exit == 58 || exit == 77) {
      return ProbeResult(
        endpoint: endpoint,
        outcome: ProbeOutcome.incompatible,
        exitCode: exit,
        errorMessage: result.stderr.toString(),
      );
    }
    // Network-/Timeout-Probleme → inconclusive
    return ProbeResult(
      endpoint: endpoint,
      outcome: ProbeOutcome.inconclusive,
      exitCode: exit,
      errorMessage: result.stderr.toString(),
    );
  }

  String? _resolveCurlBinary(AppDescriptor app) {
    // Versuche die in launch.builtBinaryPaths gepflegten Pfade zu nutzen
    // (= patched curl im standardmäßigen Build-Output).
    for (final pathExpr in app.build.builtBinaryPaths) {
      final expanded = _expandHome(pathExpr);
      if (File(expanded).existsSync()) return expanded;
    }
    // Fallback: curl-spezifisches Standard-Layout. Kein Hardcoded-Path —
    // wir gehen den App-Descriptor durch.
    return null;
  }

  String? _resolveLibDir(String curlBin) {
    // Heuristik: install-Layout `~/build/curl-openssl-ja4/install/bin/curl`
    // → `~/build/openssl-ja4-standalone/install/{lib,lib64}`. Probe beides,
    // weil OpenSSL Configure auf Debian/x86_64 nach lib64/ installiert und
    // auf macOS/Arch nach lib/. Fallback: same dir.
    if (curlBin.contains('curl-openssl-ja4')) {
      final home = Platform.environment['HOME'] ?? '';
      const opensslInstall = 'build/openssl-ja4-standalone/install';
      for (final dirName in const ['lib', 'lib64']) {
        final candidate = '$home/$opensslInstall/$dirName';
        if (Directory(candidate).existsSync()) return candidate;
      }
    }
    return null;
  }

  String _expandHome(String path) {
    if (path.startsWith('~/')) {
      final home = Platform.environment['HOME'] ?? '';
      return '$home/${path.substring(2)}';
    }
    return path;
  }
}
