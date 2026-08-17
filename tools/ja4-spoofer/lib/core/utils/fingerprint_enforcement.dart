import 'package:flutter/foundation.dart';

import '../models/fingerprint_profile.dart';
import '../models/ja4_stack.dart';
import 'ja4_hash_preview.dart';
import 'profile_args.dart';

/// TLS extension codepoints this checker reasons about by name.
class Ja4ExtensionIds {
  const Ja4ExtensionIds._();

  static const int serverName = 0x0000;
  static const int supportedGroups = 0x000a;
  static const int signatureAlgorithms = 0x000d;
  static const int alpn = 0x0010;
  static const int preSharedKey = 0x0029;
  static const int supportedVersions = 0x002b;
  static const int pskKeyExchangeModes = 0x002d;
  static const int keyShare = 0x0033;
}

/// How badly an issue breaks the "what I picked is what goes on the wire"
/// guarantee.
enum EnforcementSeverity {
  /// The emitted ClientHello is guaranteed to carry a different JA4 than the
  /// profile describes, or the config will be rejected outright. Launching
  /// without acknowledging this produces a measurement that means nothing.
  blocker,

  /// The JA4 can still match, but some part of the request is knowingly not
  /// enforceable on this stack and the wire will differ from the profile.
  warning,

  /// A deliberate, documented transformation the user should know about.
  info,
}

/// A single reason the wire will not match the selected profile.
@immutable
class EnforcementIssue {
  const EnforcementIssue({
    required this.severity,
    required this.field,
    required this.title,
    required this.deviation,
    required this.reason,
    required this.remedy,
    this.autoFixable = false,
  });

  final EnforcementSeverity severity;

  /// Config key this concerns, e.g. `extension_mode`.
  final String field;

  /// One-line summary for list rendering.
  final String title;

  /// What will actually differ on the wire.
  final String deviation;

  /// Why it differs — the mechanism, not a restatement of the symptom.
  final String reason;

  /// What the user can do about it.
  final String remedy;

  /// Whether [applyEnforcementAutoFixes] can resolve this without asking.
  final bool autoFixable;
}

/// Verdict for one profile/stack pair, produced before anything is launched.
@immutable
class EnforcementReport {
  const EnforcementReport({
    required this.issues,
    required this.intendedJa4,
    required this.stack,
  });

  final List<EnforcementIssue> issues;

  /// JA4 the profile describes — the value the user believes they selected.
  final String intendedJa4;

  /// Stack the check was run against, or null when the target is not one of
  /// the three patched libraries.
  final Ja4Stack? stack;

  List<EnforcementIssue> get blockers =>
      issues.where((i) => i.severity == EnforcementSeverity.blocker).toList();

  List<EnforcementIssue> get warnings =>
      issues.where((i) => i.severity == EnforcementSeverity.warning).toList();

  List<EnforcementIssue> get infos =>
      issues.where((i) => i.severity == EnforcementSeverity.info).toList();

  bool get hasBlockers => blockers.isNotEmpty;

  bool get hasAutoFixes => issues.any((i) => i.autoFixable);

  /// True when nothing stands between the profile and the wire that this
  /// check can see. Post-launch verification still has the final word.
  bool get isClean => issues.isEmpty;
}

