import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/controllers/profile_catalog_controller.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/services/profile_service.dart';
import 'package:ja4_spoofer/core/services/settings_service.dart';
import 'package:ja4_spoofer/features/configurator/configurator_controller.dart';
import 'package:ja4_spoofer/features/quick_launch/quick_launch_controller.dart';

void main() {
  late Directory tempDir;
  late ProfileService profileService;
  late SettingsService settingsService;
  late ProfileCatalogController profileCatalogController;
  late ConfiguratorController configuratorController;
  late QuickLaunchController quickLaunchController;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('quick_launch_test_');
    profileService = ProfileService(profilesDir: '${tempDir.path}/profiles');
    settingsService = SettingsService(
      settingsPath: '${tempDir.path}/settings.json',
    );
    profileCatalogController = ProfileCatalogController(
      profileService: profileService,
      settingsService: settingsService,
    );
    configuratorController = ConfiguratorController();
    quickLaunchController = QuickLaunchController(
      apps: const [],
      configuratorController: configuratorController,
      profileCatalogController: profileCatalogController,
    );
  });

  tearDown(() {
    quickLaunchController.dispose();
    configuratorController.dispose();
    profileCatalogController.dispose();
    tempDir.deleteSync(recursive: true);
  });

  FingerprintProfile makeProfile(String id, String name) => FingerprintProfile(
    profileId: id,
    metadata: FingerprintProfileMetadata(name: name, source: 'captured'),
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

  test(
    'selectProfile delegates to catalog and loads configurator state',
    () async {
      final profile = makeProfile('p1', 'Profile 1');
      await profileService.save(profile);
      await profileCatalogController.load();

      await quickLaunchController.selectProfile(profile);

      expect(profileCatalogController.selectedProfileId, 'p1');
      expect(configuratorController.editingProfileId, 'p1');
      expect(quickLaunchController.selectedSection, QuickLaunchSection.profile);
    },
  );

  test(
    'deleting selected profile propagates into quick launch state',
    () async {
      final profile = makeProfile('p2', 'Profile 2');
      await profileService.save(profile);
      await profileCatalogController.load();
      await quickLaunchController.selectProfile(profile);

      await profileCatalogController.deleteProfile('p2');

      expect(quickLaunchController.selectedProfile, isNull);
      expect(
        quickLaunchController.selectedSection,
        QuickLaunchSection.tlsConfiguration,
      );
    },
  );

  // Per-app randomizer engine + UI were removed. The new design is TBD; tests
  // will be reintroduced together with the rebuild.
}
