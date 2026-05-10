import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/controllers/profile_catalog_controller.dart';
import 'package:ja4_spoofer/core/models/app_descriptor.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/services/profile_service.dart';
import 'package:ja4_spoofer/core/services/settings_service.dart';
import 'package:ja4_spoofer/core/utils/compat_prober.dart';
import 'package:ja4_spoofer/core/utils/random_engine.dart';
import 'package:ja4_spoofer/features/app_launcher/app_launcher_controller.dart';
import 'package:ja4_spoofer/features/configurator/configurator_controller.dart';
import 'package:ja4_spoofer/features/quick_launch/quick_launch_controller.dart';

class _StubProber implements CompatProber {
  _StubProber(this._score);
  final CompatScore _score;
  int callCount = 0;

  @override
  ProbeRunner get runner => throw UnimplementedError();

  @override
  Future<CompatScore> probe({
    required AppDescriptor app,
    required FingerprintProfile profile,
    List<String> endpoints = defaultProbeEndpoints,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    callCount++;
    return _score;
  }
}

AppState _makeAppState(String id) => AppState(
  descriptor: AppDescriptor(
    appId: id,
    metadata: AppDescriptorMetadata(name: id),
    build: const AppBuildConfig(script: 'b.sh', builtBinaryPaths: ['x']),
    launch: const AppLaunchConfig(script: 'r.sh', profileFormat: 'curl'),
    tlsDefaults: const AppTlsDefaults(
      tlsVersions: ['1.2', '1.3'],
      cipherSuites: [
        0x1301,
        0x1302,
        0x1303,
        0xC02B,
        0xC02C,
        0xC02F,
        0xC030,
        0x009C,
      ],
      extensions: [0, 5, 10, 11, 13, 16, 23, 35, 43, 45, 51, 65281],
      signatureAlgorithms: [0x0403, 0x0804, 0x0401, 0x0503, 0x0805],
      alpnProtocols: ['h2', 'http/1.1'],
    ),
  ),
);

void main() {
  late Directory tempDir;
  late ProfileCatalogController catalog;
  late ConfiguratorController configurator;
  late QuickLaunchController qlc;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('qlc_random_test_');
    catalog = ProfileCatalogController(
      profileService: ProfileService(profilesDir: '${tempDir.path}/profiles'),
      settingsService: SettingsService(
        settingsPath: '${tempDir.path}/settings.json',
      ),
    );
    configurator = ConfiguratorController();
    qlc = QuickLaunchController(
      apps: [_makeAppState('firefox'), _makeAppState('chromium')],
      configuratorController: configurator,
      profileCatalogController: catalog,
    );
  });

  tearDown(() {
    qlc.dispose();
    configurator.dispose();
    catalog.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('roll()', () {
    test('produces per-app rolls keyed by appId', () {
      qlc.roll();
      expect(qlc.hasRollFor('firefox'), isTrue);
      expect(qlc.hasRollFor('chromium'), isTrue);
      expect(qlc.hasRollFor('unknown'), isFalse);
      expect(
        qlc.rollFor('firefox')!.profile.profileId,
        isNot(equals(qlc.rollFor('chromium')!.profile.profileId)),
      );
    });

    test('activates the randomize section', () {
      expect(qlc.selectedSection, QuickLaunchSection.profile);
      qlc.roll();
      expect(qlc.selectedSection, QuickLaunchSection.randomize);
    });

    test('respects locked seed (does not regenerate seed on roll)', () {
      qlc.setSeed('cafebabedeadbeef');
      final firstSeed = qlc.masterSeed;
      qlc.roll();
      expect(qlc.masterSeed, firstSeed);
      qlc.roll();
      expect(
        qlc.masterSeed,
        firstSeed,
        reason: 'roll() must not regenerate seed',
      );
    });

    test('clears compat probe results on a new roll', () async {
      qlc.roll();
      qlc.scheduleCompatProbe('firefox');
      qlc.roll();
      expect(qlc.compatFor('firefox'), isNull);
    });

    test('with empty apps → noop, no rolls', () {
      final emptyQlc = QuickLaunchController(
        apps: const [],
        configuratorController: configurator,
        profileCatalogController: catalog,
      );
      addTearDown(emptyQlc.dispose);
      emptyQlc.roll();
      expect(emptyQlc.hasRollFor('whatever'), isFalse);
    });
  });

  group('seed actions', () {
    test('setSeed stores the seed, randomizeSeed generates a fresh one', () {
      qlc.setSeed('aabbccdd');
      expect(qlc.masterSeed, 'aabbccdd');

      qlc.randomizeSeed();
      expect(qlc.masterSeed, isNot('aabbccdd'));
    });

    test('setSeed triggers auto-roll when in randomize section', () {
      qlc.roll(); // activates randomize section
      qlc.setSeed('aabbccdd1122');
      expect(qlc.hasRollFor('firefox'), isTrue);
      expect(qlc.masterSeed, 'aabbccdd1122');
    });
  });

  group('config setters auto-roll + survive', () {
    test('setComponentPool updates config', () {
      qlc.setComponentPool(RandomComponent.extension, RandomPool.chaos);
      expect(qlc.randomConfig.extension.pool, RandomPool.chaos);
    });

    test('toggleMutation flips set membership', () {
      final before = qlc.randomConfig.cipher.mutations.contains(
        MutationType.permute,
      );
      qlc.toggleMutation(RandomComponent.cipher, MutationType.permute);
      expect(
        qlc.randomConfig.cipher.mutations.contains(MutationType.permute),
        !before,
      );
    });

    test('setAllowIncompat propagates', () {
      qlc.setAllowIncompat(true);
      expect(qlc.randomConfig.allowIncompat, isTrue);
    });

    test('settings change triggers auto-roll when in randomize section', () {
      qlc.roll();
      final before = qlc.rollFor('firefox')!.subSeedHex;
      qlc.setComponentPool(RandomComponent.cipher, RandomPool.chaos);
      // Same seed + different config → roll fired, same subSeedHex but
      // chaos pool can produce different ciphers; at minimum rolls exist.
      expect(qlc.hasRollFor('firefox'), isTrue);
      // subSeedHex is seed-derived (not config-derived), so it stays the same.
      expect(qlc.rollFor('firefox')!.subSeedHex, before);
    });
  });

  group('profileForLaunch', () {
    test('Random section + roll exists → uses rolled profile', () {
      qlc.roll();
      qlc.selectSection(QuickLaunchSection.randomize);
      final firefox = qlc.apps.firstWhere(
        (a) => a.descriptor.appId == 'firefox',
      );
      final p = qlc.profileForLaunch(firefox);
      expect(p.metadata.source, 'random');
    });

    test('Random section + cleared rolls → falls back to effectiveProfile', () {
      qlc.roll();
      qlc.clearRolls();
      final firefox = qlc.apps.first;
      final p = qlc.profileForLaunch(firefox);
      expect(p.metadata.source, isNot('random'));
    });

    test('non-random section → ignores rolls, uses effectiveProfile', () {
      qlc.roll();
      qlc.selectSection(QuickLaunchSection.tlsConfiguration);
      final p = qlc.profileForLaunch(qlc.apps.first);
      expect(p.metadata.source, isNot('random'));
    });
  });

  group('moveRollToConfigurator', () {
    test('loads roll into Configurator + activates Configurator section', () {
      qlc.roll();
      qlc.selectSection(QuickLaunchSection.randomize);
      qlc.moveRollToConfigurator('firefox');
      expect(qlc.selectedSection, QuickLaunchSection.tlsConfiguration);
      expect(configurator.editingMetadata.name, startsWith('random-firefox-'));
    });

    test('no-op when no roll exists for appId', () {
      qlc.roll(); // activates randomize section
      qlc.clearRolls();
      qlc.moveRollToConfigurator('firefox');
      expect(
        qlc.selectedSection,
        QuickLaunchSection.randomize,
        reason: 'no-op without a roll — must not switch section',
      );
    });
  });

  group('cross-app determinism', () {
    test('same masterSeed → same rolls across separate roll() calls', () {
      qlc.setSeed('cafebabedeadbeef');
      qlc.roll();
      final ff1 = qlc.rollFor('firefox')!;
      final cr1 = qlc.rollFor('chromium')!;

      qlc.roll();
      final ff2 = qlc.rollFor('firefox')!;
      final cr2 = qlc.rollFor('chromium')!;

      expect(
        ff1.profile.inputs.cipherSuites,
        equals(ff2.profile.inputs.cipherSuites),
      );
      expect(
        cr1.profile.inputs.cipherSuites,
        equals(cr2.profile.inputs.cipherSuites),
      );
    });

    test('per-app rolls differ even with same masterSeed', () {
      qlc.setSeed('cafebabedeadbeef');
      qlc.roll();
      final ff = qlc.rollFor('firefox')!;
      final cr = qlc.rollFor('chromium')!;
      expect(ff.subSeedHex, isNot(equals(cr.subSeedHex)));
    });
  });

  group('compat probe integration', () {
    test('scheduleCompatProbe stores score per app', () async {
      final stubScore = CompatScore([
        const ProbeResult(
          endpoint: 'a',
          outcome: ProbeOutcome.compatible,
          exitCode: 0,
        ),
        const ProbeResult(
          endpoint: 'b',
          outcome: ProbeOutcome.compatible,
          exitCode: 0,
        ),
        const ProbeResult(
          endpoint: 'c',
          outcome: ProbeOutcome.compatible,
          exitCode: 0,
        ),
      ]);
      final stubProber = _StubProber(stubScore);
      final probedQlc = QuickLaunchController(
        apps: [_makeAppState('firefox')],
        configuratorController: configurator,
        profileCatalogController: catalog,
        compatProber: stubProber,
      );
      addTearDown(probedQlc.dispose);

      probedQlc.roll();
      await probedQlc.scheduleCompatProbe('firefox');
      expect(stubProber.callCount, 1);
      expect(probedQlc.compatFor('firefox')!.label, '3/3');
      expect(probedQlc.isProbing('firefox'), isFalse);
    });

    test('scheduleCompatProbe with no roll for app → no-op', () async {
      final stubProber = _StubProber(CompatScore([]));
      final probedQlc = QuickLaunchController(
        apps: [_makeAppState('firefox')],
        configuratorController: configurator,
        profileCatalogController: catalog,
        compatProber: stubProber,
      );
      addTearDown(probedQlc.dispose);
      await probedQlc.scheduleCompatProbe('firefox');
      expect(stubProber.callCount, 0);
    });
  });
}
