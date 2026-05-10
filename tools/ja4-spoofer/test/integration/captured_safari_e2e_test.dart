import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/utils/profile_args.dart';
import 'package:ja4_spoofer/features/configurator/configurator_controller.dart';

void main() {
  test(
    'captured Safari seed profile (1773261198654) emits 0x0805,0x0805 to CLI',
    () {
      final file = File('assets/seed-profiles/captured-1773261198654.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'seed profile must exist at $file',
      );

      final profile = FingerprintProfile.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
      // Sanity: JSON itself contains the duplicate.
      expect(
        profile.inputs.signatureAlgorithms.where((s) => s == 2053).length,
        2,
      );

      final controller = ConfiguratorController();
      controller.loadProfile(profile);

      final args = profileToArgs(controller.toFingerprintProfile());
      final flagIndex = args.indexOf('--signature-algorithms');
      expect(flagIndex, greaterThanOrEqualTo(0));
      // 2053 (0x0805) must appear twice in the CLI value the launch script
      // writes to /tmp/<lib>-ja4-run.conf.
      final csv = args[flagIndex + 1];
      final entries = csv.split(',');
      expect(
        entries.where((e) => e == '2053').length,
        2,
        reason: 'CLI value should keep both 0x0805 entries: $csv',
      );
    },
  );
}
