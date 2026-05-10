import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/controllers/profile_catalog_controller.dart';
import 'package:ja4_spoofer/core/models/app_settings.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/services/profile_service.dart';
import 'package:ja4_spoofer/core/services/settings_service.dart';

void main() {
  late Directory tempDir;
  late ProfileService profileService;
  late SettingsService settingsService;
  late ProfileCatalogController controller;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('profile_catalog_test_');
    profileService = ProfileService(profilesDir: '${tempDir.path}/profiles');
    settingsService = SettingsService(
      settingsPath: '${tempDir.path}/settings.json',
    );
    controller = ProfileCatalogController(
      profileService: profileService,
      settingsService: settingsService,
    );
  });

  tearDown(() {
    controller.dispose();
    tempDir.deleteSync(recursive: true);
  });

  FingerprintProfile makeProfile(String id, String name) => FingerprintProfile(
    profileId: id,
    metadata: FingerprintProfileMetadata(name: name, source: 'manual'),
    inputs: const TlsClientHelloInputs(
      tlsMinVersion: '1.2',
      tlsMaxVersion: '1.3',
      cipherSuites: [4865, 4866],
      extensions: [0, 43],
      signatureAlgorithms: [1027],
      alpnProtocols: ['h2'],
      sniMode: 'present',
    ),
  );

  test('load restores profiles and selected profile from settings', () async {
    final profile = makeProfile('p1', 'Profile 1');
    await profileService.save(profile);
    await settingsService.save(const AppSettings(quickLaunchProfileId: 'p1'));

    await controller.load();

    expect(controller.profiles.map((p) => p.profileId), contains('p1'));
    expect(controller.selectedProfileId, 'p1');
    expect(controller.selectedProfile?.metadata.name, 'Profile 1');
  });

  test('saveProfile upserts and selects profile', () async {
    final profile = makeProfile('p2', 'Profile 2');

    await controller.saveProfile(profile);

    expect(controller.profiles.where((p) => p.profileId == 'p2'), hasLength(1));
    expect(controller.selectedProfileId, 'p2');
  });

  test(
    'deleteProfile removes selected profile and clears persisted selection',
    () async {
      final profile = makeProfile('p3', 'Profile 3');
      await profileService.save(profile);
      await settingsService.save(const AppSettings(quickLaunchProfileId: 'p3'));
      await controller.load();

      await controller.deleteProfile('p3');

      expect(controller.profiles.where((p) => p.profileId == 'p3'), isEmpty);
      expect(controller.selectedProfileId, isNull);
      final settings = await settingsService.load();
      expect(settings.quickLaunchProfileId, isNull);
    },
  );
}
