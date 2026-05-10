import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/app_descriptor.dart';
import '../models/fingerprint_profile.dart';

/// Pool used to choose replacement IDs for a component.
///
/// * [constrained] = only `app.tls_defaults`; safest
/// * [mixed] = `app.tls_defaults` plus public registry IDs
/// * [chaos] = arbitrary 16-bit codepoints; maximum drift, unsafe
enum RandomPool { constrained, mixed, chaos }

/// Mutation applied to a list.
///
/// * [permute] = shuffle order while keeping IDs
/// * [drop] = remove individual IDs
/// * [swap] = replace IDs with alternatives from the pool
/// * [appendJunk] = append extra pool IDs
enum MutationType { permute, drop, swap, appendJunk }

/// Component of a ClientHello list to mutate.
enum RandomComponent { cipher, extension, sigalg }

/// SNI behavior for random rolls.
///
/// * [present] = always send SNI
/// * [none] = never send SNI
/// * [random] = deterministic per-roll coin toss
enum SniRandomMode { present, none, random }

/// TLS versions offered in the ClientHello.
///
/// * [v12and13] = TLS 1.2 plus TLS 1.3
/// * [v13only] = TLS 1.3 only
/// * [v12only] = TLS 1.2 only
/// * [random] = deterministic random choice per roll
enum TlsVersionMode { v12and13, v13only, v12only, random }

/// ALPN protocols offered in the ClientHello.
///
/// * [keep] = app defaults unchanged
/// * [random] = common deterministic random combination
enum AlpnMode { keep, random }

/// Per-component configuration.
class ComponentConfig {
  const ComponentConfig({
    this.pool = RandomPool.mixed,
    // Default: drop only. Swap is not safe by default — cipher/extension
    // swap requires a compatible junk pool; the panel makes it opt-in.
    this.mutations = const {MutationType.drop},
  });

  final RandomPool pool;
  final Set<MutationType> mutations;

  ComponentConfig copyWith({RandomPool? pool, Set<MutationType>? mutations}) =>
      ComponentConfig(
        pool: pool ?? this.pool,
        mutations: mutations ?? this.mutations,
      );
}

/// Configuration for one roll.
class RandomConfig {
  const RandomConfig({
    this.cipher = const ComponentConfig(),
    // Extensions: swap is unsafe — each extension type has library-specific
    // content formatting; swapping in unknown types produces invalid content
    // that some servers reject with a TLS alert. Drop-only is safe.
    this.extension = const ComponentConfig(mutations: {MutationType.drop}),
    this.sigalg = const ComponentConfig(
      mutations: {MutationType.permute, MutationType.swap, MutationType.drop},
    ),
    this.allowIncompat = false,
    this.dropAmount = 3,
    this.swapAmount = 2,
    this.junkAmount = 2,
    this.sniMode = SniRandomMode.present,
    this.tlsVersionMode = TlsVersionMode.v12and13,
    this.alpnMode = AlpnMode.random,
  });

  final ComponentConfig cipher;
  final ComponentConfig extension;
  final ComponentConfig sigalg;

  /// When true, mandatory safety pins can be relaxed.
  /// Defaults to false so random rolls remain connection-friendly.
  final bool allowIncompat;

  final int dropAmount;
  final int swapAmount;
  final int junkAmount;

  /// Whether random rolls send SNI.
  final SniRandomMode sniMode;

  /// TLS versions offered.
  final TlsVersionMode tlsVersionMode;

  /// ALPN protocols offered.
  final AlpnMode alpnMode;

  ComponentConfig forComponent(RandomComponent c) => switch (c) {
    RandomComponent.cipher => cipher,
    RandomComponent.extension => extension,
    RandomComponent.sigalg => sigalg,
  };

  RandomConfig copyWith({
    ComponentConfig? cipher,
    ComponentConfig? extension,
    ComponentConfig? sigalg,
    bool? allowIncompat,
    int? dropAmount,
    int? swapAmount,
    int? junkAmount,
    SniRandomMode? sniMode,
    TlsVersionMode? tlsVersionMode,
    AlpnMode? alpnMode,
  }) => RandomConfig(
    cipher: cipher ?? this.cipher,
    extension: extension ?? this.extension,
    sigalg: sigalg ?? this.sigalg,
    allowIncompat: allowIncompat ?? this.allowIncompat,
    dropAmount: dropAmount ?? this.dropAmount,
    swapAmount: swapAmount ?? this.swapAmount,
    junkAmount: junkAmount ?? this.junkAmount,
    sniMode: sniMode ?? this.sniMode,
    tlsVersionMode: tlsVersionMode ?? this.tlsVersionMode,
    alpnMode: alpnMode ?? this.alpnMode,
  );
}

