import 'dart:math';

import '../models/app_descriptor.dart';
import '../models/fingerprint_profile.dart';
import '../models/registry_item.dart';
import '../services/iana_registry_service.dart';

/// Randomization helpers used by the Configurator's "Randomize All" /
/// "Smart Random" buttons. The Quick-Launch tab currently has no randomizer
/// — it's being redesigned from scratch.

// ---------------------------------------------------------------------------
// Padding configuration
// ---------------------------------------------------------------------------

/// Controls which TLS components receive padding (fake/unassigned IDs that
/// change the JA4 fingerprint without affecting TLS negotiation).
class RandomizePaddingConfig {
  const RandomizePaddingConfig({
    this.ciphersEnabled = false,
    this.extensionsEnabled = false,
    this.signatureAlgorithmsEnabled = false,
    this.cipherPaddingCount,
    this.extensionPaddingCount,
    this.sigAlgPaddingCount,
  });

  /// No padding at all.
  const RandomizePaddingConfig.none()
    : ciphersEnabled = false,
      extensionsEnabled = false,
      signatureAlgorithmsEnabled = false,
      cipherPaddingCount = null,
      extensionPaddingCount = null,
      sigAlgPaddingCount = null;

  /// Padding only for cipher suites (safest per RFC 8446).
  const RandomizePaddingConfig.ciphersOnly({this.cipherPaddingCount})
    : ciphersEnabled = true,
      extensionsEnabled = false,
      signatureAlgorithmsEnabled = false,
      extensionPaddingCount = null,
      sigAlgPaddingCount = null;

  /// Padding for all components.
  const RandomizePaddingConfig.all({
    this.cipherPaddingCount,
    this.extensionPaddingCount,
    this.sigAlgPaddingCount,
  }) : ciphersEnabled = true,
       extensionsEnabled = true,
       signatureAlgorithmsEnabled = true;

  final bool ciphersEnabled;
  final bool extensionsEnabled;
  final bool signatureAlgorithmsEnabled;

  /// Number of padding ciphers to append. `null` means random (2–6).
  final int? cipherPaddingCount;

  /// Number of padding extensions to append. `null` means random (1–3).
  final int? extensionPaddingCount;

  /// Number of padding signature algorithms to append. `null` means random (1–3).
  final int? sigAlgPaddingCount;

  RandomizePaddingConfig copyWith({
    bool? ciphersEnabled,
    bool? extensionsEnabled,
    bool? signatureAlgorithmsEnabled,
    int? cipherPaddingCount,
    int? extensionPaddingCount,
    int? sigAlgPaddingCount,
  }) {
    return RandomizePaddingConfig(
      ciphersEnabled: ciphersEnabled ?? this.ciphersEnabled,
      extensionsEnabled: extensionsEnabled ?? this.extensionsEnabled,
      signatureAlgorithmsEnabled:
          signatureAlgorithmsEnabled ?? this.signatureAlgorithmsEnabled,
      cipherPaddingCount: cipherPaddingCount ?? this.cipherPaddingCount,
      extensionPaddingCount:
          extensionPaddingCount ?? this.extensionPaddingCount,
      sigAlgPaddingCount: sigAlgPaddingCount ?? this.sigAlgPaddingCount,
    );
  }
}

// ---------------------------------------------------------------------------
// Public randomization API (non-smart / full random)
// ---------------------------------------------------------------------------

/// Returns a randomized set of TLS version choices (min, max).
/// Returns a record `(tlsMin, tlsMax)` uniformly drawn from the 3 valid cases.
/// (1.2,1.2), (1.2,1.3), (1.3,1.3) — never (1.3,1.2).
({String tlsMin, String tlsMax}) randomizeTlsVersions(Random random) {
  const cases = <({String tlsMin, String tlsMax})>[
    (tlsMin: '1.2', tlsMax: '1.2'),
    (tlsMin: '1.2', tlsMax: '1.3'),
    (tlsMin: '1.3', tlsMax: '1.3'),
  ];
  return cases[random.nextInt(cases.length)];
}

