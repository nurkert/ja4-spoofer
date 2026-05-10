import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/app_descriptor.dart';
import 'package:ja4_spoofer/core/utils/random_engine.dart';

AppDescriptor _testApp({
  String appId = 'test-app',
  List<int> ciphers = const [
    0x1301,
    0x1302,
    0x1303,
    0xC02B,
    0xC02C,
    0xC02F,
    0xC030,
    0xCCA8,
    0xCCA9,
    0x009C,
    0x009D,
    0x002F,
    0x0035,
  ],
  List<int> extensions = const [
    0,
    5,
    10,
    11,
    13,
    16,
    18,
    23,
    27,
    28,
    35,
    43,
    45,
    51,
    65281,
  ],
  List<int> sigs = const [
    0x0403,
    0x0804,
    0x0401,
    0x0503,
    0x0805,
    0x0501,
    0x0806,
    0x0601,
  ],
}) => AppDescriptor(
  appId: appId,
  metadata: const AppDescriptorMetadata(name: 'Test'),
  build: const AppBuildConfig(script: 'x.sh', builtBinaryPaths: ['x']),
  launch: const AppLaunchConfig(script: 'r.sh', profileFormat: 'curl'),
  tlsDefaults: AppTlsDefaults(
    tlsVersions: const ['1.2', '1.3'],
    cipherSuites: ciphers,
    extensions: extensions,
    signatureAlgorithms: sigs,
    alpnProtocols: const ['h2', 'http/1.1'],
  ),
);

const _engine = RandomEngine();

const _mandatoryCiphers = {0x1301, 0x1302, 0x1303};
const _mandatoryExtensions = {0x0000, 0x000a, 0x000d, 0x002b, 0x002d, 0x0033};
const _mandatorySigAlgs = {0x0403, 0x0804};

