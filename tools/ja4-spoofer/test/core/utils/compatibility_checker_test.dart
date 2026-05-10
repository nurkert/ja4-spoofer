import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/app_descriptor.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/utils/compatibility_checker.dart';

FingerprintProfile _profile({
  String tlsMin = '1.2',
  String tlsMax = '1.3',
  List<int> ciphers = const [],
  List<int> extensions = const [],
  List<int> sigs = const [],
  List<String> alpn = const [],
}) => FingerprintProfile(
  profileId: 'test',
  metadata: const FingerprintProfileMetadata(name: 'Test'),
  inputs: TlsClientHelloInputs(
    tlsMinVersion: tlsMin,
    tlsMaxVersion: tlsMax,
    cipherSuites: ciphers,
    extensions: extensions,
    signatureAlgorithms: sigs,
    alpnProtocols: alpn,
  ),
);

AppDescriptor _app({
  String name = 'Firefox JA4',
  List<String> tlsVersions = const ['1.2', '1.3'],
  List<int> ciphers = const [],
  List<int> extensions = const [],
  List<int> sigs = const [],
  List<String> alpn = const [],
}) => AppDescriptor(
  appId: 'test-app',
  metadata: AppDescriptorMetadata(name: name),
  build: const AppBuildConfig(script: 'scripts/build.sh', builtBinaryPaths: []),
  launch: const AppLaunchConfig(script: 'scripts/run.sh', profileFormat: 'nss'),
  tlsDefaults: AppTlsDefaults(
    tlsVersions: tlsVersions,
    cipherSuites: ciphers,
    extensions: extensions,
    signatureAlgorithms: sigs,
    alpnProtocols: alpn,
  ),
);

void main() {
  const checker = CompatibilityChecker();

  group('cipher support', () {
    test('unsupported cipher with overlap is a warning, not error', () {
      final result = checker.check(
        _profile(ciphers: [0x1301, 0x1302]),
        _app(ciphers: [0x1301]),
      );

      final issue = result.issues.firstWhere(
        (i) => i.code == 'UNSUPPORTED_CIPHERS',
      );
      expect(issue.level, CompatibilityLevel.warning);
      expect(result.issues.any((i) => i.code == 'NO_CIPHER_OVERLAP'), isFalse);
      expect(result.isCompatible, isTrue);
    });

    test('no overlap produces NO_CIPHER_OVERLAP', () {
      final result = checker.check(
        _profile(ciphers: [0x1302]),
        _app(ciphers: [0x1301]),
      );

      expect(result.issues.any((i) => i.code == 'UNSUPPORTED_CIPHERS'), isTrue);
      expect(result.issues.any((i) => i.code == 'NO_CIPHER_OVERLAP'), isTrue);
      expect(result.isCompatible, isFalse);
    });

    test('matching ciphers produce no cipher issues', () {
      final result = checker.check(
        _profile(ciphers: [0x1301]),
        _app(ciphers: [0x1301, 0x1302]),
      );

      expect(
        result.issues.any((i) => i.code == 'UNSUPPORTED_CIPHERS'),
        isFalse,
      );
      expect(result.issues.any((i) => i.code == 'NO_CIPHER_OVERLAP'), isFalse);
      expect(result.isCompatible, isTrue);
    });
  });

  group('non-fatal compatibility issues', () {
    test('unsupported extensions are warnings', () {
      final result = checker.check(
        _profile(extensions: [0x0000, 0x0010]),
        _app(extensions: [0x0000]),
      );

      final issue = result.issues.firstWhere(
        (i) => i.code == 'UNSUPPORTED_EXTENSIONS',
      );
      expect(issue.level, CompatibilityLevel.warning);
      expect(result.isCompatible, isTrue);
    });

    test('unsupported signature algorithms are warnings', () {
      final result = checker.check(
        _profile(sigs: [0x0403, 0x0804]),
        _app(sigs: [0x0403]),
      );

      final issue = result.issues.firstWhere(
        (i) => i.code == 'UNSUPPORTED_SIGALGS',
      );
      expect(issue.level, CompatibilityLevel.warning);
      expect(result.isCompatible, isTrue);
    });

    test('unsupported ALPN values are warnings', () {
      final result = checker.check(
        _profile(alpn: ['h2', 'http/1.1']),
        _app(alpn: ['h2']),
      );

      final issue = result.issues.firstWhere(
        (i) => i.code == 'UNSUPPORTED_ALPN',
      );
      expect(issue.level, CompatibilityLevel.warning);
      expect(result.isCompatible, isTrue);
    });
  });

  group('TLS version support', () {
    test('unsupported max version produces error', () {
      final result = checker.check(
        _profile(tlsMax: '1.3'),
        _app(tlsVersions: ['1.2']),
      );

      final issue = result.issues.firstWhere(
        (i) => i.code == 'UNSUPPORTED_TLS_VERSION',
      );
      expect(issue.level, CompatibilityLevel.error);
      expect(result.isCompatible, isFalse);
    });

    test('supported max version is accepted', () {
      final result = checker.check(
        _profile(tlsMax: '1.2'),
        _app(tlsVersions: ['1.2']),
      );

      expect(
        result.issues.any((i) => i.code == 'UNSUPPORTED_TLS_VERSION'),
        isFalse,
      );
      expect(result.isCompatible, isTrue);
    });
  });

  group('missing defaults', () {
    test('apps without defaults return a warning', () {
      final result = checker.check(
        _profile(ciphers: [0x1301]),
        _app(
          name: 'Unknown SSL',
          tlsVersions: const [],
          ciphers: const [],
          extensions: const [],
          sigs: const [],
          alpn: const [],
        ),
      );

      final issue = result.issues.firstWhere((i) => i.code == 'NO_DEFAULTS');
      expect(issue.level, CompatibilityLevel.warning);
      expect(result.appName, 'Unknown SSL');
      expect(result.isCompatible, isTrue);
    });
  });
}
