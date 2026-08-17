import 'package:flutter/foundation.dart';

import '../models/fingerprint_profile.dart';
import 'fingerprint_enforcement.dart';
import 'ja4_hash_preview.dart';

/// One field of the profile that did not survive the trip to the wire.
@immutable
class DumpDeviation {
  const DumpDeviation({
    required this.field,
    required this.requested,
    required this.actual,
    required this.reason,
  });

  /// Config key, e.g. `cipher_suites`.
  final String field;

  /// What the launcher asked for.
  final String requested;

  /// What the library reports it actually serialized.
  final String actual;

  /// Why they differ, in terms of the stack's own diagnostics.
  final String reason;
}

/// Why the whole verification could not be performed.
enum DumpVerdictStatus {
  /// No dump file appeared after the launch.
  noDump,

  /// A dump exists but the library reports the config was never applied.
  configIgnored,

  /// The dump was parsed and compared.
  verified,
}

/// Result of comparing the selected profile against what the patched library
/// says it actually put on the wire.
@immutable
class DumpVerdict {
  const DumpVerdict({
    required this.status,
    required this.deviations,
    required this.maskReasons,
    this.intendedJa4,
    this.effectiveJa4,
    this.mismatchMask = 0,
    this.applyOk = false,
  });

  final DumpVerdictStatus status;

  /// Field-level differences between `requested_*` and `final_*`.
  final List<DumpDeviation> deviations;

  /// Human-readable decoding of every set `mismatch_mask` bit.
  final List<String> maskReasons;

  /// JA4 the profile describes.
  final String? intendedJa4;

  /// JA4 recomputed from the library's `final_*` readback of the emitted
  /// ClientHello.
  final String? effectiveJa4;

  final int mismatchMask;
  final bool applyOk;

  /// True only when the fingerprint that went out is the one that was picked.
  bool get matches =>
      status == DumpVerdictStatus.verified &&
      deviations.isEmpty &&
      mismatchMask == 0 &&
      intendedJa4 != null &&
      intendedJa4 == effectiveJa4;

  /// True when the JA4 hashes agree even though something else drifted —
  /// good enough for JA4-based measurement, not for byte-level claims.
  bool get ja4Matches =>
      intendedJa4 != null &&
      effectiveJa4 != null &&
      intendedJa4 == effectiveJa4;

  /// Headline for the UI.
  String get headline => switch (status) {
    DumpVerdictStatus.noDump =>
      'Nicht verifizierbar — kein Diagnose-Dump geschrieben',
    DumpVerdictStatus.configIgnored =>
      'Fingerprint NICHT angewendet — die Anwendung hat ihren eigenen gesendet',
    DumpVerdictStatus.verified when matches =>
      'Fingerprint bestätigt — gesendet wie ausgewählt',
    DumpVerdictStatus.verified when ja4Matches =>
      'JA4 stimmt, aber der ClientHello weicht ab',
    DumpVerdictStatus.verified => 'Abweichender Fingerprint gesendet',
  };
}

/// Compares a selected profile against the diagnostic dump the patched TLS
/// stacks write for every ClientHello.
///
/// This is the only place in the app that answers the question that matters:
/// did the fingerprint I picked actually go out? It does not trust `apply_ok`
/// alone — BoringSSL, NSS and OpenSSL re-parse their own serialized
/// ClientHello into the `final_*` keys, so recomputing the JA4 from those
/// values and comparing it against the profile is an independent check that
/// survives a config the library quietly ignored.
class Ja4DumpVerifier {
  const Ja4DumpVerifier();

  /// Fields compared pairwise between `requested_*` and `final_*`.
  static const _comparedFields = <String, String>{
    'cipher_suites': 'Cipher-Suites',
    'alpn': 'ALPN',
    'signature_algorithms': 'Signature Algorithms',
    'extension_order': 'Extension-Reihenfolge',
    'supported_versions': 'supported_versions',
    'supported_groups': 'supported_groups',
    'key_share_groups': 'key_share_groups',
    'psk_key_exchange_modes': 'psk_key_exchange_modes',
  };

  /// Bit meanings per docs/ja4-diagnostic-schema.md.
  static const _maskBits = <int, String>{
    0x0001: 'parse_error — die Config-Datei konnte nicht gelesen werden.',
    0x0002:
        'apply_runtime_mismatch — ein Override ließ sich nicht auf den '
        'Library-Zustand anwenden.',
    0x0004:
        'key_share_mismatch — eine key_share-Gruppe ist nicht unterstützt oder '
        'nicht reproduzierbar.',
    0x0008:
        'supported_versions_mismatch — eine angeforderte TLS-Version wird nicht '
        'unterstützt.',
    0x0010: 'unknown_config_key — der Parser sah einen unbekannten Config-Key.',
    0x0020:
        'invalid_config_combination — die Config ist semantisch widersprüchlich.',
    0x0040:
        'missing_requested_extension — eine im exact-Modus geforderte Extension '
        'fehlt im gesendeten ClientHello.',
    0x0080: 'cipher_suites_mismatch — gesendete Cipher weichen ab.',
    0x0100: 'alpn_mismatch — gesendetes ALPN weicht ab.',
    0x0200: 'signature_algorithms_mismatch — gesendete Sigalgs weichen ab.',
    0x0400:
        'extension_order_mismatch — gesendete Extension-Reihenfolge weicht ab.',
    0x0800: 'supported_groups_mismatch — gesendete Gruppen weichen ab.',
    0x1000: 'psk_key_exchange_modes_mismatch — gesendete PSK-Modi weichen ab.',
  };

