import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/app_settings.dart';
import 'package:ja4_spoofer/core/services/iana_registry_service.dart';

/// Tiny synthetic CSV used by the cache tests. Parses to 3 ciphers, with
/// a header row that matches the real IANA file shape.
const _miniCipherCsv = '''
Value,Description
"0x13,0x01",TLS_AES_128_GCM_SHA256
"0x13,0x02",TLS_AES_256_GCM_SHA384
"0x13,0x03",TLS_CHACHA20_POLY1305_SHA256
''';

const _miniExtensionCsv = '''
Value,Extension Name
0,server_name
43,supported_versions
''';

const _miniSignatureCsv = '''
Value,Description
0x0403,ecdsa_secp256r1_sha256
''';

class _FakeFetcher {
  _FakeFetcher(this.bodies);

  final Map<String, String> bodies;
  int calls = 0;
  bool offline = false;

  Future<String> call(Uri url) async {
    calls += 1;
    if (offline) {
      throw const SocketException('simulated offline');
    }
    final body = bodies[url.toString()];
    if (body == null) {
      throw HttpException('no mock body for $url');
    }
    return body;
  }
}

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
        final service = IanaRegistryService();
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
        final service = IanaRegistryService();
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

  group('IanaRegistryService.load(online) cache', () {
    late Directory tempDir;
    late _FakeFetcher fetcher;
    late IanaRegistryService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('iana_cache_test_');
      fetcher = _FakeFetcher({
        'https://www.iana.org/assignments/tls-parameters/tls-parameters-4.csv':
            _miniCipherCsv,
        'https://www.iana.org/assignments/tls-extensiontype-values/tls-extensiontype-values-1.csv':
            _miniExtensionCsv,
        'https://www.iana.org/assignments/tls-parameters/tls-signaturescheme.csv':
            _miniSignatureCsv,
      });
      service = IanaRegistryService(
        fetcher: fetcher.call,
        cacheDir: tempDir.path,
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('cache miss fetches each URL exactly once', () async {
      await service.load(IanaSource.online);
      expect(fetcher.calls, 3);
      // Cache files are now on disk.
      expect(File('${tempDir.path}/tls-parameters-4.csv').existsSync(), isTrue);
    });

    test('second load within TTL serves from cache (no new fetch)', () async {
      await service.load(IanaSource.online);
      final firstRunCalls = fetcher.calls;
      await service.load(IanaSource.online);
      expect(
        fetcher.calls,
        firstRunCalls,
        reason: 'no additional fetches expected on warm cache',
      );
    });

    test(
      'offline with stale cache returns the stale data instead of failing',
      () async {
        // Prime cache.
        await service.load(IanaSource.online);
        // Age cache files past the TTL.
        final cacheFile = File('${tempDir.path}/tls-parameters-4.csv');
        final stale = DateTime.now().subtract(const Duration(days: 30));
        await cacheFile.setLastModified(stale);
        await File(
          '${tempDir.path}/tls-extensiontype-values-1.csv',
        ).setLastModified(stale);
        await File(
          '${tempDir.path}/tls-signaturescheme.csv',
        ).setLastModified(stale);

        // Knock the network out.
        fetcher.offline = true;
        final bundle = await service.load(IanaSource.online);

        // We get parsed data from the stale cache, not the bundled
        // fallback — confirms the stale-cache path executed.
        expect(bundle.cipherSuites.length, 3);
        expect(bundle.cipherSuites.first.name, 'TLS_AES_128_GCM_SHA256');
      },
    );

    test(
      'offline with no cache falls through to bundled snapshot via load()',
      () async {
        fetcher.offline = true;
        final bundle = await service.load(IanaSource.online);
        // load()'s top-level catch falls back to the bundled snapshot,
        // which is the full ~hundred-entry registry.
        expect(bundle.cipherSuites.length, greaterThan(50));
      },
    );
  });
}
