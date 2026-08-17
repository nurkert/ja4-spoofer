import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/utils/fingerprint_enforcement.dart';
import 'package:ja4_spoofer/core/utils/ja4_dump_verifier.dart';

const _ciphers = [4865, 4866, 4867];
const _extensions = [0, 10, 13, 16, 43, 51];
const _sigalgs = [1027, 2052];

FingerprintProfile _profile({
  List<int> ciphers = _ciphers,
  List<int> extensions = _extensions,
  List<int> sigalgs = _sigalgs,
  List<int> supportedVersions = const [772],
}) => FingerprintProfile(
  profileId: 'test',
  metadata: const FingerprintProfileMetadata(name: 'Test'),
  inputs: TlsClientHelloInputs(
    tlsMaxVersion: '1.3',
    cipherSuites: ciphers,
    cipherMode: 'exact',
    extensions: extensions,
    extensionMode: 'exact',
    signatureAlgorithms: sigalgs,
    supportedVersions: supportedVersions,
    supportedGroups: const [29],
    keyShareGroups: const [29],
    alpnProtocols: const ['h2'],
    sniMode: 'domain',
  ),
);

/// Builds a schema-v1 dump. Defaults describe a launch that honoured the
/// request exactly; named args let a test drift one field at a time.
String _dump({
  String active = '1',
  String applyOk = '1',
  String mismatchMask = '0',
  String? finalCiphers,
  String? finalExtensions,
  String? finalSigalgs,
  String enableGrease = '0',
  String greaseValue = '',
  String sniMode = 'domain',
  String tlsMax = '772',
}) {
  String csv(List<int> v) => v.join(',');
  return '''
active=$active
apply_ok=$applyOk
mismatch_mask=$mismatchMask

effective_tls_min=771
effective_tls_max=$tlsMax
strict=0
sni_mode=$sniMode
enable_grease=$enableGrease
enable_ch_xtn_permutation=0
grease_value=$greaseValue

requested_cipher_suites=${csv(_ciphers)}
requested_alpn=h2
requested_signature_algorithms=${csv(_sigalgs)}
requested_extension_order=${csv(_extensions)}
requested_supported_versions=772
requested_supported_groups=29
requested_key_share_groups=29
requested_psk_key_exchange_modes=

final_cipher_suites=${finalCiphers ?? csv(_ciphers)}
final_alpn=h2
final_signature_algorithms=${finalSigalgs ?? csv(_sigalgs)}
final_extension_order=${finalExtensions ?? csv(_extensions)}
final_supported_versions=772
final_supported_groups=29
final_key_share_groups=29
final_psk_key_exchange_modes=
''';
}

