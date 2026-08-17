import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/capture_record.dart';
import '../models/fingerprint_profile.dart';
import '../utils/fingerprint_enforcement.dart';
import '../utils/ja4_dump_verifier.dart';
import 'ja4_capture_server.dart';

/// Why a wire measurement did or did not happen.
enum WireProbeStatus {
  /// A ClientHello was read off the socket and compared.
  observed,

  /// The client never connected to the probe within the timeout.
  noConnection,

  /// The probe could not be started (port binding, launch failure).
  failed,
}

/// An independent measurement of what a client actually put on the wire.
///
/// This is the counterpart to [DumpVerdict]. The dump is the patched library
/// reporting on itself; this is a ClientHello read off a socket by code that
/// shares nothing with the library, then hashed with the same JA4
/// implementation the profile is hashed with. When the two disagree, this one
/// is the measurement.
@immutable
class WireObservation {
  const WireObservation({
    required this.status,
    required this.intendedJa4,
    this.observedJa4,
    this.observedInputs,
    this.deviations = const [],
    this.error,
  });

  final WireProbeStatus status;

  /// JA4 the selected profile describes.
  final String intendedJa4;

  /// JA4 computed from the ClientHello that actually arrived.
  final String? observedJa4;

  /// The full ClientHello shape as it arrived, for field-level comparison.
  final TlsClientHelloInputs? observedInputs;

  /// Fields where the arriving ClientHello differs from the profile.
  final List<DumpDeviation> deviations;

  final String? error;

  /// The only unqualified proof this app can produce: the fingerprint that
  /// went out is the one that was selected.
  bool get matches =>
      status == WireProbeStatus.observed && observedJa4 == intendedJa4;

  String get headline => switch (status) {
    WireProbeStatus.observed when matches =>
      'Gemessen: gesendeter Fingerprint stimmt mit der Auswahl überein',
    WireProbeStatus.observed =>
      'Gemessen: es wurde ein anderer Fingerprint gesendet',
    WireProbeStatus.noConnection =>
      'Keine Messung — der Client hat den Prüf-Server nicht kontaktiert',
    WireProbeStatus.failed => 'Messung fehlgeschlagen',
  };
}

/// Measures the fingerprint a client really emits.
///
/// Starts a loopback-only TLS sniffer on an ephemeral port, hands the caller
/// the resulting `https://127.0.0.1:<port>/` URL to point a client at, reads
/// the first ClientHello that arrives and compares it against the profile.
///
/// The sniffer never completes a handshake — it reads the ClientHello, replies
/// with a fatal `handshake_failure` alert and closes. The client will report a
/// TLS error, which is expected: the connection exists only to be measured.
class Ja4VerificationProbe {
  const Ja4VerificationProbe();