/// Result of one roll for one app.
class RolledProfile {
  const RolledProfile({required this.profile, required this.subSeedHex});

  /// Generated profile ready for replay.
  final FingerprintProfile profile;

  /// App-specific sub-seed hex used for reproducibility and naming.
  final String subSeedHex;
}

/// Pool/mutation engine that creates a [RolledProfile] from an app descriptor
/// and [RandomConfig].
///
/// Core invariants:
/// * `constrained` draws IDs only from `app.tls_defaults`.
/// * mandatory IDs remain present while `allowIncompat` is false.
/// * cross-app determinism uses `SHA256(masterSeed + appId).first8`.
/// * disabled JA4_a drift neutralizes count-changing mutations.
class RandomEngine {
  const RandomEngine();

  // Safety pins prevent accidental handshake breakage.

  /// TLS-1.3 mandatory cipher suites (RFC 8446 §9.1).
  static const _mandatoryCiphers = {0x1301, 0x1302, 0x1303};

  /// Extensions required for a working TLS handshake.
  /// SNI is pinned even though `sniMode` controls whether it is sent, because
  /// dropping it from exact-mode extension lists can disable SNI unexpectedly.
  /// ALPN is pinned because generated profiles set `alpnProtocols`; omitting
  /// the extension can create an inconsistent ClientHello.
  static const _mandatoryExtensions = {
    0x0000, // server_name (SNI) — dropping this kills virtual-hosted HTTPS
    0x000a, // supported_groups
    0x000d, // signature_algorithms
    0x0010, // application_layer_protocol_negotiation (ALPN)
    0x002b, // supported_versions
    0x002d, // psk_key_exchange_modes
    0x0033, // key_share
  };

  /// Standard signature algorithms needed for common certificate chains.
  static const _mandatorySigAlgs = {0x0403, 0x0804};

  // Extra ID pools used by mixed/chaos and appendJunk.

  /// Real ECDHE cipher suites from Firefox that BoringSSL/NSS/OpenSSL all
  /// support — safe to swap in via the manual panel.
  /// DHE suites and unregistered values (0xC0FF, 0xC100) removed: BoringSSL
  /// disables DHE by default and can't construct a ClientHello for unknown IDs.
  static const _ianaCipherJunk = <int>[
    0xC009, // TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA (Firefox)
    0xC00A, // TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA (Firefox)
    0xCCA8, // TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256 (Firefox)
    0xCCA9, // TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 (Firefox)
  ];

  /// IANA-known but rarely used extension types.
  static const _ianaExtensionJunk = <int>[
    14,
    19,
    20,
    25,
    30,
    34,
    49,
    65037,
    17613,
  ];

  /// Modern sigalg codes not present in standard browser defaults.
  /// Legacy SHA1 values (0x0201, 0x0203) removed — deprecated and potentially
  /// rejected by strict NSS/BoringSSL builds.
  static const _ianaSigAlgJunk = <int>[
    0x0807, // ed25519
    0x0808, // ed448
    0x0809, // rsa_pss_pss_sha256
    0x080a, // rsa_pss_pss_sha384
  ];