void main() {
  group('RandomEngine pool×mutation properties (1000 seeds)', () {
    final app = _testApp();

    test('constrained pool only emits IDs from app.tls_defaults', () {
      final allowedC = app.tlsDefaults.cipherSuites.toSet();
      final allowedE = app.tlsDefaults.extensions.toSet();
      final allowedS = app.tlsDefaults.signatureAlgorithms.toSet();

      const cfg = RandomConfig(
        cipher: ComponentConfig(pool: RandomPool.constrained),
        extension: ComponentConfig(pool: RandomPool.constrained),
        sigalg: ComponentConfig(pool: RandomPool.constrained),
      );

      for (var seed = 0; seed < 1000; seed++) {
        final rolled = _engine.roll(
          app: app,
          config: cfg,
          masterSeed: seed.toRadixString(16).padLeft(16, '0'),
        );
        final inputs = rolled.profile.inputs;
        for (final id in inputs.cipherSuites) {
          expect(
            allowedC.contains(id),
            isTrue,
            reason: 'cipher $id leaked into constrained pool seed=$seed',
          );
        }
        for (final id in inputs.extensions) {
          expect(
            allowedE.contains(id),
            isTrue,
            reason: 'ext $id leaked into constrained pool seed=$seed',
          );
        }
        for (final id in inputs.signatureAlgorithms) {
          expect(
            allowedS.contains(id),
            isTrue,
            reason: 'sigalg $id leaked into constrained pool seed=$seed',
          );
        }
      }
    });

    test('mandatory pin always present when allowIncompat=false', () {
      const cfg = RandomConfig(
        cipher: ComponentConfig(
          pool: RandomPool.chaos,
          mutations: {MutationType.drop, MutationType.swap},
        ),
        extension: ComponentConfig(
          pool: RandomPool.chaos,
          mutations: {MutationType.drop, MutationType.swap},
        ),
        sigalg: ComponentConfig(
          pool: RandomPool.chaos,
          mutations: {MutationType.drop, MutationType.swap},
        ),
        dropAmount: 5,
        swapAmount: 5,
      );

      for (var seed = 0; seed < 1000; seed++) {
        final rolled = _engine.roll(
          app: app,
          config: cfg,
          masterSeed: seed.toRadixString(16).padLeft(16, '0'),
        );
        final inputs = rolled.profile.inputs;
        for (final mid in _mandatoryCiphers) {
          expect(
            inputs.cipherSuites,
            contains(mid),
            reason: 'mandatory cipher $mid dropped seed=$seed',
          );
        }
        for (final mid in _mandatoryExtensions) {
          expect(
            inputs.extensions,
            contains(mid),
            reason: 'mandatory ext $mid dropped seed=$seed',
          );
        }
        for (final mid in _mandatorySigAlgs) {
          expect(
            inputs.signatureAlgorithms,
            contains(mid),
            reason: 'mandatory sigalg $mid dropped seed=$seed',
          );
        }
      }
    });

    test('count-preserving when D and J not in mutations', () {
      const cfg = RandomConfig(
        cipher: ComponentConfig(
          pool: RandomPool.mixed,
          mutations: {MutationType.permute, MutationType.swap},
        ),
        extension: ComponentConfig(
          pool: RandomPool.mixed,
          mutations: {MutationType.permute, MutationType.swap},
        ),
        sigalg: ComponentConfig(
          pool: RandomPool.mixed,
          mutations: {MutationType.permute, MutationType.swap},
        ),
      );

      final baseC = app.tlsDefaults.cipherSuites.length;
      final baseE = app.tlsDefaults.extensions.length;
      final baseS = app.tlsDefaults.signatureAlgorithms.length;

      for (var seed = 0; seed < 1000; seed++) {
        final rolled = _engine.roll(
          app: app,
          config: cfg,
          masterSeed: seed.toRadixString(16).padLeft(16, '0'),
        );
        final inputs = rolled.profile.inputs;
        expect(
          inputs.cipherSuites.length,
          baseC,
          reason: 'cipher count drifted seed=$seed',
        );
        expect(
          inputs.extensions.length,
          baseE,
          reason: 'ext count drifted seed=$seed',
        );
        expect(
          inputs.signatureAlgorithms.length,
          baseS,
          reason: 'sigalg count drifted seed=$seed',
        );
      }
    });

    test('count grows when appendJunk + allowJa4aDrift=true', () {
      // constrained pool never appends foreign IDs; use mixed to test growth.
      const cfg = RandomConfig(
        cipher: ComponentConfig(
          pool: RandomPool.mixed,
          mutations: {MutationType.appendJunk},
        ),
        extension: ComponentConfig(
          pool: RandomPool.mixed,
          mutations: {MutationType.appendJunk},
        ),
        sigalg: ComponentConfig(
          pool: RandomPool.mixed,
          mutations: {MutationType.appendJunk},
        ),
        junkAmount: 3,
      );

      final baseC = app.tlsDefaults.cipherSuites.length;
      final baseE = app.tlsDefaults.extensions.length;
      final baseS = app.tlsDefaults.signatureAlgorithms.length;

      var grewC = 0, grewE = 0, grewS = 0;
      for (var seed = 0; seed < 200; seed++) {
        final rolled = _engine.roll(
          app: app,
          config: cfg,
          masterSeed: seed.toRadixString(16).padLeft(16, '0'),
        );
        final inputs = rolled.profile.inputs;
        if (inputs.cipherSuites.length > baseC) grewC++;
        if (inputs.extensions.length > baseE) grewE++;
        if (inputs.signatureAlgorithms.length > baseS) grewS++;
      }

      expect(
        grewC,
        greaterThan(150),
        reason: 'cipher list grew $grewC/200 with appendJunk',
      );
      expect(
        grewE,
        greaterThan(150),
        reason: 'extension list grew $grewE/200 with appendJunk',
      );
      expect(
        grewS,
        greaterThan(150),
        reason: 'sigalg list grew $grewS/200 with appendJunk',
      );
    });

    test('cross-app determinism: same masterSeed + appId → same roll', () {
      const cfg = RandomConfig();
      const masterSeed = 'deadbeefcafebabe';

      for (var i = 0; i < 50; i++) {
        final r1 = _engine.roll(app: app, config: cfg, masterSeed: masterSeed);
        final r2 = _engine.roll(app: app, config: cfg, masterSeed: masterSeed);
        expect(r1.subSeedHex, r2.subSeedHex);
        expect(
          r1.profile.inputs.cipherSuites,
          equals(r2.profile.inputs.cipherSuites),
        );
        expect(
          r1.profile.inputs.extensions,
          equals(r2.profile.inputs.extensions),
        );
        expect(
          r1.profile.inputs.signatureAlgorithms,
          equals(r2.profile.inputs.signatureAlgorithms),
        );
      }
    });

    test('different appId → different sub-seed (even with same master)', () {
      final appA = _testApp(appId: 'firefox');
      final appB = _testApp(appId: 'chromium');
      const cfg = RandomConfig();
      const masterSeed = 'deadbeefcafebabe';

      final ra = _engine.roll(app: appA, config: cfg, masterSeed: masterSeed);
      final rb = _engine.roll(app: appB, config: cfg, masterSeed: masterSeed);
      expect(ra.subSeedHex, isNot(equals(rb.subSeedHex)));
    });

    test('cipherMode/extensionMode = exact on every roll', () {
      const cfg = RandomConfig();
      for (var seed = 0; seed < 100; seed++) {
        final rolled = _engine.roll(
          app: app,
          config: cfg,
          masterSeed: seed.toRadixString(16).padLeft(16, '0'),
        );
        expect(rolled.profile.inputs.cipherMode, 'exact');
        expect(rolled.profile.inputs.extensionMode, 'exact');
      }
    });

    test('GREASE never emitted by random rolls', () {
      const grease = {
        0x0a0a,
        0x1a1a,
        0x2a2a,
        0x3a3a,
        0x4a4a,
        0x5a5a,
        0x6a6a,
        0x7a7a,
        0x8a8a,
        0x9a9a,
        0xaaaa,
        0xbaba,
        0xcaca,
        0xdada,
        0xeaea,
        0xfafa,
      };
      const cfg = RandomConfig();
      for (var seed = 0; seed < 200; seed++) {
        final rolled = _engine.roll(
          app: app,
          config: cfg,
          masterSeed: seed.toRadixString(16).padLeft(16, '0'),
        );
        for (final id in rolled.profile.inputs.cipherSuites) {
          expect(
            grease.contains(id),
            isFalse,
            reason: 'GREASE leaked into cipher list seed=$seed',
          );
        }
        expect(rolled.profile.inputs.enableGrease, isFalse);
      }
    });

    test('empty tls_defaults → roll returns valid profile (no crash)', () {
      final emptyApp = _testApp(
        ciphers: const [],
        extensions: const [],
        sigs: const [],
      );
      const cfg = RandomConfig();
      final rolled = _engine.roll(
        app: emptyApp,
        config: cfg,
        masterSeed: 'deadbeefcafebabe',
      );
      expect(rolled.profile.inputs.cipherSuites, isEmpty);
      expect(rolled.profile.inputs.extensions, isEmpty);
      expect(rolled.profile.inputs.signatureAlgorithms, isEmpty);
    });

    test('all mutations off → output equals base (modulo permute=off)', () {
      const cfg = RandomConfig(
        cipher: ComponentConfig(mutations: {}),
        extension: ComponentConfig(mutations: {}),
        sigalg: ComponentConfig(mutations: {}),
      );
      final rolled = _engine.roll(
        app: app,
        config: cfg,
        masterSeed: 'deadbeefcafebabe',
      );
      expect(
        rolled.profile.inputs.cipherSuites,
        equals(app.tlsDefaults.cipherSuites),
      );
      expect(
        rolled.profile.inputs.extensions,
        equals(app.tlsDefaults.extensions),
      );
      expect(
        rolled.profile.inputs.signatureAlgorithms,
        equals(app.tlsDefaults.signatureAlgorithms),
      );
    });
  });

  group('RandomEngine helpers', () {
    test('randomSeed returns 16-hex-char string', () {
      for (var i = 0; i < 50; i++) {
        final s = RandomEngine.randomSeed();
        expect(s.length, 16);
        expect(RegExp(r'^[0-9a-fA-F]{16}$').hasMatch(s), isTrue);
      }
    });

    test('randomSeed produces distinct values', () {
      final seen = <String>{};
      for (var i = 0; i < 100; i++) {
        seen.add(RandomEngine.randomSeed());
      }
      expect(
        seen.length,
        greaterThan(95),
        reason: 'randomSeed produced collisions: $seen',
      );
    });
  });
}