  /// Verdict for a launch that produced no dump at all.
  DumpVerdict noDump() => const DumpVerdict(
    status: DumpVerdictStatus.noDump,
    deviations: [],
    maskReasons: [
      'Die gestartete Anwendung hat keinen Diagnose-Dump geschrieben. Das '
          'passiert, wenn das Binary nicht gegen die gepatchte TLS-Library '
          'gelinkt ist — dann ignoriert es die JA4-Umgebungsvariablen '
          'vollständig und sendet seinen nativen Fingerprint.',
    ],
  );

  /// Parses [dumpContent] and compares it against [profile].
  DumpVerdict verify({
    required String dumpContent,
    required FingerprintProfile profile,
  }) {
    final dump = _parse(dumpContent);
    if (dump.isEmpty) return noDump();

    final intended = intendedJa4For(profile);
    final mask = int.tryParse(dump['mismatch_mask'] ?? '') ?? 0;
    final applyOk = dump['apply_ok'] == '1';
    final active = dump['active'] == '1';

    final maskReasons = <String>[
      for (final entry in _maskBits.entries)
        if (mask & entry.key != 0) entry.value,
    ];

    if (!active) {
      return DumpVerdict(
        status: DumpVerdictStatus.configIgnored,
        deviations: const [],
        maskReasons: [
          'Der Dump meldet active=0: die Library hat die Config verworfen und '
              'ihren eigenen ClientHello gesendet. Typische Ursachen sind eine '
              'nicht lesbare Config-Datei, eine ungültige Zeile oder eine nicht '
              'unterstützte Gruppe — die Patches verwerfen in diesen Fällen die '
              'gesamte Config und melden trotzdem apply_ok=1.',
          ...maskReasons,
        ],
        intendedJa4: intended,
        mismatchMask: mask,
        applyOk: applyOk,
      );
    }

    final greaseValue = int.tryParse(dump['grease_value'] ?? '');
    final greaseOn = dump['enable_grease'] == '1';

    final deviations = <DumpDeviation>[];
    for (final entry in _comparedFields.entries) {
      final requested = dump['requested_${entry.key}'] ?? '';
      final actual = dump['final_${entry.key}'] ?? '';
      if (requested.isEmpty) continue; // Nothing was requested for this field.
      if (requested == actual) continue;
      if (greaseOn && _stripGrease(actual, greaseValue) == requested) {
        continue; // Library-injected GREASE only; JA4 filters it anyway.
      }
      deviations.add(
        DumpDeviation(
          field: entry.key,
          requested: requested,
          actual: actual,
          reason: _reasonForField(entry.value, mask),
        ),
      );
    }

    return DumpVerdict(
      status: DumpVerdictStatus.verified,
      deviations: deviations,
      maskReasons: maskReasons,
      intendedJa4: intended,
      effectiveJa4: _ja4FromDump(dump),
      mismatchMask: mask,
      applyOk: applyOk,
    );
  }

  /// Recomputes the JA4 from the library's readback of the emitted
  /// ClientHello.
  String? _ja4FromDump(Map<String, String> dump) {
    final ciphers = _ints(dump['final_cipher_suites']);
    final extensions = _ints(dump['final_extension_order']);
    if (ciphers.isEmpty && extensions.isEmpty) return null;

    return const Ja4HashPreview().compute(
      tlsMaxVersion: _tlsVersionLabel(dump['effective_tls_max']),
      supportedVersions: _ints(dump['final_supported_versions']),
      sniMode: dump['sni_mode'] ?? 'present',
      cipherSuites: ciphers,
      extensions: extensions,
      signatureAlgorithms: _ints(dump['final_signature_algorithms']),
      alpnProtocols: _strings(dump['final_alpn']),
    );
  }

  String _reasonForField(String label, int mask) {
    final bits = <String>[
      for (final entry in _maskBits.entries)
        if (mask & entry.key != 0) entry.value,
    ];
    if (bits.isEmpty) {
      return '$label wurde angefordert, aber die Library hat einen anderen Wert '
          'serialisiert, ohne dafür ein mismatch-Bit zu setzen. Das deutet auf '
          'einen Pfad hin, den die Diagnose nicht abdeckt — hier lohnt ein PCAP.';
    }
    return '$label weicht ab. Gemeldet: ${bits.join(" ")}';
  }

  Map<String, String> _parse(String content) {
    final result = <String, String>{};
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final index = line.indexOf('=');
      if (index <= 0) continue;
      result[line.substring(0, index)] = line.substring(index + 1).trim();
    }
    return result;
  }

  /// Removes one leading GREASE entry matching [greaseValue] and any trailing
  /// GREASE entries, mirroring what scripts/ja4_verify.sh tolerates.
  String _stripGrease(String csv, int? greaseValue) {
    final parts = csv.split(',').where((p) => p.isNotEmpty).toList();
    if (parts.isNotEmpty && greaseValue != null) {
      if (int.tryParse(parts.first) == greaseValue) parts.removeAt(0);
    }
    while (parts.isNotEmpty && _isGreaseValue(parts.last)) {
      parts.removeLast();
    }
    return parts.join(',');
  }

  static bool _isGreaseValue(String raw) {
    final value = int.tryParse(raw);
    if (value == null) return false;
    return (value & 0x0f0f) == 0x0a0a && (value >> 8) == (value & 0xff);
  }

  static List<int> _ints(String? csv) {
    if (csv == null || csv.isEmpty) return const [];
    return csv
        .split(',')
        .map((p) => int.tryParse(p.trim()))
        .whereType<int>()
        .toList();
  }

  static List<String> _strings(String? csv) {
    if (csv == null || csv.isEmpty) return const [];
    return csv
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
  }

  static String _tlsVersionLabel(String? raw) => switch (raw) {
    '772' => '1.3',
    '771' => '1.2',
    '770' => '1.1',
    '769' => '1.0',
    _ => '1.3',
  };
}