  /// Creates a [RolledProfile] for [app] from [config] and [masterSeed].
  RolledProfile roll({
    required AppDescriptor app,
    required RandomConfig config,
    required String masterSeed,
  }) {
    final subSeedBytes = _subSeed(masterSeed, app.appId);
    final subSeedHex = subSeedBytes
        .take(8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final rng = Random(_intFromBytes(subSeedBytes));

    final defaults = app.tlsDefaults;

    // TLS versions: determine which to offer based on tlsVersionMode.
    // Uses subSeedBytes[9] so the result is stable across mutation-config changes.
    const _versionSets = [
      ['1.2', '1.3'], // v12and13 (index 0)
      ['1.3'], // v13only  (index 1)
      ['1.2'], // v12only  (index 2)
    ];
    final versionSet = switch (config.tlsVersionMode) {
      TlsVersionMode.v12and13 => _versionSets[0],
      TlsVersionMode.v13only => _versionSets[1],
      TlsVersionMode.v12only => _versionSets[2],
      TlsVersionMode.random => _versionSets[subSeedBytes[9] % 3],
    };
    final (minVer, maxVer) = _tlsVersionRange(versionSet);

    // When TLS 1.2 only: TLS 1.3-specific ciphers (0x1301/02/03) in a
    // TLS 1.2 ClientHello create an anomalous fingerprint. Strip them from
    // the base and don't pin them as mandatory.
    final isV12Only = !versionSet.contains('1.3');
    var cipherBase = List<int>.from(defaults.cipherSuites);
    final effectiveMandatoryCiphers = isV12Only
        ? const <int>{}
        : _mandatoryCiphers;
    if (isV12Only) {
      final filtered = cipherBase
          .where((c) => !_mandatoryCiphers.contains(c))
          .toList();
      if (filtered.isNotEmpty) cipherBase = filtered;
    }

    // SNI: use a dedicated bit from the sub-seed so the result is stable
    // across config changes that alter how many RNG calls the mutations make.
    final sniPresent = switch (config.sniMode) {
      SniRandomMode.present => true,
      SniRandomMode.none => false,
      SniRandomMode.random => (subSeedBytes[8] & 1) == 0,
    };

    // ALPN: subSeedBytes[10] for stable picks across mutation-config changes.
    const _alpnOptions = [
      ['h2', 'http/1.1'],
      ['h2'],
      ['http/1.1'],
      ['h2', 'http/1.1', 'h3-29'],
    ];
    final alpnProtocols = config.alpnMode == AlpnMode.random
        ? _alpnOptions[subSeedBytes[10] % _alpnOptions.length]
        : defaults.alpnProtocols.isEmpty
        ? const ['h2', 'http/1.1']
        : List<String>.from(defaults.alpnProtocols);

    final ciphers = _mutateInts(
      base: cipherBase,
      mandatory: effectiveMandatoryCiphers,
      junkPool: _ianaCipherJunk,
      cfg: config.cipher,
      config: config,
      rng: rng,
    );

    final extensions = _mutateInts(
      base: List<int>.from(defaults.extensions),
      mandatory: _mandatoryExtensions,
      junkPool: _ianaExtensionJunk,
      cfg: config.extension,
      config: config,
      rng: rng,
    );

    final sigalgs = _mutateInts(
      base: List<int>.from(defaults.signatureAlgorithms),
      mandatory: _mandatorySigAlgs,
      junkPool: _ianaSigAlgJunk,
      cfg: config.sigalg,
      config: config,
      rng: rng,
    );

    final inputs = TlsClientHelloInputs(
      tlsMinVersion: minVer,
      tlsMaxVersion: maxVer,
      cipherSuites: ciphers,
      alpnProtocols: alpnProtocols,
      extensions: extensions,
      signatureAlgorithms: sigalgs,
      sniMode: sniPresent ? 'present' : 'none',
      enableGrease: false,
      enableChXtnPermutation: false,
      // Random rolls must override the lib's native cipher/extension list
      // — without exact mode the patched OpenSSL/BoringSSL/NSS would emit
      // their own defaults and our roll would be ignored on the wire.
      cipherMode: 'exact',
      extensionMode: 'exact',
    );

    final profile = FingerprintProfile(
      profileId: 'random-${app.appId}-$subSeedHex',
      metadata: FingerprintProfileMetadata(
        name: '${app.metadata.name} (random $subSeedHex)',
        source: 'random',
        profileFormat: app.launch.profileFormat,
      ),
      inputs: inputs,
    );

    return RolledProfile(profile: profile, subSeedHex: subSeedHex);
  }

  // --- internals ---

  List<int> _mutateInts({
    required List<int> base,
    required Set<int> mandatory,
    required List<int> junkPool,
    required ComponentConfig cfg,
    required RandomConfig config,
    required Random rng,
  }) {
    if (base.isEmpty) return base;

    var current = List<int>.from(base);

    final swapPool = _poolFor(cfg.pool, base, junkPool, rng);
    // constrained means "only app's own defaults" — no foreign IDs ever appended.
    final appendPool = cfg.pool == RandomPool.constrained
        ? <int>[]
        : _poolFor(cfg.pool, base, junkPool, rng);

    if (cfg.mutations.contains(MutationType.permute)) {
      current = _permute(current, mandatory, rng);
    }

    if (cfg.mutations.contains(MutationType.drop)) {
      current = _drop(
        current,
        mandatory,
        config.dropAmount,
        rng,
        allowIncompat: config.allowIncompat,
      );
    }

    if (cfg.mutations.contains(MutationType.swap)) {
      current = _swap(
        current,
        mandatory,
        swapPool,
        config.swapAmount,
        rng,
        allowIncompat: config.allowIncompat,
      );
    }

    if (cfg.mutations.contains(MutationType.appendJunk)) {
      current = _appendJunk(current, appendPool, config.junkAmount, rng);
    }

    return current;
  }

  List<int> _poolFor(
    RandomPool pool,
    List<int> base,
    List<int> ianaJunk,
    Random rng,
  ) {
    switch (pool) {
      case RandomPool.constrained:
        return List<int>.from(base);
      case RandomPool.mixed:
        return [...base, ...ianaJunk];
      case RandomPool.chaos:
        // 16-Bit IDs zufällig + base + ianaJunk
        final extra = List<int>.generate(16, (_) => rng.nextInt(0xFFFF));
        return [...base, ...ianaJunk, ...extra];
    }
  }

  List<int> _permute(List<int> ids, Set<int> mandatory, Random rng) {
    // Mandatory IDs stay pinned at the front; only the rest is shuffled.
    final front = ids.where((id) => mandatory.contains(id)).toList();
    final rest = ids.where((id) => !mandatory.contains(id)).toList();
    if (rest.length < 2) return ids;
    final original = List<int>.from(rest);
    var attempts = 0;
    do {
      rest.shuffle(rng);
      attempts++;
    } while (_listEqual(rest, original) && attempts < 8);
    return [...front, ...rest];
  }

  List<int> _drop(
    List<int> ids,
    Set<int> mandatory,
    int amount,
    Random rng, {
    required bool allowIncompat,
  }) {
    if (ids.isEmpty || amount <= 0) return ids;
    final droppable = <int>[];
    for (var i = 0; i < ids.length; i++) {
      if (allowIncompat || !mandatory.contains(ids[i])) droppable.add(i);
    }
    if (droppable.isEmpty) return ids;
    // Always keep at least one ID — an empty cipher/extension list is invalid.
    final maxDroppable = (ids.length - 1).clamp(0, droppable.length);
    if (maxDroppable == 0) return ids;
    final ceiling = amount > maxDroppable ? maxDroppable : amount;
    final dropCount = 1 + rng.nextInt(ceiling);
    droppable.shuffle(rng);
    final removeIdx = droppable.take(dropCount).toSet();
    final kept = <int>[];
    for (var i = 0; i < ids.length; i++) {
      if (!removeIdx.contains(i)) kept.add(ids[i]);
    }
    return kept;
  }

  List<int> _swap(
    List<int> ids,
    Set<int> mandatory,
    List<int> pool,
    int amount,
    Random rng, {
    required bool allowIncompat,
  }) {
    if (ids.isEmpty || amount <= 0) return ids;
    final present = ids.toSet();
    final junkCandidates = pool.where((id) => !present.contains(id)).toList()
      ..shuffle(rng);
    if (junkCandidates.isEmpty) return ids;

    final swappable = <int>[];
    for (var i = 0; i < ids.length; i++) {
      if (allowIncompat || !mandatory.contains(ids[i])) swappable.add(i);
    }
    if (swappable.isEmpty) return ids;

    final ceiling = [
      amount,
      swappable.length,
      junkCandidates.length,
    ].reduce((a, b) => a < b ? a : b);
    final swapCount = 1 + rng.nextInt(ceiling);
    swappable.shuffle(rng);
    final swapIdx = swappable.take(swapCount).toSet();

    final result = List<int>.from(ids);
    var nextJunk = 0;
    for (final idx in swapIdx) {
      result[idx] = junkCandidates[nextJunk++];
    }
    return result;
  }

  List<int> _appendJunk(List<int> ids, List<int> pool, int amount, Random rng) {
    if (amount <= 0) return ids;
    final present = ids.toSet();
    final available = pool.where((id) => !present.contains(id)).toList()
      ..shuffle(rng);
    if (available.isEmpty) return ids;
    final take = amount > available.length ? available.length : amount;
    return [...ids, ...available.take(take)];
  }

  (String, String) _tlsVersionRange(List<String> declared) {
    final usable =
        declared.where((v) => v == '1.2' || v == '1.3').toSet().toList()
          ..sort();
    if (usable.isEmpty) return ('1.2', '1.3');
    return (usable.first, usable.last);
  }

  List<int> _subSeed(String masterSeed, String appId) {
    final bytes = utf8.encode('$masterSeed:$appId');
    return sha256.convert(bytes).bytes;
  }

  int _intFromBytes(List<int> bytes) {
    var v = 0;
    for (var i = 0; i < 8 && i < bytes.length; i++) {
      v = (v << 8) | bytes[i];
    }
    return v;
  }

  bool _listEqual<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Generates a fresh 8-byte random master seed as a hex string.
  static String randomSeed([Random? rng]) {
    final r = rng ?? Random.secure();
    final bytes = List<int>.generate(8, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
