import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/services/ja4_verification_probe.dart';
import 'package:ja4_spoofer/core/utils/fingerprint_enforcement.dart';

/// Builds a real TLS 1.3 ClientHello record so the probe measures the same way
/// it will in production: bytes off a socket, not a synthesized struct.
Uint8List buildClientHello({
  required List<int> cipherSuites,
  required List<int> extensionOrder,
  List<int> signatureAlgorithms = const [0x0403],
  List<int> supportedVersions = const [0x0304],
  List<int> supportedGroups = const [0x001d],
  List<int> keyShareGroups = const [0x001d],
  List<int> pskModes = const [1],
  List<String> alpn = const ['h2'],
  String? sni = 'example.com',
}) {
  List<int> u16(int v) => [(v >> 8) & 0xff, v & 0xff];
  List<int> u16List(List<int> values) => [
    ...u16(values.length * 2),
    for (final v in values) ...u16(v),
  ];

  List<int> bodyFor(int type) {
    switch (type) {
      case 0x0000: // server_name
        final host = sni ?? '';
        final name = host.codeUnits;
        return [...u16(name.length + 3), 0x00, ...u16(name.length), ...name];
      case 0x000a: // supported_groups
        return u16List(supportedGroups);
      case 0x000d: // signature_algorithms
        return u16List(signatureAlgorithms);
      case 0x0010: // alpn
        final entries = <int>[];
        for (final p in alpn) {
          entries.addAll([p.length, ...p.codeUnits]);
        }
        return [...u16(entries.length), ...entries];
      case 0x002b: // supported_versions
        return [
          supportedVersions.length * 2,
          for (final v in supportedVersions) ...u16(v),
        ];
      case 0x002d: // psk_key_exchange_modes
        return [pskModes.length, ...pskModes];
      case 0x0033: // key_share
        final entries = <int>[];
        for (final g in keyShareGroups) {
          entries.addAll([...u16(g), ...u16(32), ...List.filled(32, 0x41)]);
        }
        return [...u16(entries.length), ...entries];
      default:
        return [];
    }
  }

  final extensionBytes = <int>[];
  for (final type in extensionOrder) {
    final body = bodyFor(type);
    extensionBytes.addAll([...u16(type), ...u16(body.length), ...body]);
  }

  final handshakeBody = <int>[
    ...u16(0x0303), // client_version
    ...List.filled(32, 0x2a), // random
    0x00, // session_id length
    ...u16List(cipherSuites),
    0x01, 0x00, // compression methods
    ...u16(extensionBytes.length),
    ...extensionBytes,
  ];

  final handshake = <int>[
    0x01, // ClientHello
    (handshakeBody.length >> 16) & 0xff,
    (handshakeBody.length >> 8) & 0xff,
    handshakeBody.length & 0xff,
    ...handshakeBody,
  ];

  return Uint8List.fromList([
    0x16, // handshake record
    0x03, 0x01,
    ...u16(handshake.length),
    ...handshake,
  ]);
}

FingerprintProfile profileFor({
  required List<int> ciphers,
  required List<int> extensions,
  List<int> sigalgs = const [0x0403],
  List<String> alpn = const ['h2'],
}) => FingerprintProfile(
  profileId: 'probe-test',
  metadata: const FingerprintProfileMetadata(name: 'Probe Test'),
  inputs: TlsClientHelloInputs(
    tlsMaxVersion: '1.3',
    cipherSuites: ciphers,
    cipherMode: 'exact',
    extensions: extensions,
    extensionMode: 'exact',
    signatureAlgorithms: sigalgs,
    supportedVersions: const [0x0304],
    supportedGroups: const [0x001d],
    keyShareGroups: const [0x001d],
    pskKeyExchangeModes: const [1],
    alpnProtocols: alpn,
    sniMode: 'domain',
  ),
);

/// Connects to the probe URL and writes [hello], standing in for a launched
/// client.
Future<void> sendHello(String probeUrl, Uint8List hello) async {
  final uri = Uri.parse(probeUrl);
  final socket = await Socket.connect(uri.host, uri.port);
  socket.add(hello);
  await socket.flush();
  // Give the probe a moment to read before the socket goes away.
  await socket.done.timeout(
    const Duration(seconds: 2),
    onTimeout: () async => socket.destroy(),
  );
}