/// Returns a randomized selection of cipher suite IDs.
List<int> randomizeCiphers(List<RegistryItem> registry, Random random) {
  final allIds = registry.map((e) => e.id).toList();
  final chosen = <int>{
    ..._sampleAndShuffle<int>(allIds, 6 + random.nextInt(15), random),
  };
  chosen.addAll([4865, 4866, 4867]);
  return _sampleAndShuffle<int>(chosen.toList(), chosen.length, random);
}

/// Returns a randomized selection of signature algorithm IDs.
List<int> randomizeSignatures(List<RegistryItem> registry, Random random) {
  final allIds = registry.map((e) => e.id).toList();
  final chosen = <int>{
    ..._sampleAndShuffle<int>(allIds, 4 + random.nextInt(8), random),
  };
  chosen.addAll([2052, 2053, 2054, 1027, 1283]);
  return _sampleAndShuffle<int>(
    chosen.toList(),
    min(chosen.length, 14),
    random,
  );
}

/// Returns a randomized selection of extension IDs.
List<int> randomizeExtensions(List<RegistryItem> registry, Random random) {
  const baseExt = <int>{0, 10, 11, 13, 16, 23, 35, 43, 45, 51, 65281};
  const optionalExt = [5, 18, 28, 34];
  final chosen = <int>{...baseExt};
  chosen.addAll(
    _sampleAndShuffle<int>(
      optionalExt,
      random.nextInt(optionalExt.length + 1),
      random,
    ),
  );
  final allIds = registry.map((e) => e.id).toList();
  chosen.addAll(_sampleAndShuffle<int>(allIds, random.nextInt(6), random));
  return _sampleAndShuffle<int>(chosen.toList(), chosen.length, random);
}

/// Returns a randomized ALPN list from the standard pool.
List<String> randomizeAlpn(Random random) {
  const pool = ['h2', 'http/1.1'];
  return _sampleAndShuffle<String>(
    pool,
    1 + random.nextInt(pool.length),
    random,
  );
}

/// Returns a randomized profile directory path suffix.
String randomProfileDirSuffix(Random random, {int bytes = 8}) {
  final b = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    b.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}

/// Returns defaults from the IANA fallback bundle.
List<RegistryItem> get fallbackCipherRegistry =>
    List.of(IanaRegistryService.fallbackBundle.cipherSuites);

List<RegistryItem> get fallbackExtensionRegistry =>
    List.of(IanaRegistryService.fallbackBundle.extensions);

List<RegistryItem> get fallbackSignatureRegistry =>
    List.of(IanaRegistryService.fallbackBundle.signatureSchemes);

// ---------- Smart randomization: curated SSL-library-specific lists ----------

// Cipher IDs known-safe for NSS (Firefox)
const _nssSafeCiphers = <int>[
  4865, 4866, 4867, // TLS 1.3 mandatory
  49195, 49196, // ECDHE-ECDSA-AES128/256-GCM
  49199, 49200, // ECDHE-RSA-AES128/256-GCM
  52392, 52393, // ECDHE-*-CHACHA20
  49171, 49172, // ECDHE-RSA-AES128/256-SHA (legacy)
];

// Cipher IDs known-safe for BoringSSL (Chromium)
const _boringsslSafeCiphers = <int>[
  4865, 4866, 4867, // TLS 1.3 mandatory
  49195, 49199, 49196, 49200,
  52393, 52392,
  156, 157, // RSA-AES128/256-GCM (legacy fallback)
];

// Signature algorithm IDs known-safe for both NSS and BoringSSL
const _safeSignatures = <int>[
  1027, 1283, 1539, // ECDSA (SHA-256, SHA-384, SHA-512)
  2052, 2053, 2054, // RSA-PSS (SHA-256, SHA-384, SHA-512)
  1025, 1281, 1537, // RSA-PKCS1 (SHA-256, SHA-384, SHA-512)
  515, 513, // legacy SHA-1
];

// Extension IDs known-safe for both NSS and BoringSSL
const _safeExtensions = <int>[
  0,
  5,
  10,
  11,
  13,
  16,
  17513,
  18,
  21,
  22,
  23,
  27,
  28,
  34,
  35,
  41,
  43,
  45,
  51,
  65281,
];

// ---------- Padding pools (unassigned IANA IDs, safe to advertise) ----------