/// Checks whether [profile] can actually reach the wire unchanged through
/// [stack], before a single byte is sent.
///
/// This is a static check over the config the launcher would emit. It cannot
/// see runtime reality — an unpatched binary, a rejected config file, a
/// library that filters a group at handshake time — which is what
/// `Ja4DumpVerifier` covers after the launch. The two are complements: this
/// one catches the deviations that are already decided at config time, and
/// those are the ones the GUI can still prevent.
///
/// [knownExtensionIds] should carry the IANA-registered extension codepoints
/// when available; without it the synthetic-stub check is skipped rather than
/// guessed.
EnforcementReport checkFingerprintEnforcement({
  required FingerprintProfile profile,
  required Ja4Stack? stack,
  Set<int>? knownExtensionIds,
}) {
  final inputs = profile.inputs;
  final issues = <EnforcementIssue>[];

  final cipherMode = effectiveCipherMode(profile);
  final extensionMode = effectiveExtensionMode(profile);

  // ---- Blockers: the JA4 is already decided to be different ----

  if (inputs.cipherSuites.isNotEmpty && cipherMode != 'exact') {
    issues.add(
      EnforcementIssue(
        severity: EnforcementSeverity.blocker,
        field: 'cipher_mode',
        title: 'Cipher-Liste wird nur umsortiert, nicht ersetzt',
        deviation:
            'Die Library sendet zusätzlich ihre eigenen Standard-Cipher-Suites; '
            'deine ${inputs.cipherSuites.length} Suites werden lediglich nach '
            'vorn gezogen.',
        reason:
            'Ohne cipher_mode=exact gilt der Default "reorder": '
            '"Move requested ciphers to the front, keep remaining defaults". '
            'JA4 sortiert die Cipher-Liste ohnehin — entscheidend ist die '
            'Anzahl, und die steigt durch die Library-Defaults. Damit ändern '
            'sich der Cipher-Count im Prefix und JA4_a.',
        remedy: 'cipher_mode auf "exact" setzen.',
        autoFixable: true,
      ),
    );
  }

  if (inputs.extensions.isNotEmpty && extensionMode != 'exact') {
    issues.add(
      EnforcementIssue(
        severity: EnforcementSeverity.blocker,
        field: 'extension_mode',
        title: 'Extension-Liste wird nur umsortiert, nicht ersetzt',
        deviation:
            'Die Library behält ihre eigenen Standard-Extensions bei und stellt '
            'deine ${inputs.extensions.length} Extensions nur voran.',
        reason:
            'Ohne extension_mode=exact gilt der Default "reorder": '
            '"Move requested extensions first, keep remaining defaults". Der '
            'Extension-Count im JA4-Prefix und JA4_b hängen direkt an dieser '
            'Liste, also entsteht garantiert ein anderer Fingerprint.',
        remedy: 'extension_mode auf "exact" setzen.',
        autoFixable: true,
      ),
    );
  }

  if (cipherMode == 'exact' && inputs.cipherSuites.isEmpty) {
    issues.add(
      const EnforcementIssue(
        severity: EnforcementSeverity.blocker,
        field: 'cipher_suites',
        title: 'cipher_mode=exact ohne Cipher-Liste',
        deviation: 'Die Config ist in sich widersprüchlich und wird verworfen.',
        reason:
            'Die Patches werten das als invalid_config_combination (Bit 0x0020). '
            'Je nach Stack wird die gesamte Config ignoriert — dann geht der '
            'native Fingerprint der Anwendung raus.',
        remedy: 'Cipher-Suites wählen oder cipher_mode leer lassen.',
      ),
    );
  }

  if (extensionMode == 'exact' && inputs.extensions.isEmpty) {
    issues.add(
      const EnforcementIssue(
        severity: EnforcementSeverity.blocker,
        field: 'extension_order',
        title: 'extension_mode=exact ohne Extension-Liste',
        deviation: 'Die Config ist in sich widersprüchlich und wird verworfen.',
        reason:
            'Die Patches werten das als invalid_config_combination (Bit 0x0020). '
            'Je nach Stack wird die gesamte Config ignoriert — dann geht der '
            'native Fingerprint der Anwendung raus.',
        remedy: 'Extensions wählen oder extension_mode leer lassen.',
      ),
    );
  }

  final tlsMin = _tlsVersionValue(inputs.tlsMinVersion);
  final tlsMax = _tlsVersionValue(inputs.tlsMaxVersion);
  if (tlsMin != null && tlsMax != null && tlsMin > tlsMax) {
    issues.add(
      EnforcementIssue(
        severity: EnforcementSeverity.blocker,
        field: 'tls_min',
        title: 'tls_min ist größer als tls_max',
        deviation:
            'tls_min=${inputs.tlsMinVersion} > tls_max=${inputs.tlsMaxVersion} — '
            'die Config wird verworfen.',
        reason:
            'invalid_config_combination (Bit 0x0020). Der Handshake läuft dann '
            'mit den Versionsgrenzen der Anwendung, nicht mit deinen.',
        remedy: 'Versionsgrenzen tauschen.',
        autoFixable: true,
      ),
    );
  }

  if (inputs.keyShareGroups.isNotEmpty && inputs.supportedGroups.isNotEmpty) {
    final missing = inputs.keyShareGroups
        .where((g) => !inputs.supportedGroups.contains(g))
        .toList();
    if (missing.isNotEmpty) {
      issues.add(
        EnforcementIssue(
          severity: EnforcementSeverity.blocker,
          field: 'key_share_groups',
          title: 'key_share_groups ist keine Teilmenge von supported_groups',
          deviation:
              'Gruppe(n) ${missing.join(", ")} stehen im key_share, fehlen aber '
              'in supported_groups.',
          reason:
              'RFC 8446 verlangt, dass jede key_share-Gruppe auch in '
              'supported_groups steht. Die Patches werten den Verstoß als '
              'invalid_config_combination (Bit 0x0020) und verwerfen die Config.',
          remedy: 'Die fehlenden Gruppen zu supported_groups hinzufügen.',
          autoFixable: true,
        ),
      );
    }
  }

  // ---- Warnings: JA4 kann noch passen, der Draht weicht trotzdem ab ----

  // Dependency closure. When an explicit extension list is in play but a body
  // override has no matching extension id, the patches append that id silently.
  // The append is invisible in the diagnostic dump (the "requested" side is
  // written from the same mutated struct), so this is the one deviation class
  // the post-launch check structurally cannot see. Catching it here is the
  // only chance.
  if (inputs.extensions.isNotEmpty) {
    final implied = <int, String>{
      if (inputs.signatureAlgorithms.isNotEmpty)
        Ja4ExtensionIds.signatureAlgorithms: 'signature_algorithms',
      if (inputs.supportedGroups.isNotEmpty)
        Ja4ExtensionIds.supportedGroups: 'supported_groups',
      if (inputs.keyShareGroups.isNotEmpty)
        Ja4ExtensionIds.keyShare: 'key_share',
      if (inputs.supportedVersions.isNotEmpty)
        Ja4ExtensionIds.supportedVersions: 'supported_versions',
      if (inputs.pskKeyExchangeModes.isNotEmpty)
        Ja4ExtensionIds.pskKeyExchangeModes: 'psk_key_exchange_modes',
      if (inputs.alpnProtocols.isNotEmpty) Ja4ExtensionIds.alpn: 'alpn',
      if (inputs.sniMode == 'present' || inputs.sniMode == 'domain')
        Ja4ExtensionIds.serverName: 'sni_mode',
    };
    final appended = implied.entries
        .where((e) => !inputs.extensions.contains(e.key))
        .toList();
    if (appended.isNotEmpty) {
      final names = appended
          .map(
            (e) => '0x${e.key.toRadixString(16).padLeft(4, "0")} (${e.value})',
          )
          .join(', ');
      issues.add(
        EnforcementIssue(
          severity: EnforcementSeverity.blocker,
          field: 'extension_order',
          title: 'Die Library fügt ${appended.length} Extension(s) still hinzu',
          deviation:
              'Zusätzlich zu deiner Liste landet $names auf dem Draht — der '
              'Extension-Count steigt von ${inputs.extensions.length} auf '
              '${inputs.extensions.length + appended.length}.',
          reason:
              'Du hast Werte für diese Extension-Bodies konfiguriert, ohne die '
              'zugehörige Extension-ID in extension_order aufzunehmen. Die '
              'Patches ergänzen die ID dann automatisch ("dependency closure"), '
              'damit der Body überhaupt gesendet werden kann. Der Dump meldet '
              'das NICHT als Abweichung, weil er die bereits ergänzte Liste als '
              '"requested" ausgibt — dein JA4 ändert sich trotzdem.',
          remedy:
              'Die IDs explizit in extension_order aufnehmen (vor einem '
              'eventuellen pre_shared_key), oder die Body-Overrides entfernen.',
          autoFixable: true,
        ),
      );
    }
  }

  // Stack-specific ceilings, straight from the patch docs.
  if (stack == Ja4Stack.openssl && inputs.keyShareGroups.isNotEmpty) {
    issues.add(
      const EnforcementIssue(
        severity: EnforcementSeverity.warning,
        field: 'key_share_groups',
        title: 'OpenSSL kann key_share nicht neu erzeugen',
        deviation:
            'Der key_share bleibt der von OpenSSL selbst gewählte; deine '
            'key_share_groups erreichen den Draht nicht.',
        reason:
            'Die Neuerzeugung eines EVP_PKEY pro Gruppe ist im OpenSSL-Patch '
            'nicht implementiert (docs/openssl-ja4-config.md). Der Hook setzt '
            'stattdessen Bit 0x0004 (key_share_mismatch).',
        remedy:
            'Für key_share-Treue Chromium/BoringSSL oder Firefox/NSS als Ziel '
            'wählen.',
      ),
    );
  }

  if (stack == Ja4Stack.openssl &&
      (inputs.supportedVersions.isNotEmpty ||
          inputs.supportedGroups.isNotEmpty ||
          inputs.pskKeyExchangeModes.isNotEmpty)) {
    issues.add(
      const EnforcementIssue(
        severity: EnforcementSeverity.warning,
        field: 'extension bodies',
        title: 'OpenSSL überschreibt Extension-Bodies nur längengleich',
        deviation:
            'Hat dein Override eine andere Byte-Länge als der von OpenSSL '
            'serialisierte Body, wird der Rewrite übersprungen und OpenSSLs '
            'eigener Wert bleibt stehen.',
        reason:
            'Der Patch patcht den ClientHello-Puffer in-place ohne Resize '
            '(docs/openssl-ja4-config.md, "Padding behaviour"). Bei Längen'
            'differenz setzt er Bit 0x0008 / 0x0800 / 0x1000 und lässt die '
            'ursprüngliche Serialisierung stehen.',
        remedy:
            'Nach dem Start die Verifikation unten prüfen — sie zeigt, ob der '
            'Rewrite gegriffen hat.',
      ),
    );
  }

  if (knownExtensionIds != null && inputs.extensions.isNotEmpty) {
    final unknown = inputs.extensions
        .where((e) => !knownExtensionIds.contains(e) && !_isGrease(e))
        .toList();
    if (unknown.isNotEmpty) {
      final names = unknown
          .map((e) => '0x${e.toRadixString(16).padLeft(4, "0")}')
          .join(', ');
      issues.add(
        EnforcementIssue(
          severity: EnforcementSeverity.warning,
          field: 'extension_order',
          title:
              '${unknown.length} Extension(s) werden als leerer Stub gesendet',
          deviation:
              '$names erscheinen mit korrekter ID, aber mit 0 Byte Inhalt.',
          reason:
              'Die Library hat für diese Codepoints keinen eigenen Sender. Im '
              'exact-Modus schreiben die Patches einen synthetischen Stub mit '
              'Länge 0, damit die ID an der richtigen Position im JA4 auftaucht. '
              'Der JA4 stimmt damit — der Inhalt ist aber leer, was byteweise '
              'sofort auffällt und Gegenstellen ablehnen können.',
          remedy:
              'Für reine JA4-Gleichheit unkritisch. Für Byte-Treue ein Ziel mit '
              'nativer Unterstützung wählen.',
        ),
      );
    }
  }

  // ---- Infos: bewusste, dokumentierte Transformationen ----

  if (profile.metadata.source == 'captured') {
    if (inputs.enableGrease) {
      issues.add(
        const EnforcementIssue(
          severity: EnforcementSeverity.info,
          field: 'enable_grease',
          title: 'GREASE wird für Capture-Replays abgeschaltet',
          deviation:
              'Trotz aktivierter Option geht der ClientHello ohne GREASE raus.',
          reason:
              'JA4 filtert GREASE ohnehin heraus, aber manche JA4-Implementier'
              'ungen lassen GREASE in der Sigalg-Liste durchsickern. Für 1:1-'
              'Imitation erzwingt der Launcher deshalb enable_grease=0.',
          remedy:
              'Bewusst so. Beachte: ein echter Chrome sendet GREASE — der Draht '
              'weicht hier absichtlich vom Original ab.',
        ),
      );
    }
    if (inputs.enableChXtnPermutation) {
      issues.add(
        const EnforcementIssue(
          severity: EnforcementSeverity.info,
          field: 'enable_ch_xtn_permutation',
          title: 'Extension-Permutation wird für Capture-Replays abgeschaltet',
          deviation: 'Die aufgezeichnete Reihenfolge wird 1:1 wiedergegeben.',
          reason:
              'Erneutes Permutieren würde die replayte Reihenfolge zerwürfeln. '
              'Auf JA4 hat das keinen Einfluss (JA4 sortiert), auf die Byte-'
              'Reihenfolge schon.',
          remedy: 'Bewusst so.',
        ),
      );
    }
  }

  issues.add(
    const EnforcementIssue(
      severity: EnforcementSeverity.info,
      field: 'strict',
      title: 'Start läuft im Best-Effort-Modus',
      deviation:
          'Abweichungen brechen den Handshake nicht ab, sondern landen nur im '
          'Diagnose-Dump.',
      reason:
          'strict=1 würde bei jedem nicht umsetzbaren Wert hart abbrechen — bei '
          'Capture-Replays mit exotischen Ciphern bekämst du dann gar keine '
          'Verbindung. Deshalb startet der Launcher bewusst tolerant.',
      remedy:
          'Die Verifikation nach dem Start wertet den Dump aus und meldet jede '
          'Abweichung.',
    ),
  );

  return EnforcementReport(
    issues: issues,
    intendedJa4: intendedJa4For(profile),
    stack: stack,
  );
}

