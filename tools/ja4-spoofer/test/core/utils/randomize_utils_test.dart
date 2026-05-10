import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/registry_item.dart';
import 'package:ja4_spoofer/core/utils/randomize_utils.dart';

List<RegistryItem> _makeRegistry(List<int> ids) =>
    ids.map((id) => RegistryItem(id: id, name: 'item-$id')).toList();

void main() {
  group('randomizeTlsVersions', () {
    test('seeded → deterministic result', () {
      final r1 = randomizeTlsVersions(Random(42));
      final r2 = randomizeTlsVersions(Random(42));
      expect(r1.tlsMin, r2.tlsMin);
      expect(r1.tlsMax, r2.tlsMax);
    });

    test('min ≤ max always (over many seeds)', () {
      const choices = ['1.2', '1.3'];
      for (var seed = 0; seed < 100; seed++) {
        final r = randomizeTlsVersions(Random(seed));
        expect(choices.indexOf(r.tlsMin) <= choices.indexOf(r.tlsMax), isTrue);
      }
    });

    test('all 3 valid cases roughly equally likely (uniform over cases)', () {
      // 3 valid (min,max) cases: (1.2,1.2), (1.2,1.3), (1.3,1.3).
      // Old impl produced (1.3,1.3) with 50% — fix should be ~33% each.
      final counts = <String, int>{};
      const trials = 3000;
      for (var seed = 0; seed < trials; seed++) {
        final r = randomizeTlsVersions(Random(seed));
        final key = '${r.tlsMin}-${r.tlsMax}';
        counts[key] = (counts[key] ?? 0) + 1;
      }
      expect(counts.length, 3);
      for (final n in counts.values) {
        // Each case should be within ±5% of the 33.3% expected share.
        expect(n / trials, closeTo(1 / 3, 0.05));
      }
    });
  });

  group('randomizeCiphers', () {
    final registry = _makeRegistry([49195, 49199, 49196, 49200, 49171, 156]);

    test('always contains 4865, 4866, 4867', () {
      for (var seed = 0; seed < 20; seed++) {
        final result = randomizeCiphers(registry, Random(seed));
        expect(result, containsAll([4865, 4866, 4867]));
      }
    });

    test('non-empty result', () {
      final result = randomizeCiphers(registry, Random(0));
      expect(result, isNotEmpty);
    });
  });

  group('randomizeSignatures', () {
    final registry = _makeRegistry([1025, 1539, 2055]);

    test('always contains required sigs', () {
      for (var seed = 0; seed < 20; seed++) {
        final result = randomizeSignatures(registry, Random(seed));
        expect(result, containsAll([2052, 2053, 2054, 1027, 1283]));
      }
    });

    test('length ≤ 14', () {
      for (var seed = 0; seed < 20; seed++) {
        final result = randomizeSignatures(registry, Random(seed));
        expect(result.length, lessThanOrEqualTo(14));
      }
    });
  });

  group('randomizeExtensions', () {
    const baseExt = <int>{0, 10, 11, 13, 16, 23, 35, 43, 45, 51, 65281};
    final registry = _makeRegistry([100, 200, 300]);

    test('all base extensions present', () {
      for (var seed = 0; seed < 20; seed++) {
        final result = randomizeExtensions(registry, Random(seed));
        expect(result.toSet().containsAll(baseExt), isTrue);
      }
    });
  });

  group('randomizeAlpn', () {
    test('result ⊆ [h2, http/1.1]', () {
      for (var seed = 0; seed < 30; seed++) {
        final result = randomizeAlpn(Random(seed));
        for (final p in result) {
          expect(['h2', 'http/1.1'], contains(p));
        }
      }
    });

    test('length ≥ 1', () {
      for (var seed = 0; seed < 30; seed++) {
        final result = randomizeAlpn(Random(seed));
        expect(result.length, greaterThanOrEqualTo(1));
      }
    });
  });

  group('randomProfileDirSuffix', () {
    test('length = bytes*2', () {
      final s = randomProfileDirSuffix(Random(0), bytes: 8);
      expect(s.length, 16);
    });

    test('hex chars only', () {
      final s = randomProfileDirSuffix(Random(0), bytes: 8);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(s), isTrue);
    });

    test('different seeds → different results', () {
      final s1 = randomProfileDirSuffix(Random(1));
      final s2 = randomProfileDirSuffix(Random(99999));
      expect(s1, isNot(s2));
    });
  });

  group('fallback registries', () {
    test('fallbackCipherRegistry is non-empty', () {
      expect(fallbackCipherRegistry, isNotEmpty);
    });

    test('fallbackExtensionRegistry is non-empty', () {
      expect(fallbackExtensionRegistry, isNotEmpty);
    });

    test('fallbackSignatureRegistry is non-empty', () {
      expect(fallbackSignatureRegistry, isNotEmpty);
    });
  });

  group('_sampleAndShuffle (via wrappers)', () {
    test('empty registry → []', () {
      final result = randomizeCiphers([], Random(0));
      // With empty registry, only the mandatory [4865,4866,4867] are added
      expect(result, containsAll([4865, 4866, 4867]));
    });

    test(
      'randomizeAlpn with count=0 would still return ≥1 (pool-size guardrail)',
      () {
        // _sampleAndShuffle with count ≤ 0 returns [] but randomizeAlpn always requests 1+
        // So we verify it always yields ≥ 1
        final result = randomizeAlpn(Random(0));
        expect(result.length, greaterThanOrEqualTo(1));
      },
    );
  });
}