/// Unassigned cipher suite IDs — servers MUST ignore unknown ciphers per
/// RFC 8446 §4.1.2, so these change the JA4 hash without affecting negotiation.
const _paddingCipherPool = <int>[
  0x00C6,
  0x00C7,
  0x00C8,
  0x00C9,
  0x00CA,
  0x00CB,
  0x00D0,
  0x00D1,
  0x00D2,
  0x00D3,
  0x00D4,
  0x00D5,
  0xC0A0,
  0xC0A1,
  0xC0A2,
  0xC0A3,
  0xC0A4,
  0xC0A5,
  0xC0B0,
  0xC0B1,
  0xC0B2,
  0xC0B3,
  0xC0B4,
  0xC0B5,
];

/// Unassigned extension IDs — more risky than ciphers, some servers may reject.
const _paddingExtensionPool = <int>[
  0xFF01,
  0xFF02,
  0xFF03,
  0xFF04,
  0xFF05,
  0xFF10,
  0xFF11,
  0xFF12,
  0xFF13,
  0xFF14,
];

/// Unassigned signature algorithm IDs.
const _paddingSigAlgPool = <int>[
  0x0A0A,
  0x0B0B,
  0x0C0C,
  0x0D0D,
  0x0E0E,
  0x0F0F,
  0x1010,
  0x1111,
  0x1212,
  0x1313,
];

// ---------- Smart randomization with priority ordering + padding ----------

/// Smart randomization constrained to [profileFormat]-specific safe lists.
///
/// When [tlsDefaults] is provided, ciphers/extensions/signatures that overlap
/// with the SSL library's actual support are placed first (highest priority),
/// ensuring the server preferentially negotiates a cipher the library supports.
///
/// When [paddingConfig] enables padding, fake/unassigned IDs are appended at
/// the end to vary the JA4 fingerprint without affecting TLS negotiation.
TlsClientHelloInputs smartRandomizeInputs(
  String profileFormat,
  Random rng, {
  AppTlsDefaults? tlsDefaults,
  RandomizePaddingConfig paddingConfig = const RandomizePaddingConfig.none(),
}) {
  final ciphers = smartRandomizeCiphers(
    profileFormat,
    rng,
    tlsDefaults: tlsDefaults,
    paddingConfig: paddingConfig,
  );
  final signatures = smartRandomizeSignatures(
    rng,
    tlsDefaults: tlsDefaults,
    paddingConfig: paddingConfig,
  );
  final extensions = smartRandomizeExtensions(
    rng,
    tlsDefaults: tlsDefaults,
    paddingConfig: paddingConfig,
  );
  final versions = randomizeTlsVersions(rng);
  return TlsClientHelloInputs(
    tlsMinVersion: versions.tlsMin,
    tlsMaxVersion: versions.tlsMax,
    cipherSuites: ciphers,
    alpnProtocols: randomizeAlpn(rng),
    extensions: extensions,
    signatureAlgorithms: signatures,
    enableGrease: false,
    enableChXtnPermutation: false,
  );
}

/// Smart-randomized cipher suite IDs for [profileFormat] with priority
/// ordering: supported ciphers first, then remaining picked, then padding.
List<int> smartRandomizeCiphers(
  String? profileFormat,
  Random rng, {
  AppTlsDefaults? tlsDefaults,
  RandomizePaddingConfig paddingConfig = const RandomizePaddingConfig.none(),
}) {
  final pool = profileFormat == 'boringssl'
      ? _boringsslSafeCiphers
      : _nssSafeCiphers;
  final optional = pool.where((c) => c < 4865 || c > 4867).toList();
  final picked = <int>{4865, 4866, 4867};
  picked.addAll(
    _sampleAndShuffle(optional, 2 + rng.nextInt(optional.length - 1), rng),
  );

  final List<int> ordered;
  if (tlsDefaults != null && tlsDefaults.cipherSuites.isNotEmpty) {
    final supportedSet = tlsDefaults.cipherSuites.toSet();
    final supported = picked.where((c) => supportedSet.contains(c)).toList();
    final unsupported = picked.where((c) => !supportedSet.contains(c)).toList();
    ordered = [
      ..._sampleAndShuffle(supported, supported.length, rng),
      ..._sampleAndShuffle(unsupported, unsupported.length, rng),
    ];
  } else {
    ordered = _sampleAndShuffle(picked.toList(), picked.length, rng);
  }

  if (paddingConfig.ciphersEnabled) {
    final count = paddingConfig.cipherPaddingCount ?? (2 + rng.nextInt(5));
    final padding = _generatePadding(
      _paddingCipherPool,
      rng,
      count,
      ordered.toSet(),
    );
    return [...ordered, ...padding];
  }
  return ordered;
}