/// The JA4 the profile describes — what the user believes they selected.
String intendedJa4For(FingerprintProfile profile) {
  final inputs = profile.inputs;
  return const Ja4HashPreview().compute(
    tlsMaxVersion: inputs.tlsMaxVersion,
    supportedVersions: inputs.supportedVersions,
    sniMode: inputs.sniMode,
    cipherSuites: inputs.cipherSuites,
    extensions: inputs.extensions,
    signatureAlgorithms: inputs.signatureAlgorithms,
    alpnProtocols: inputs.alpnProtocols,
  );
}

/// Applies every mechanical fix from [report] to [profile] and returns the
/// corrected profile.
///
/// These edits change the profile's JA4 on purpose: they turn an ambiguous
/// request into the exact ClientHello the stack would have produced anyway, so
/// that the value shown in the UI is the value that reaches the wire.
FingerprintProfile applyEnforcementAutoFixes(
  FingerprintProfile profile,
  EnforcementReport report,
) {
  if (!report.hasAutoFixes) return profile;
  final fixedFields = report.issues
      .where((i) => i.autoFixable)
      .map((i) => i.field)
      .toSet();
  var inputs = profile.inputs;

  if (fixedFields.contains('cipher_mode')) {
    inputs = inputs.copyWith(cipherMode: 'exact');
  }
  if (fixedFields.contains('extension_mode')) {
    inputs = inputs.copyWith(extensionMode: 'exact');
  }
  if (fixedFields.contains('tls_min')) {
    inputs = inputs.copyWith(
      tlsMinVersion: profile.inputs.tlsMaxVersion,
      tlsMaxVersion: profile.inputs.tlsMinVersion,
    );
  }
  if (fixedFields.contains('key_share_groups')) {
    final groups = List<int>.from(inputs.supportedGroups);
    for (final g in inputs.keyShareGroups) {
      if (!groups.contains(g)) groups.add(g);
    }
    inputs = inputs.copyWith(supportedGroups: groups);
  }
  if (fixedFields.contains('extension_order')) {
    inputs = inputs.copyWith(extensions: _withImpliedExtensions(inputs));
  }

  return FingerprintProfile(
    profileId: profile.profileId,
    metadata: profile.metadata,
    inputs: inputs,
    isBuiltIn: profile.isBuiltIn,
  );
}

