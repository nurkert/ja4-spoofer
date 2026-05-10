import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/app_settings.dart';
import 'package:ja4_spoofer/core/services/iana_registry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IanaRegistryService fallback bundle', () {
    test('includes Zen-relevant ECDHE CBC suites', () {
      final cipherIds = IanaRegistryService.fallbackBundle.cipherSuites
          .map((item) => item.id)
          .toList(growable: false);

      expect(cipherIds, containsAll([49161, 49162]));
    });
  });

  group('IanaRegistryService.load', () {
    test(
      'disabled source returns the empty bundle (no names anywhere)',
      () async {
        const service = IanaRegistryService();
        final bundle = await service.load(IanaSource.disabled);
        expect(bundle.cipherSuites, isEmpty);
        expect(bundle.extensions, isEmpty);
        expect(bundle.signatureSchemes, isEmpty);
        expect(bundle, same(IanaRegistryService.emptyBundle));
      },
    );

    test(
      'bundled source parses the assets/iana CSV snapshot and dwarfs the fallback',
      () async {
        const service = IanaRegistryService();
        final bundle = await service.load(IanaSource.bundled);

        // Snapshot must contain at least the fallback set (post-parse).
        // The full IANA registries are well over 100 cipher suites and
        // dozens of extensions — assert the order of magnitude rather
        // than exact counts so the test survives upstream additions.
        expect(bundle.cipherSuites.length, greaterThan(50));
        expect(bundle.extensions.length, greaterThan(20));
        expect(bundle.signatureSchemes.length, greaterThan(10));

        // Spot-check a couple of well-known IDs are resolved by name.
        final cipher4865 = bundle.cipherSuites.firstWhere((i) => i.id == 4865);
        expect(cipher4865.name, contains('AES_128_GCM'));

        final ext0 = bundle.extensions.firstWhere((i) => i.id == 0);
        expect(ext0.name.toLowerCase(), contains('server_name'));
      },
    );
  });
}