/// Smart-randomized extension IDs with priority ordering + optional padding.
List<int> smartRandomizeExtensions(
  Random rng, {
  AppTlsDefaults? tlsDefaults,
  RandomizePaddingConfig paddingConfig = const RandomizePaddingConfig.none(),
}) {
  const baseExt = <int>{0, 10, 11, 13, 16, 23, 35, 43, 45, 51, 65281};
  final optional = _safeExtensions.where((e) => !baseExt.contains(e)).toList();
  final picked = <int>{...baseExt};
  picked.addAll(
    _sampleAndShuffle(optional, rng.nextInt(optional.length + 1), rng),
  );

  final List<int> ordered;
  if (tlsDefaults != null && tlsDefaults.extensions.isNotEmpty) {
    final supportedSet = tlsDefaults.extensions.toSet();
    final supported = picked.where((e) => supportedSet.contains(e)).toList();
    final unsupported = picked.where((e) => !supportedSet.contains(e)).toList();
    ordered = [
      ..._sampleAndShuffle(supported, supported.length, rng),
      ..._sampleAndShuffle(unsupported, unsupported.length, rng),
    ];
  } else {
    ordered = _sampleAndShuffle(picked.toList(), picked.length, rng);
  }

  if (paddingConfig.extensionsEnabled) {
    final count = paddingConfig.extensionPaddingCount ?? (1 + rng.nextInt(3));
    final padding = _generatePadding(
      _paddingExtensionPool,
      rng,
      count,
      ordered.toSet(),
    );
    return [...ordered, ...padding];
  }
  return ordered;
}

/// Smart-randomized signature algorithm IDs with priority ordering + optional padding.
List<int> smartRandomizeSignatures(
  Random rng, {
  AppTlsDefaults? tlsDefaults,
  RandomizePaddingConfig paddingConfig = const RandomizePaddingConfig.none(),
}) {
  const required = <int>{1027, 1283, 2052, 2053, 2054};
  final optional = _safeSignatures.where((s) => !required.contains(s)).toList();
  final picked = <int>{...required};
  picked.addAll(
    _sampleAndShuffle(optional, rng.nextInt(optional.length + 1), rng),
  );

  final List<int> ordered;
  if (tlsDefaults != null && tlsDefaults.signatureAlgorithms.isNotEmpty) {
    final supportedSet = tlsDefaults.signatureAlgorithms.toSet();
    final supported = picked.where((s) => supportedSet.contains(s)).toList();
    final unsupported = picked.where((s) => !supportedSet.contains(s)).toList();
    ordered = [
      ..._sampleAndShuffle(supported, supported.length, rng),
      ..._sampleAndShuffle(unsupported, unsupported.length, rng),
    ];
  } else {
    ordered = _sampleAndShuffle(picked.toList(), min(picked.length, 12), rng);
  }

  if (paddingConfig.signatureAlgorithmsEnabled) {
    final count = paddingConfig.sigAlgPaddingCount ?? (1 + rng.nextInt(3));
    final padding = _generatePadding(
      _paddingSigAlgPool,
      rng,
      count,
      ordered.toSet(),
    );
    return [...ordered, ...padding];
  }
  return ordered;
}

// ---------- Internal helpers ----------

List<T> _sampleAndShuffle<T>(List<T> source, int count, Random random) {
  if (source.isEmpty || count <= 0) return <T>[];
  final copy = List<T>.from(source)..shuffle(random);
  return copy.take(min(count, copy.length)).toList(growable: false);
}

/// Picks [count] IDs from [pool] that are not in [exclude].
List<int> _generatePadding(
  List<int> pool,
  Random rng,
  int count,
  Set<int> exclude,
) {
  final available = pool.where((id) => !exclude.contains(id)).toList();
  return _sampleAndShuffle(available, min(count, available.length), rng);
}
