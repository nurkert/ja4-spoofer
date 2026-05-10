import '../models/fingerprint_profile.dart';

/// Converts a [FingerprintProfile] to CLI args for run_*_with_ja4.sh scripts.
List<String> profileToArgs(FingerprintProfile profile) {
  final inputs = profile.inputs;
  final cipherMode = _effectiveCipherMode(profile);
  final extensionMode = _effectiveExtensionMode(profile);
  final enableGrease = _effectiveEnableGrease(profile);
  final enableChXtnPermutation = _effectiveEnableChXtnPermutation(profile);
  return [
    if (inputs.tlsMinVersion.isNotEmpty) ...['--tls-min', inputs.tlsMinVersion],
    if (inputs.tlsMaxVersion.isNotEmpty) ...['--tls-max', inputs.tlsMaxVersion],
    if (inputs.cipherSuites.isNotEmpty) ...[
      '--cipher-suites',
      inputs.cipherSuites.join(','),
    ],
    if (cipherMode != null) ...['--cipher-mode', cipherMode],
    if (inputs.alpnProtocols.isNotEmpty) ...[
      '--alpn',
      inputs.alpnProtocols.join(','),
    ],
    if (inputs.signatureAlgorithms.isNotEmpty) ...[
      '--signature-algorithms',
      inputs.signatureAlgorithms.join(','),
    ],
    if (inputs.supportedVersions.isNotEmpty) ...[
      '--supported-versions',
      inputs.supportedVersions.join(','),
    ],
    if (inputs.supportedGroups.isNotEmpty) ...[
      '--supported-groups',
      inputs.supportedGroups.join(','),
    ],
    if (inputs.keyShareGroups.isNotEmpty) ...[
      '--key-share-groups',
      inputs.keyShareGroups.join(','),
    ],
    if (inputs.pskKeyExchangeModes.isNotEmpty) ...[
      '--psk-key-exchange-modes',
      inputs.pskKeyExchangeModes.join(','),
    ],
    if (inputs.extensions.isNotEmpty) ...[
      '--extension-order',
      inputs.extensions.join(','),
    ],
    if (extensionMode != null) ...['--extension-mode', extensionMode],
    if (inputs.sniMode.isNotEmpty) ...['--sni-mode', inputs.sniMode],
    '--enable-grease',
    enableGrease ? '1' : '0',
    '--enable-ch-xtn-permutation',
    enableChXtnPermutation ? '1' : '0',
  ];
}

String? _effectiveCipherMode(FingerprintProfile profile) {
  final explicit = profile.inputs.cipherMode;
  if (explicit != null && explicit.isNotEmpty) return explicit;

  final isCapturedReplay = profile.metadata.source == 'captured';
  if (isCapturedReplay && profile.inputs.cipherSuites.isNotEmpty) {
    return 'exact';
  }
  return null;
}

String? _effectiveExtensionMode(FingerprintProfile profile) {
  final explicit = profile.inputs.extensionMode;
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final isCapturedReplay = profile.metadata.source == 'captured';
  if (isCapturedReplay && profile.inputs.extensions.isNotEmpty) {
    return 'exact';
  }
  return null;
}

bool _effectiveEnableGrease(FingerprintProfile profile) {
  // JA4 is GREASE-stable by spec — the hasher strips RFC 8701 GREASE values
  // from ciphers/extensions/sigalgs/supported-versions before SHA256, so the
  // real tool always produces the same JA4 across connections. The capture
  // pipeline already filters GREASE out of the persisted lists. Re-injecting
  // GREASE on replay therefore (a) yields no JA4 benefit and (b) risks JA4_c
  // divergence on JA4 implementations that don't strip sigalg-GREASE
  // consistently (BoringSSL injects 0x?A?A into the sigalg list when GREASE
  // is on; many JA4 hashers leak that into the hash). For 1:1 imitation of
  // the captured tool's server-visible JA4, suppress GREASE on captured
  // replays. Manually-configured profiles still honor the explicit flag.
  if (profile.metadata.source == 'captured') {
    return false;
  }
  return profile.inputs.enableGrease;
}

bool _effectiveEnableChXtnPermutation(FingerprintProfile profile) {
  // Captured profiles encode a concrete extension order (replayed via
  // extension_mode='exact'). Re-permuting on top would shuffle the replayed
  // order and break JA4_c. The capture pipeline already records
  // enableChXtnPermutation=false, but a user could flip it manually in the
  // configurator on a captured profile. Coerce to false in that case so 1:1
  // imitation never depends on UI state. Manually-configured profiles still
  // honor the explicit flag.
  if (profile.metadata.source == 'captured') {
    return false;
  }
  return profile.inputs.enableChXtnPermutation;
}
