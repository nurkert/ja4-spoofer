import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/utils/profile_args.dart';

FingerprintProfile _profile(TlsClientHelloInputs inputs) => FingerprintProfile(
  profileId: 'test',
  metadata: const FingerprintProfileMetadata(name: 'Test'),
  inputs: inputs,
);

FingerprintProfile _capturedProfile(TlsClientHelloInputs inputs) =>
    FingerprintProfile(
      profileId: 'captured-test',
      metadata: const FingerprintProfileMetadata(
        name: 'Captured Test',
        source: 'captured',
      ),
      inputs: inputs,
    );

void main() {
  group('profileToArgs', () {
    test(
      'all fields empty/false → only the captured-profile coercion flags',
      () {
        final args = profileToArgs(
          _profile(
            const TlsClientHelloInputs(
              tlsMinVersion: '',
              tlsMaxVersion: '',
              sniMode: '',
            ),
          ),
        );
        // Captured profiles always force GREASE+permutation off so JA4 stays
        // stable on replay (see captured-profile coercion in profile_args.dart).
        expect(
          args,
          equals(['--enable-grease', '0', '--enable-ch-xtn-permutation', '0']),
        );
      },
    );

    test('all fields populated → correct flag-value pairs', () {
      final args = profileToArgs(
        _profile(
          TlsClientHelloInputs(
            tlsMinVersion: '1.2',
            tlsMaxVersion: '1.3',
            cipherSuites: [4865, 4866],
            cipherMode: 'exact',
            alpnProtocols: ['h2'],
            signatureAlgorithms: [2052],
            supportedVersions: [772, 771],
            supportedGroups: [29, 23],
            keyShareGroups: [29],
            pskKeyExchangeModes: [1],
            extensions: [0, 10],
            extensionMode: 'reorder',
            sniMode: 'present',
            enableGrease: true,
            enableChXtnPermutation: true,
          ),
        ),
      );

      expect(args, containsAllInOrder(['--tls-min', '1.2']));
      expect(args, containsAllInOrder(['--tls-max', '1.3']));
      expect(args, containsAllInOrder(['--cipher-suites', '4865,4866']));
      expect(args, containsAllInOrder(['--cipher-mode', 'exact']));
      expect(args, containsAllInOrder(['--alpn', 'h2']));
      expect(args, containsAllInOrder(['--signature-algorithms', '2052']));
      expect(args, containsAllInOrder(['--supported-versions', '772,771']));
      expect(args, containsAllInOrder(['--supported-groups', '29,23']));
      expect(args, containsAllInOrder(['--key-share-groups', '29']));
      expect(args, containsAllInOrder(['--psk-key-exchange-modes', '1']));
      expect(args, containsAllInOrder(['--extension-order', '0,10']));
      expect(args, containsAllInOrder(['--extension-mode', 'reorder']));
      expect(args, containsAllInOrder(['--sni-mode', 'present']));
      expect(args, containsAllInOrder(['--enable-grease', '1']));
      expect(args, containsAllInOrder(['--enable-ch-xtn-permutation', '1']));
    });

    test('captured + enableGrease=false → coerced to --enable-grease 0', () {
      final args = profileToArgs(_profile(const TlsClientHelloInputs()));
      expect(args, containsAllInOrder(['--enable-grease', '0']));
    });

    test('enableGrease=true → includes --enable-grease 1', () {
      final args = profileToArgs(
        _profile(const TlsClientHelloInputs(enableGrease: true)),
      );
      expect(args, containsAllInOrder(['--enable-grease', '1']));
    });

    test('captured + enableChXtnPermutation=false → coerced to 0', () {
      final args = profileToArgs(_profile(const TlsClientHelloInputs()));
      expect(args, containsAllInOrder(['--enable-ch-xtn-permutation', '0']));
    });

    test('enableChXtnPermutation=true → emitted', () {
      final args = profileToArgs(
        _profile(const TlsClientHelloInputs(enableChXtnPermutation: true)),
      );
      expect(args, containsAllInOrder(['--enable-ch-xtn-permutation', '1']));
    });

    test('empty tlsMinVersion → no --tls-min', () {
      final args = profileToArgs(
        _profile(const TlsClientHelloInputs(tlsMinVersion: '')),
      );
      expect(args.contains('--tls-min'), isFalse);
    });

    test('non-empty tlsMinVersion → --tls-min included', () {
      final args = profileToArgs(
        _profile(const TlsClientHelloInputs(tlsMinVersion: '1.2')),
      );
      expect(args, containsAllInOrder(['--tls-min', '1.2']));
    });

    test('empty alpnProtocols → no --alpn', () {
      final args = profileToArgs(_profile(const TlsClientHelloInputs()));
      expect(args.contains('--alpn'), isFalse);
    });

    test('captured profile without explicit cipherMode defaults to exact', () {
      final args = profileToArgs(
        _capturedProfile(
          const TlsClientHelloInputs(cipherSuites: [4865, 4866]),
        ),
      );

      expect(args, containsAllInOrder(['--cipher-mode', 'exact']));
    });

    test(
      'captured profile without explicit extensionMode defaults to exact',
      () {
        final args = profileToArgs(
          _capturedProfile(
            const TlsClientHelloInputs(extensions: [0, 10, 13, 43]),
          ),
        );

        expect(args, containsAllInOrder(['--extension-mode', 'exact']));
      },
    );
  });
}
