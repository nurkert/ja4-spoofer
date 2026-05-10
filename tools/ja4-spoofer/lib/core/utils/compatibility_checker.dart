import '../models/app_descriptor.dart';
import '../models/fingerprint_profile.dart';
import '../models/registry_bundle.dart';
import '../models/registry_item.dart';

enum CompatibilityLevel { ok, warning, error }

class CompatibilityIssue {
  const CompatibilityIssue({
    required this.code,
    required this.level,
    required this.message,
  });

  final String code;
  final CompatibilityLevel level;
  final String message;
}

class CompatibilityResult {
  const CompatibilityResult({required this.appName, required this.issues});

  final String appName;
  final List<CompatibilityIssue> issues;

  bool get isCompatible =>
      issues.every((i) => i.level != CompatibilityLevel.error);
}

/// Checks whether a [FingerprintProfile] is compatible with an app's
/// [AppTlsDefaults] — verifies that all cipher suites, extensions, etc.
/// in the profile are supported by the target SSL library.
class CompatibilityChecker {
  const CompatibilityChecker();

  /// Pass a [registry] to decorate unsupported-cipher / extension /
  /// signature-algorithm messages with their IANA names. When `null`,
  /// only hex IDs are emitted.
  CompatibilityResult check(
    FingerprintProfile profile,
    AppDescriptor app, {
    RegistryBundle? registry,
  }) {
    final issues = <CompatibilityIssue>[];
    final defaults = app.tlsDefaults;
    final inputs = profile.inputs;

    if (defaults.isEmpty) {
      issues.add(
        CompatibilityIssue(
          code: 'NO_DEFAULTS',
          level: CompatibilityLevel.warning,
          message:
              '${app.metadata.name} has no TLS defaults defined — cannot verify compatibility.',
        ),
      );
      return CompatibilityResult(appName: app.metadata.name, issues: issues);
    }

    // Cipher suite check.
    // Patched JA4 libs replay arbitrary cipher lists, so cipher IDs missing
    // from the descriptor's tls_defaults are advisory — they only become a
    // hard error when there's zero overlap (handshake would surely fail).
    if (inputs.cipherSuites.isNotEmpty && defaults.cipherSuites.isNotEmpty) {
      final supported = defaults.cipherSuites.toSet();
      final unsupported = inputs.cipherSuites
          .where((c) => !supported.contains(c))
          .toList();
      if (unsupported.isNotEmpty) {
        final formatted = unsupported
            .map((c) => _formatId(c, registry?.cipherSuites))
            .join(', ');
        issues.add(
          CompatibilityIssue(
            code: 'UNSUPPORTED_CIPHERS',
            level: CompatibilityLevel.warning,
            message:
                '${unsupported.length} cipher suite(s) outside ${app.metadata.name} defaults: $formatted',
          ),
        );
      }
      final overlap = inputs.cipherSuites.toSet().intersection(supported);
      if (overlap.isEmpty) {
        issues.add(
          const CompatibilityIssue(
            code: 'NO_CIPHER_OVERLAP',
            level: CompatibilityLevel.error,
            message:
                'No cipher suites in this profile are supported — connection would fail.',
          ),
        );
      }
    }

    // Extension check
    if (inputs.extensions.isNotEmpty && defaults.extensions.isNotEmpty) {
      final supported = defaults.extensions.toSet();
      final unsupported = inputs.extensions
          .where((e) => !supported.contains(e))
          .toList();
      if (unsupported.isNotEmpty) {
        final formatted = unsupported
            .map((e) => _formatId(e, registry?.extensions))
            .join(', ');
        issues.add(
          CompatibilityIssue(
            code: 'UNSUPPORTED_EXTENSIONS',
            level: CompatibilityLevel.warning,
            message:
                '${unsupported.length} extension(s) not supported by ${app.metadata.name}: $formatted',
          ),
        );
      }
    }

    // Signature algorithm check
    if (inputs.signatureAlgorithms.isNotEmpty &&
        defaults.signatureAlgorithms.isNotEmpty) {
      final supported = defaults.signatureAlgorithms.toSet();
      final unsupported = inputs.signatureAlgorithms
          .where((s) => !supported.contains(s))
          .toList();
      if (unsupported.isNotEmpty) {
        final formatted = unsupported
            .map((s) => _formatId(s, registry?.signatureSchemes))
            .join(', ');
        issues.add(
          CompatibilityIssue(
            code: 'UNSUPPORTED_SIGALGS',
            level: CompatibilityLevel.warning,
            message:
                '${unsupported.length} signature algorithm(s) not supported by ${app.metadata.name}: $formatted',
          ),
        );
      }
    }

    // ALPN check
    if (inputs.alpnProtocols.isNotEmpty && defaults.alpnProtocols.isNotEmpty) {
      final supported = defaults.alpnProtocols.toSet();
      final unsupported = inputs.alpnProtocols
          .where((a) => !supported.contains(a))
          .toList();
      if (unsupported.isNotEmpty) {
        issues.add(
          CompatibilityIssue(
            code: 'UNSUPPORTED_ALPN',
            level: CompatibilityLevel.warning,
            message:
                'ALPN protocol(s) not supported by ${app.metadata.name}: ${unsupported.join(", ")}',
          ),
        );
      }
    }

    // TLS version check
    if (defaults.tlsVersions.isNotEmpty) {
      final supported = defaults.tlsVersions.toSet();
      if (!supported.contains(inputs.tlsMaxVersion)) {
        issues.add(
          CompatibilityIssue(
            code: 'UNSUPPORTED_TLS_VERSION',
            level: CompatibilityLevel.error,
            message:
                'TLS ${inputs.tlsMaxVersion} not supported by ${app.metadata.name}.',
          ),
        );
      }
    }

    return CompatibilityResult(appName: app.metadata.name, issues: issues);
  }

  String _formatId(int id, List<RegistryItem>? items) {
    final hex = '0x${id.toRadixString(16).padLeft(4, '0')}';
    if (items == null) return hex;
    for (final item in items) {
      if (item.id == id) return '$hex ${item.name}';
    }
    return hex;
  }
}
