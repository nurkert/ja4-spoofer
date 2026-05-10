import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/controllers/profile_catalog_controller.dart';
import 'package:ja4_spoofer/core/models/app_descriptor.dart';
import 'package:ja4_spoofer/core/services/profile_service.dart';
import 'package:ja4_spoofer/core/services/settings_service.dart';
import 'package:ja4_spoofer/core/utils/random_engine.dart';
import 'package:ja4_spoofer/features/app_launcher/app_launcher_controller.dart';
import 'package:ja4_spoofer/features/configurator/configurator_controller.dart';
import 'package:ja4_spoofer/features/quick_launch/quick_launch_controller.dart';
import 'package:ja4_spoofer/features/quick_launch/widgets/randomize_options_card.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

AppState _appState(String id) => AppState(
  descriptor: AppDescriptor(
    appId: id,
    metadata: AppDescriptorMetadata(name: id),
    build: const AppBuildConfig(script: 'b.sh', builtBinaryPaths: ['x']),
    launch: const AppLaunchConfig(script: 'r.sh', profileFormat: 'curl'),
    tlsDefaults: const AppTlsDefaults(
      tlsVersions: ['1.2', '1.3'],
      cipherSuites: [0x1301, 0x1302, 0x1303, 0xC02B, 0xC02C],
      extensions: [0, 10, 13, 35, 43, 51],
      signatureAlgorithms: [0x0403, 0x0804],
      alpnProtocols: ['h2'],
    ),
  ),
);

Widget _wrap(QuickLaunchController controller) {
  return ShadApp(
    home: Scaffold(
      body: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, _x) => RandomizeOptionsCard(controller: controller),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late Directory tempDir;
  late ProfileCatalogController catalog;
  late ConfiguratorController configurator;
  late QuickLaunchController qlc;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('rnd_card_test_');
    catalog = ProfileCatalogController(
      profileService: ProfileService(profilesDir: '${tempDir.path}/profiles'),
      settingsService: SettingsService(
        settingsPath: '${tempDir.path}/settings.json',
      ),
    );
    configurator = ConfiguratorController();
    qlc = QuickLaunchController(
      apps: [_appState('firefox'), _appState('chromium')],
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

  group('Default rendering', () {
    testWidgets('shows seed field and refresh icon, no Roll button', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(qlc));
      await tester.pump();

      expect(find.text('seed:'), findsOneWidget);
      // No standalone Roll button in default view.
      expect(find.text('Roll'), findsNothing);
      // No JA4_a toggle.
      expect(find.text('JA4_a:'), findsNothing);
    });

    testWidgets('Custom panel is collapsed by default', (tester) async {
      await tester.pumpWidget(_wrap(qlc));
      await tester.pump();
      expect(find.text('Pool'), findsNothing);
      expect(find.text('Mutations'), findsNothing);
      expect(find.text('Cipher'), findsNothing);
    });
  });

  group('Seed row', () {
    testWidgets('refresh icon triggers randomizeSeed → auto-roll', (
      tester,
    ) async {
      qlc.roll(); // put controller in randomize section
      await tester.pumpWidget(_wrap(qlc));
      await tester.pump();

      final seedBefore = qlc.masterSeed;
      // Tap the refresh icon (tooltip: 'Generate fresh random seed').
      await tester.tap(find.byTooltip('Generate fresh random seed'));
      await tester.pump();

      expect(qlc.masterSeed, isNot(seedBefore));
      expect(qlc.hasRollFor('firefox'), isTrue);
    });
  });

  group('Selecting Randomize section auto-rolls', () {
    testWidgets('selecting section generates rolls immediately', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(qlc));
      await tester.pump();

      expect(qlc.hasRollFor('firefox'), isFalse);
      // Tap the card header to select the randomize section.
      await tester.tap(find.text('Randomize'));
      await tester.pump();

      expect(qlc.selectedSection, QuickLaunchSection.randomize);
      expect(qlc.hasRollFor('firefox'), isTrue);
    });
  });

  group('Custom panel expand', () {
    testWidgets('clicking Custom shows Pool dropdowns + Mutation chips', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(qlc));
      await tester.pump();

      await tester.tap(find.text('Custom'));
      await tester.pump();

      expect(find.text('Pool'), findsOneWidget);
      expect(find.text('Mutations'), findsOneWidget);
      expect(find.text('Cipher'), findsOneWidget);
      expect(find.text('Extension'), findsOneWidget);
      expect(find.text('Sigalg'), findsOneWidget);

      // P is only shown for SigAlg (cipher/extension order is irrelevant for JA4_b/c).
      expect(find.text('P'), findsOneWidget);
      // S, D, J appear for all three components.
      expect(find.text('S'), findsNWidgets(3));
      expect(find.text('D'), findsNWidgets(3));
      expect(find.text('J'), findsNWidgets(3));
    });

    testWidgets('toggling a mutation chip propagates to controller', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(qlc));
      await tester.pump();

      await tester.tap(find.text('Custom'));
      await tester.pump();

      // Toggle the Cipher S chip (P is not available for Cipher/Extension).
      final cipherS = find.text('S').first;
      final initialContains = qlc.randomConfig.cipher.mutations.contains(
        MutationType.swap,
      );
      await tester.tap(cipherS);
      await tester.pump();
      final afterContains = qlc.randomConfig.cipher.mutations.contains(
        MutationType.swap,
      );
      expect(afterContains, !initialContains);
    });
  });
}
