import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/models/ja4_stack.dart';
import 'package:ja4_spoofer/core/utils/fingerprint_enforcement.dart';

FingerprintProfile _profile(
  TlsClientHelloInputs inputs, {
  String source = 'manual',
}) => FingerprintProfile(
  profileId: 'test',
  metadata: FingerprintProfileMetadata(name: 'Test', source: source),
  inputs: inputs,
);

/// A profile that survives every check: exact modes, and every configured body
/// override has its extension id present.
TlsClientHelloInputs _cleanInputs() => const TlsClientHelloInputs(
  tlsMinVersion: '1.2',
  tlsMaxVersion: '1.3',
  cipherSuites: [4865, 4866],
  cipherMode: 'exact',
  extensions: [0, 10, 13, 16, 43, 45, 51],
  extensionMode: 'exact',
  signatureAlgorithms: [1027],
  supportedVersions: [772, 771],
  supportedGroups: [29, 23],
  keyShareGroups: [29],
  pskKeyExchangeModes: [1],
  alpnProtocols: ['h2'],
  sniMode: 'domain',
);

EnforcementIssue _issue(EnforcementReport report, String field) =>
    report.issues.firstWhere((i) => i.field == field);

bool _hasField(EnforcementReport report, String field) =>
    report.issues.any((i) => i.field == field);