/// Inserts every extension id implied by a configured body override, keeping
/// `pre_shared_key` last as RFC 8446 §4.2.11 requires.
List<int> _withImpliedExtensions(TlsClientHelloInputs inputs) {
  final implied = <int>[
    if (inputs.signatureAlgorithms.isNotEmpty)
      Ja4ExtensionIds.signatureAlgorithms,
    if (inputs.supportedGroups.isNotEmpty) Ja4ExtensionIds.supportedGroups,
    if (inputs.keyShareGroups.isNotEmpty) Ja4ExtensionIds.keyShare,
    if (inputs.supportedVersions.isNotEmpty) Ja4ExtensionIds.supportedVersions,
    if (inputs.pskKeyExchangeModes.isNotEmpty)
      Ja4ExtensionIds.pskKeyExchangeModes,
    if (inputs.alpnProtocols.isNotEmpty) Ja4ExtensionIds.alpn,
    if (inputs.sniMode == 'present' || inputs.sniMode == 'domain')
      Ja4ExtensionIds.serverName,
  ];

  final result = List<int>.from(inputs.extensions);
  for (final id in implied) {
    if (result.contains(id)) continue;
    final pskIndex = result.indexOf(Ja4ExtensionIds.preSharedKey);
    if (pskIndex >= 0) {
      result.insert(pskIndex, id);
    } else {
      result.add(id);
    }
  }
  return result;
}

int? _tlsVersionValue(String version) => switch (version) {
  '1.0' => 0x0301,
  '1.1' => 0x0302,
  '1.2' => 0x0303,
  '1.3' => 0x0304,
  _ => int.tryParse(version),
};

bool _isGrease(int value) =>
    (value & 0x0f0f) == 0x0a0a && (value >> 8) == (value & 0xff);