  /// Runs [launchClient] against a freshly bound probe and returns what
  /// arrived.
  ///
  /// [launchClient] receives the probe URL and must start the client; it may
  /// return before the client exits. The probe resolves as soon as the first
  /// ClientHello lands, so a browser that stays open does not block the result.
  Future<WireObservation> measure({
    required FingerprintProfile profile,
    required Future<void> Function(String probeUrl) launchClient,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final intended = intendedJa4For(profile);
    final server = Ja4CaptureServer(
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4,
      // A single probe run; no need to accumulate or group.
      maxHistory: 8,
      deduplicationWindow: Duration.zero,
    );

    try {
      await server.start();
    } catch (e) {
      server.dispose();
      return WireObservation(
        status: WireProbeStatus.failed,
        intendedJa4: intended,
        error: 'Prüf-Server konnte nicht gestartet werden: $e',
      );
    }

    final port = server.boundPort;
    if (port == null) {
      server.dispose();
      return WireObservation(
        status: WireProbeStatus.failed,
        intendedJa4: intended,
        error: 'Prüf-Server hat keinen Port erhalten.',
      );
    }

    // A Completer rather than `onCapture.first`: when the client fails to
    // start we tear the server down immediately, and a dangling `first` would
    // then surface the stream closing as an unhandled "No element" error.
    final captured = Completer<CaptureRecord>();
    final subscription = server.onCapture.listen((record) {
      if (!captured.isCompleted) captured.complete(record);
    });

    CaptureRecord? record;
    try {
      try {
        await launchClient('https://127.0.0.1:$port/');
      } catch (e) {
        return WireObservation(
          status: WireProbeStatus.failed,
          intendedJa4: intended,
          error: 'Client konnte nicht gestartet werden: $e',
        );
      }

      try {
        record = await captured.future.timeout(timeout);
      } on TimeoutException {
        record = null;
      }
    } finally {
      await subscription.cancel();
      server.dispose();
    }

    if (record == null) {
      return WireObservation(
        status: WireProbeStatus.noConnection,
        intendedJa4: intended,
      );
    }

    final observed = record.tlsInputs;
    return WireObservation(
      status: WireProbeStatus.observed,
      intendedJa4: intended,
      observedJa4: record.ja4Hash,
      observedInputs: observed,
      deviations: observed == null
          ? const []
          : diffProfileAgainstWire(profile: profile, observed: observed),
    );
  }
}

/// Field-level comparison of a profile against the ClientHello that arrived.
///
/// Only fields the profile actually requested are compared — an empty list in
/// the profile means "library's choice", and reporting the library's choice as
/// a deviation would be noise. GREASE is already stripped by the capture path
/// on both sides.
List<DumpDeviation> diffProfileAgainstWire({
  required FingerprintProfile profile,
  required TlsClientHelloInputs observed,
}) {
  final inputs = profile.inputs;
  final deviations = <DumpDeviation>[];

  void compareInts(String field, String label, List<int> want, List<int> got) {
    if (want.isEmpty) return;
    if (_intListEquals(want, got)) return;
    deviations.add(
      DumpDeviation(
        field: field,
        requested: want.join(','),
        actual: got.join(','),
        reason:
            '$label auf dem Draht weicht vom Profil ab. Gemessen am '
            'eingehenden ClientHello, unabhängig von der Selbstauskunft der '
            'Library.',
      ),
    );
  }

  compareInts(
    'cipher_suites',
    'Cipher-Suites',
    inputs.cipherSuites,
    observed.cipherSuites,
  );
  compareInts(
    'extension_order',
    'Extension-Reihenfolge',
    inputs.extensions,
    observed.extensions,
  );
  compareInts(
    'signature_algorithms',
    'Signature Algorithms',
    inputs.signatureAlgorithms,
    observed.signatureAlgorithms,
  );
  compareInts(
    'supported_versions',
    'supported_versions',
    inputs.supportedVersions,
    observed.supportedVersions,
  );
  compareInts(
    'supported_groups',
    'supported_groups',
    inputs.supportedGroups,
    observed.supportedGroups,
  );
  compareInts(
    'key_share_groups',
    'key_share_groups',
    inputs.keyShareGroups,
    observed.keyShareGroups,
  );
  compareInts(
    'psk_key_exchange_modes',
    'psk_key_exchange_modes',
    inputs.pskKeyExchangeModes,
    observed.pskKeyExchangeModes,
  );

  if (inputs.alpnProtocols.isNotEmpty &&
      !_stringListEquals(inputs.alpnProtocols, observed.alpnProtocols)) {
    deviations.add(
      DumpDeviation(
        field: 'alpn',
        requested: inputs.alpnProtocols.join(','),
        actual: observed.alpnProtocols.join(','),
        reason:
            'ALPN auf dem Draht weicht vom Profil ab. Gemessen am eingehenden '
            'ClientHello — auf OpenSSL ist das die einzige Quelle, die diese '
            'Abweichung überhaupt zeigen kann, weil der Dump ALPN aus dem '
            'Request zurückspiegelt.',
      ),
    );
  }

  return deviations;
}

bool _intListEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _stringListEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