void main() {
  const probe = Ja4VerificationProbe();
  const ciphers = [0x1301, 0x1302, 0x1303];
  const extensions = [0x0000, 0x000a, 0x000d, 0x0010, 0x002b, 0x002d, 0x0033];

  group('Ja4VerificationProbe', () {
    test('a matching ClientHello is confirmed against the profile', () async {
      final profile = profileFor(ciphers: ciphers, extensions: extensions);
      final hello = buildClientHello(
        cipherSuites: ciphers,
        extensionOrder: extensions,
      );

      final result = await probe.measure(
        profile: profile,
        launchClient: (url) => sendHello(url, hello),
        timeout: const Duration(seconds: 10),
      );

      expect(result.status, WireProbeStatus.observed);
      expect(result.observedJa4, result.intendedJa4);
      expect(result.deviations, isEmpty);
      expect(result.matches, isTrue);
      expect(result.headline, contains('stimmt'));
    });

    test('the measured JA4 equals the profile computation', () async {
      final profile = profileFor(ciphers: ciphers, extensions: extensions);
      final result = await probe.measure(
        profile: profile,
        launchClient: (url) => sendHello(
          url,
          buildClientHello(cipherSuites: ciphers, extensionOrder: extensions),
        ),
        timeout: const Duration(seconds: 10),
      );
      expect(result.observedJa4, intendedJa4For(profile));
    });

    test('a cipher the library dropped is caught on the wire', () async {
      final profile = profileFor(ciphers: ciphers, extensions: extensions);
      // The client emitted only two of the three requested suites.
      final hello = buildClientHello(
        cipherSuites: const [0x1301, 0x1302],
        extensionOrder: extensions,
      );

      final result = await probe.measure(
        profile: profile,
        launchClient: (url) => sendHello(url, hello),
        timeout: const Duration(seconds: 10),
      );

      expect(result.status, WireProbeStatus.observed);
      expect(result.matches, isFalse);
      expect(result.observedJa4, isNot(result.intendedJa4));
      final deviation = result.deviations.firstWhere(
        (d) => d.field == 'cipher_suites',
      );
      expect(deviation.requested, '4865,4866,4867');
      expect(deviation.actual, '4865,4866');
    });

    test('an extension the library added silently is caught on the wire', () {
      // This is the case the diagnostic dump structurally cannot report: the
      // stacks append the id and write the already-mutated list back as
      // "requested". Only an outside observer sees it.
      final profile = profileFor(
        ciphers: ciphers,
        extensions: const [0x0000, 0x000a, 0x000d, 0x0010, 0x002b, 0x0033],
      );
      final deviations = diffProfileAgainstWire(
        profile: profile,
        observed: TlsClientHelloInputs(
          cipherSuites: ciphers,
          extensions: extensions, // includes the appended 0x002d
          signatureAlgorithms: const [0x0403],
          alpnProtocols: const ['h2'],
        ),
      );
      expect(deviations.map((d) => d.field), contains('extension_order'));
    });

    test('ALPN drift is reported — the OpenSSL dump cannot show it', () {
      final profile = profileFor(
        ciphers: ciphers,
        extensions: extensions,
        alpn: const ['h2', 'http/1.1'],
      );
      final deviations = diffProfileAgainstWire(
        profile: profile,
        observed: const TlsClientHelloInputs(
          cipherSuites: ciphers,
          extensions: extensions,
          alpnProtocols: ['http/1.1'],
        ),
      );
      final alpn = deviations.firstWhere((d) => d.field == 'alpn');
      expect(alpn.requested, 'h2,http/1.1');
      expect(alpn.actual, 'http/1.1');
      expect(alpn.reason, contains('OpenSSL'));
    });

    test('fields the profile leaves open are not reported as drift', () {
      const profile = FingerprintProfile(
        profileId: 'open',
        metadata: FingerprintProfileMetadata(name: 'Open'),
        // Only ciphers are pinned; everything else is the library's choice.
        inputs: TlsClientHelloInputs(
          cipherSuites: ciphers,
          cipherMode: 'exact',
        ),
      );
      final deviations = diffProfileAgainstWire(
        profile: profile,
        observed: const TlsClientHelloInputs(
          cipherSuites: ciphers,
          extensions: [0x0000, 0x0033],
          signatureAlgorithms: [0x0403, 0x0804],
          supportedGroups: [0x001d, 0x0017],
          alpnProtocols: ['h2'],
        ),
      );
      expect(deviations, isEmpty);
    });

    test('a client that never connects is not a pass', () async {
      final profile = profileFor(ciphers: ciphers, extensions: extensions);
      final result = await probe.measure(
        profile: profile,
        launchClient: (_) async {}, // starts nothing
        timeout: const Duration(milliseconds: 400),
      );

      expect(result.status, WireProbeStatus.noConnection);
      expect(result.matches, isFalse);
      expect(result.observedJa4, isNull);
      expect(result.headline, contains('Keine Messung'));
    });

    test(
      'a client that fails to start is reported, not silently passed',
      () async {
        final profile = profileFor(ciphers: ciphers, extensions: extensions);
        final result = await probe.measure(
          profile: profile,
          launchClient: (_) async => throw const ProcessException('x', []),
          timeout: const Duration(milliseconds: 400),
        );

        expect(result.status, WireProbeStatus.failed);
        expect(result.matches, isFalse);
        expect(result.error, isNotNull);
      },
    );

    test('the probe binds loopback only', () async {
      // A self-check must not be reachable from the LAN. Assert by checking
      // the URL handed to the client.
      String? seenUrl;
      await probe.measure(
        profile: profileFor(ciphers: ciphers, extensions: extensions),
        launchClient: (url) async => seenUrl = url,
        timeout: const Duration(milliseconds: 300),
      );
      expect(seenUrl, startsWith('https://127.0.0.1:'));
    });
  });
}
