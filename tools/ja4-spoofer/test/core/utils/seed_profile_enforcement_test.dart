import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/models/ja4_stack.dart';
import 'package:ja4_spoofer/core/utils/fingerprint_enforcement.dart';

/// Every profile the app ships must be launchable as-is.
///
/// A seed profile that trips the pre-flight check would confront the user with
/// a deviation dialog on the very first click, for a profile they did not
/// author — so this is a shipping guarantee, not a style preference.
void main() {
  final seedDir = Directory('assets/seed-profiles');

  test('seed profile directory is present', () {
    expect(seedDir.existsSync(), isTrue);
  });

  final files =
      seedDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final profile = FingerprintProfile.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
    final name = profile.metadata.name;

    for (final stack in Ja4Stack.values) {
      test(
        'seed "$name" launches on ${stack.displayName} without blockers',
        () {
          final report = checkFingerprintEnforcement(
            profile: profile,
            stack: stack,
          );
          expect(
            report.hasBlockers,
            isFalse,
            reason: report.blockers
                .map((i) => '${i.field}: ${i.deviation}')
                .join('\n'),
          );
        },
      );
    }

    test('seed "$name" has a computable JA4', () {
      final ja4 = intendedJa4For(profile);
      expect(
        ja4,
        matches(RegExp(r'^[tq]1[0-3][di]\d{4}.._[0-9a-f]{12}_[0-9a-f]{12}$')),
      );
    });
  }
}