void main() {
  const verifier = Ja4DumpVerifier();

  group('Ja4DumpVerifier', () {
    test('a faithful dump confirms the fingerprint', () {
      final verdict = verifier.verify(
        dumpContent: _dump(),
        profile: _profile(),
      );
      expect(verdict.status, DumpVerdictStatus.verified);
      expect(verdict.deviations, isEmpty);
      expect(verdict.effectiveJa4, verdict.intendedJa4);
      expect(verdict.matches, isTrue);
      expect(verdict.headline, contains('bestätigt'));
    });

    test('active=0 is reported as "config ignored", not as success', () {
      // This is the NSS failure mode: a rejected config still writes
      // apply_ok=1 / mismatch_mask=0, so trusting those alone reports a
      // success while the app sent its native fingerprint.
      final verdict = verifier.verify(
        dumpContent: _dump(active: '0'),
        profile: _profile(),
      );
      expect(verdict.status, DumpVerdictStatus.configIgnored);
      expect(verdict.applyOk, isTrue);
      expect(verdict.mismatchMask, 0);
      expect(verdict.matches, isFalse);
      expect(verdict.headline, contains('NICHT angewendet'));
      expect(verdict.maskReasons.first, contains('active=0'));
    });

    test('a missing dump is not a pass', () {
      final verdict = verifier.noDump();
      expect(verdict.status, DumpVerdictStatus.noDump);
      expect(verdict.matches, isFalse);
      expect(verdict.maskReasons.first, contains('gepatchte'));
    });

    test('empty dump content is treated as no dump', () {
      final verdict = verifier.verify(
        dumpContent: '   \n# nur ein Kommentar\n',
        profile: _profile(),
      );
      expect(verdict.status, DumpVerdictStatus.noDump);
    });

    test('a dropped cipher is named as a deviation', () {
      final verdict = verifier.verify(
        dumpContent: _dump(
          finalCiphers: '4865,4866',
          mismatchMask: '128', // 0x0080 cipher_suites_mismatch
        ),
        profile: _profile(),
      );
      expect(verdict.deviations, hasLength(1));
      final deviation = verdict.deviations.single;
      expect(deviation.field, 'cipher_suites');
      expect(deviation.requested, '4865,4866,4867');
      expect(deviation.actual, '4865,4866');
      expect(deviation.reason, contains('cipher_suites_mismatch'));
      expect(verdict.matches, isFalse);
    });

    test('an extra extension changes the JA4 and is caught even without a '
        'mismatch bit', () {
      // The library appended 0x002d (45). No bit is set — exactly the
      // "requested side was already mutated" blind spot. The recomputed JA4
      // still exposes it.
      final verdict = verifier.verify(
        dumpContent: _dump(finalExtensions: '0,10,13,16,43,45,51'),
        profile: _profile(),
      );
      expect(verdict.effectiveJa4, isNot(verdict.intendedJa4));
      expect(verdict.ja4Matches, isFalse);
      expect(verdict.matches, isFalse);
      expect(verdict.deviations.single.reason, contains('PCAP'));
    });

    test('library-injected GREASE is tolerated', () {
      final verdict = verifier.verify(
        dumpContent: _dump(
          finalCiphers: '2570,4865,4866,4867',
          enableGrease: '1',
          greaseValue: '2570',
        ),
        profile: _profile(),
      );
      expect(verdict.deviations, isEmpty);
      // JA4 excludes GREASE, so the hashes still agree.
      expect(verdict.effectiveJa4, verdict.intendedJa4);
      expect(verdict.matches, isTrue);
    });

    test('trailing GREASE in sigalgs is tolerated', () {
      final verdict = verifier.verify(
        dumpContent: _dump(
          finalSigalgs: '1027,2052,2570',
          enableGrease: '1',
          greaseValue: '2570',
        ),
        profile: _profile(),
      );
      expect(verdict.deviations, isEmpty);
    });

    test('every set mismatch bit is decoded into a reason', () {
      final verdict = verifier.verify(
        dumpContent: _dump(mismatchMask: '4', applyOk: '0'),
        profile: _profile(),
      );
      expect(verdict.maskReasons, hasLength(1));
      expect(verdict.maskReasons.single, contains('key_share_mismatch'));
      expect(verdict.matches, isFalse);
    });

    test('several bits decode to several reasons', () {
      final verdict = verifier.verify(
        // 0x0080 | 0x0400
        dumpContent: _dump(mismatchMask: '1152', applyOk: '0'),
        profile: _profile(),
      );
      expect(verdict.maskReasons, hasLength(2));
    });

    test('the effective JA4 follows final_supported_versions', () {
      final verdict = verifier.verify(
        dumpContent: _dump(),
        profile: _profile(),
      );
      expect(verdict.effectiveJa4, startsWith('t13d'));
    });

    test('intended JA4 equals the standalone profile computation', () {
      final profile = _profile();
      final verdict = verifier.verify(dumpContent: _dump(), profile: profile);
      expect(verdict.intendedJa4, intendedJa4For(profile));
    });

    test('a JA4 match with a byte-level drift is reported distinctly', () {
      // supported_groups drifted but JA4 does not cover it: the JA4 matches
      // while the ClientHello does not.
      final dump = _dump().replaceAll(
        'final_supported_groups=29',
        'final_supported_groups=29,23',
      );
      final verdict = verifier.verify(dumpContent: dump, profile: _profile());
      expect(verdict.ja4Matches, isTrue);
      expect(verdict.matches, isFalse);
      expect(verdict.headline, contains('JA4 stimmt'));
    });
  });
}
