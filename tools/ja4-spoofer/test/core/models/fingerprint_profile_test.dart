import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';

void main() {
  group('FingerprintProfileMetadata', () {
    test('fromJson/toJson round-trip', () {
      final now = DateTime.utc(2024, 6, 1, 12);
      final m = FingerprintProfileMetadata(
        name: 'Test',
        source: 'captured',
        capturedAt: now,
        userAgent: 'Mozilla/5.0',
      );
      final m2 = FingerprintProfileMetadata.fromJson(m.toJson());
      expect(m2.name, 'Test');
      expect(m2.source, 'captured');
      expect(m2.capturedAt, now);
      expect(m2.userAgent, 'Mozilla/5.0');
    });

    test('missing captured_at → null', () {
      final m = FingerprintProfileMetadata.fromJson({'name': 'X'});
      expect(m.capturedAt, isNull);
    });

    test('missing name → Unnamed', () {
      final m = FingerprintProfileMetadata.fromJson({});
      expect(m.name, 'Unnamed');
    });

    test('toJson omits null captured_at and user_agent', () {
      const m = FingerprintProfileMetadata(name: 'X');
      final j = m.toJson();
      expect(j.containsKey('captured_at'), isFalse);
      expect(j.containsKey('user_agent'), isFalse);
    });
  });

  group('TlsClientHelloInputs', () {
    test('fromJson/toJson round-trip with all fields', () {
      final inputs = TlsClientHelloInputs(
        tlsMinVersion: '1.2',
        tlsMaxVersion: '1.3',
        cipherSuites: [4865, 4866],
        alpnProtocols: ['h2'],
        extensions: [0, 10],
        signatureAlgorithms: [2052],
        supportedVersions: [772, 771],
        supportedGroups: [29, 23],
        keyShareGroups: [29],
        pskKeyExchangeModes: [1],
        enableGrease: true,
        enableChXtnPermutation: true,
        sniMode: 'domain',
        cipherMode: 'exact',
        extensionMode: 'reorder',
      );
      final inputs2 = TlsClientHelloInputs.fromJson(inputs.toJson());
      expect(inputs2.tlsMinVersion, '1.2');
      expect(inputs2.tlsMaxVersion, '1.3');
      expect(inputs2.cipherSuites, [4865, 4866]);
      expect(inputs2.alpnProtocols, ['h2']);
      expect(inputs2.extensions, [0, 10]);
      expect(inputs2.signatureAlgorithms, [2052]);
      expect(inputs2.supportedVersions, [772, 771]);
      expect(inputs2.supportedGroups, [29, 23]);
      expect(inputs2.keyShareGroups, [29]);
      expect(inputs2.pskKeyExchangeModes, [1]);
      expect(inputs2.enableGrease, isTrue);
      expect(inputs2.enableChXtnPermutation, isTrue);
      expect(inputs2.sniMode, 'domain');
      expect(inputs2.cipherMode, 'exact');
      expect(inputs2.extensionMode, 'reorder');
    });

    test('fromJson null list fields → empty []', () {
      final inputs = TlsClientHelloInputs.fromJson({});
      expect(inputs.cipherSuites, isEmpty);
      expect(inputs.alpnProtocols, isEmpty);
      expect(inputs.extensions, isEmpty);
      expect(inputs.signatureAlgorithms, isEmpty);
      expect(inputs.supportedVersions, isEmpty);
      expect(inputs.supportedGroups, isEmpty);
      expect(inputs.keyShareGroups, isEmpty);
      expect(inputs.pskKeyExchangeModes, isEmpty);
    });

    test('fromJson non-list value for list fields → empty []', () {
      final inputs = TlsClientHelloInputs.fromJson({
        'cipher_suites': 'bad',
        'alpn_protocols': 42,
        'extensions': false,
        'signature_algorithms': {},
        'supported_versions': 'x',
        'supported_groups': {'a': 1},
        'key_share_groups': true,
        'psk_key_exchange_modes': 13,
      });
      expect(inputs.cipherSuites, isEmpty);
      expect(inputs.alpnProtocols, isEmpty);
      expect(inputs.extensions, isEmpty);
      expect(inputs.signatureAlgorithms, isEmpty);
      expect(inputs.supportedVersions, isEmpty);
      expect(inputs.supportedGroups, isEmpty);
      expect(inputs.keyShareGroups, isEmpty);
      expect(inputs.pskKeyExchangeModes, isEmpty);
    });

    test('copyWith updates individual fields', () {
      const base = TlsClientHelloInputs();
      final copy = base.copyWith(
        tlsMinVersion: '1.3',
        cipherSuites: [4865],
        enableGrease: true,
        sniMode: 'none',
      );
      expect(copy.tlsMinVersion, '1.3');
      expect(copy.tlsMaxVersion, '1.3'); // unchanged
      expect(copy.cipherSuites, [4865]);
      expect(copy.enableGrease, isTrue);
      expect(copy.sniMode, 'none');
    });

    test('copyWith with no args keeps all originals', () {
      final base = TlsClientHelloInputs(
        tlsMinVersion: '1.2',
        tlsMaxVersion: '1.3',
        cipherSuites: [4865],
        alpnProtocols: ['h2'],
        extensions: [0],
        signatureAlgorithms: [2052],
        supportedVersions: [772],
        supportedGroups: [29],
        keyShareGroups: [29],
        pskKeyExchangeModes: [1],
        enableGrease: true,
        enableChXtnPermutation: true,
        sniMode: 'none',
      );
      final copy = base.copyWith();
      expect(copy.tlsMinVersion, base.tlsMinVersion);
      expect(copy.tlsMaxVersion, base.tlsMaxVersion);
      expect(copy.cipherSuites, base.cipherSuites);
      expect(copy.alpnProtocols, base.alpnProtocols);
      expect(copy.extensions, base.extensions);
      expect(copy.signatureAlgorithms, base.signatureAlgorithms);
      expect(copy.supportedVersions, base.supportedVersions);
      expect(copy.supportedGroups, base.supportedGroups);
      expect(copy.keyShareGroups, base.keyShareGroups);
      expect(copy.pskKeyExchangeModes, base.pskKeyExchangeModes);
      expect(copy.enableGrease, base.enableGrease);
      expect(copy.enableChXtnPermutation, base.enableChXtnPermutation);
      expect(copy.sniMode, base.sniMode);
    });
  });

  group('FingerprintProfile', () {
    test('fromJson/toJson round-trip', () {
      final profile = FingerprintProfile(
        profileId: 'p-1',
        metadata: FingerprintProfileMetadata(
          name: 'Profile 1',
          source: 'manual',
          capturedAt: DateTime.utc(2024),
        ),
        inputs: TlsClientHelloInputs(
          cipherSuites: [4865],
          alpnProtocols: ['h2', 'http/1.1'],
        ),
      );
      final j = profile.toJson();
      final p2 = FingerprintProfile.fromJson(j);
      expect(p2.profileId, 'p-1');
      expect(p2.metadata.name, 'Profile 1');
      expect(p2.inputs.cipherSuites, [4865]);
      expect(p2.inputs.alpnProtocols, ['h2', 'http/1.1']);
    });

    test('fromJson with missing inputs section → graceful defaults', () {
      final p = FingerprintProfile.fromJson({'profile_id': 'x'});
      expect(p.inputs.cipherSuites, isEmpty);
      expect(p.inputs.tlsMinVersion, '1.2');
    });

    test('fromJson with missing metadata section → graceful defaults', () {
      final p = FingerprintProfile.fromJson({'profile_id': 'x'});
      expect(p.metadata.name, 'Unnamed');
      expect(p.metadata.source, 'manual');
    });

    test('fromJson missing profile_id → throws FormatException', () {
      // Reject profiles without an ID rather than silently writing them
      // to disk as "unknown.json" — that previously masked partially
      // written / hand-crafted imports and also created a path-traversal
      // surface (a profile_id of "../escape" would have escaped the
      // profiles directory).
      expect(
        () => FingerprintProfile.fromJson({}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson rejects path-traversal in profile_id', () {
      expect(
        () => FingerprintProfile.fromJson({'profile_id': '../escape'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => FingerprintProfile.fromJson({'profile_id': 'a/b'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('toJson includes schema_version=1', () {
      const p = FingerprintProfile(
        profileId: 'x',
        metadata: FingerprintProfileMetadata(name: 'X'),
        inputs: TlsClientHelloInputs(),
      );
      expect(p.toJson()['schema_version'], 1);
    });
  });
}