void main() {
  group('checkFingerprintEnforcement', () {
    test('a fully specified exact profile raises no blockers', () {
      final report = checkFingerprintEnforcement(
        profile: _profile(_cleanInputs()),
        stack: Ja4Stack.nss,
      );
      expect(
        report.hasBlockers,
        isFalse,
        reason: report.blockers.map((i) => i.title).join(' | '),
      );
      expect(report.warnings, isEmpty);
      // The best-effort note is always present so the user knows the launch is
      // tolerant and the post-launch check is what proves the result.
      expect(_hasField(report, 'strict'), isTrue);
    });

    test('manual profile without cipher_mode is blocked', () {
      final report = checkFingerprintEnforcement(
        profile: _profile(
          const TlsClientHelloInputs(cipherSuites: [4865, 4866]),
        ),
        stack: Ja4Stack.nss,
      );
      final issue = _issue(report, 'cipher_mode');
      expect(issue.severity, EnforcementSeverity.blocker);
      expect(issue.autoFixable, isTrue);
      expect(issue.reason, contains('reorder'));
    });

    test('manual profile without extension_mode is blocked', () {
      final report = checkFingerprintEnforcement(
        profile: _profile(const TlsClientHelloInputs(extensions: [0, 43])),
        stack: Ja4Stack.nss,
      );
      final issue = _issue(report, 'extension_mode');
      expect(issue.severity, EnforcementSeverity.blocker);
      expect(issue.autoFixable, isTrue);
    });

    test('captured profiles get exact modes implicitly and are not blocked '
        'for mode reasons', () {
      final report = checkFingerprintEnforcement(
        profile: _profile(
          const TlsClientHelloInputs(
            cipherSuites: [4865],
            extensions: [0, 16],
            alpnProtocols: ['h2'],
            sniMode: 'domain',
          ),
          source: 'captured',
        ),
        stack: Ja4Stack.nss,
      );
      expect(_hasField(report, 'cipher_mode'), isFalse);
      expect(_hasField(report, 'extension_mode'), isFalse);
    });

    test('exact mode without a list is a blocker', () {
      final report = checkFingerprintEnforcement(
        profile: _profile(
          const TlsClientHelloInputs(
            cipherMode: 'exact',
            extensionMode: 'exact',
          ),
        ),
        stack: Ja4Stack.nss,
      );
      expect(
        report.blockers.map((i) => i.field),
        containsAll(<String>['cipher_suites', 'extension_order']),
      );
    });

    test('tls_min greater than tls_max is a blocker and auto-fixable', () {
      final report = checkFingerprintEnforcement(
        profile: _profile(
          const TlsClientHelloInputs(
            tlsMinVersion: '1.3',
            tlsMaxVersion: '1.2',
          ),
        ),
        stack: Ja4Stack.nss,
      );
      final issue = _issue(report, 'tls_min');
      expect(issue.severity, EnforcementSeverity.blocker);
      expect(issue.autoFixable, isTrue);
    });

    test('key_share_groups outside supported_groups is a blocker', () {
      final report = checkFingerprintEnforcement(
        profile: _profile(
          const TlsClientHelloInputs(
            supportedGroups: [29],
            keyShareGroups: [23],
            extensions: [10, 51],
            extensionMode: 'exact',
          ),
        ),
        stack: Ja4Stack.nss,
      );
      final issue = _issue(report, 'key_share_groups');
      expect(issue.severity, EnforcementSeverity.blocker);
      expect(issue.deviation, contains('23'));
    });

    test('a body override without its extension id is flagged as a silent '
        'library append', () {
      final report = checkFingerprintEnforcement(
        profile: _profile(
          const TlsClientHelloInputs(
            // supported_versions configured, but 0x002b (43) is missing.
            extensions: [0, 10, 13, 16, 51],
            extensionMode: 'exact',
            supportedVersions: [772],
            supportedGroups: [29],
            keyShareGroups: [29],
            signatureAlgorithms: [1027],
            alpnProtocols: ['h2'],
            sniMode: 'domain',
          ),
        ),
        stack: Ja4Stack.nss,
      );
      final issue = _issue(report, 'extension_order');
      expect(issue.severity, EnforcementSeverity.blocker);
      expect(issue.deviation, contains('0x002b'));
      expect(issue.deviation, contains('supported_versions'));
      // The point of this rule: the dump cannot report it.
      expect(issue.reason, contains('Dump'));
    });

    test('OpenSSL cannot honour key_share_groups', () {
      final report = checkFingerprintEnforcement(
        profile: _profile(_cleanInputs()),
        stack: Ja4Stack.openssl,
      );
      final issue = report.warnings.firstWhere(
        (i) => i.field == 'key_share_groups',
      );
      expect(issue.reason, contains('0x0004'));
    });

    test('the same profile raises no key_share warning on NSS', () {
      final report = checkFingerprintEnforcement(
        profile: _profile(_cleanInputs()),
        stack: Ja4Stack.nss,
      );
      expect(
        report.warnings.any((i) => i.field == 'key_share_groups'),
        isFalse,
      );
    });

    test('unknown extension ids are reported as empty stubs', () {
      final report = checkFingerprintEnforcement(
        profile: _profile(
          const TlsClientHelloInputs(
            extensions: [0, 16, 65037],
            extensionMode: 'exact',
            alpnProtocols: ['h2'],
            sniMode: 'domain',
          ),
        ),
        stack: Ja4Stack.boringssl,
        knownExtensionIds: const {0, 16},
      );
      final issue = report.warnings.firstWhere((i) => i.title.contains('Stub'));
      expect(issue.deviation, contains('0xfe0d'));
    });

    test('GREASE values are not mistaken for unknown extensions', () {
      final report = checkFingerprintEnforcement(
        profile: _profile(
          const TlsClientHelloInputs(
            extensions: [0, 16, 0x0a0a],
            extensionMode: 'exact',
            alpnProtocols: ['h2'],
            sniMode: 'domain',
          ),
        ),
        stack: Ja4Stack.boringssl,
        knownExtensionIds: const {0, 16},
      );
      expect(report.warnings.any((i) => i.title.contains('Stub')), isFalse);
    });

    test('captured profiles report the GREASE coercion as info', () {
      final report = checkFingerprintEnforcement(
        profile: _profile(
          const TlsClientHelloInputs(
            cipherSuites: [4865],
            extensions: [0, 16],
            alpnProtocols: ['h2'],
            sniMode: 'domain',
            enableGrease: true,
          ),
          source: 'captured',
        ),
        stack: Ja4Stack.boringssl,
      );
      final issue = _issue(report, 'enable_grease');
      expect(issue.severity, EnforcementSeverity.info);
    });

    test('intendedJa4 follows supported_versions, not tls_max', () {
      final tls12 = checkFingerprintEnforcement(
        profile: _profile(
          const TlsClientHelloInputs(
            tlsMaxVersion: '1.3',
            supportedVersions: [771],
            cipherSuites: [4865],
            cipherMode: 'exact',
            extensions: [43],
            extensionMode: 'exact',
            sniMode: 'domain',
          ),
        ),
        stack: Ja4Stack.nss,
      );
      expect(tls12.intendedJa4.startsWith('t12d'), isTrue);
    });
  });

  group('applyEnforcementAutoFixes', () {
    test('sets both exact modes', () {
      final profile = _profile(
        const TlsClientHelloInputs(
          cipherSuites: [4865],
          extensions: [0, 16],
          alpnProtocols: ['h2'],
          sniMode: 'domain',
        ),
      );
      final report = checkFingerprintEnforcement(
        profile: profile,
        stack: Ja4Stack.nss,
      );
      final fixed = applyEnforcementAutoFixes(profile, report);
      expect(fixed.inputs.cipherMode, 'exact');
      expect(fixed.inputs.extensionMode, 'exact');
    });

    test('appends implied extension ids before pre_shared_key', () {
      final profile = _profile(
        const TlsClientHelloInputs(
          extensions: [0, 16, 41], // 41 = pre_shared_key, must stay last
          extensionMode: 'exact',
          supportedVersions: [772],
          alpnProtocols: ['h2'],
          sniMode: 'domain',
        ),
      );
      final report = checkFingerprintEnforcement(
        profile: profile,
        stack: Ja4Stack.nss,
      );
      final fixed = applyEnforcementAutoFixes(profile, report);
      expect(fixed.inputs.extensions, contains(43));
      expect(fixed.inputs.extensions.last, 41);
    });

    test('adds missing key_share groups to supported_groups', () {
      final profile = _profile(
        const TlsClientHelloInputs(
          supportedGroups: [29],
          keyShareGroups: [23],
          extensions: [10, 51],
          extensionMode: 'exact',
        ),
      );
      final report = checkFingerprintEnforcement(
        profile: profile,
        stack: Ja4Stack.nss,
      );
      final fixed = applyEnforcementAutoFixes(profile, report);
      expect(fixed.inputs.supportedGroups, containsAll(<int>[29, 23]));
    });

    test('swaps inverted tls bounds', () {
      final profile = _profile(
        const TlsClientHelloInputs(tlsMinVersion: '1.3', tlsMaxVersion: '1.2'),
      );
      final report = checkFingerprintEnforcement(
        profile: profile,
        stack: Ja4Stack.nss,
      );
      final fixed = applyEnforcementAutoFixes(profile, report);
      expect(fixed.inputs.tlsMinVersion, '1.2');
      expect(fixed.inputs.tlsMaxVersion, '1.3');
    });

    test('a fixed profile passes the check it failed', () {
      final profile = _profile(
        const TlsClientHelloInputs(
          cipherSuites: [4865, 4866],
          extensions: [0, 16],
          alpnProtocols: ['h2'],
          sniMode: 'domain',
          supportedVersions: [772],
          supportedGroups: [29],
          keyShareGroups: [23],
          signatureAlgorithms: [1027],
        ),
      );
      final before = checkFingerprintEnforcement(
        profile: profile,
        stack: Ja4Stack.nss,
      );
      expect(before.hasBlockers, isTrue);

      final fixed = applyEnforcementAutoFixes(profile, before);
      final after = checkFingerprintEnforcement(
        profile: fixed,
        stack: Ja4Stack.nss,
      );
      expect(
        after.hasBlockers,
        isFalse,
        reason: after.blockers.map((i) => i.title).join(' | '),
      );
    });

    test('auto-fixing changes the intended JA4 — that is the point', () {
      final profile = _profile(
        const TlsClientHelloInputs(
          extensions: [0, 16],
          extensionMode: 'exact',
          supportedVersions: [772],
          alpnProtocols: ['h2'],
          sniMode: 'domain',
        ),
      );
      final report = checkFingerprintEnforcement(
        profile: profile,
        stack: Ja4Stack.nss,
      );
      final fixed = applyEnforcementAutoFixes(profile, report);
      expect(intendedJa4For(fixed), isNot(intendedJa4For(profile)));
    });
  });
}
