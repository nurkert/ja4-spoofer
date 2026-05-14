import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/models/registry_bundle.dart';
import 'package:ja4_spoofer/core/models/registry_item.dart';
import 'package:ja4_spoofer/core/services/iana_registry_service.dart';
import 'package:ja4_spoofer/core/utils/profile_args.dart';
import 'package:ja4_spoofer/features/configurator/configurator_controller.dart';

class _FakeRegistryService extends IanaRegistryService {
  _FakeRegistryService(this.bundle);

  final RegistryBundle bundle;

  @override
  Future<RegistryBundle> loadAll() async => bundle;
}

FingerprintProfile _profileWithUnknownIds() {
  return FingerprintProfile(
    profileId: 'imported-zen',
    metadata: const FingerprintProfileMetadata(
      name: 'Imported Zen',
      source: 'imported',
    ),
    inputs: const TlsClientHelloInputs(
      cipherSuites: [9999, 4865, 9999, 4866, 49161],
      extensions: [0, 0, 9998, 13, 9998],
      signatureAlgorithms: [65000, 2052, 65000],
      alpnProtocols: ['h2'],
    ),
  );
}

void main() {
  test(
    'loadProfile dedupes selections immediately to prevent ReorderableListView crashes',
    () {
      final controller = ConfiguratorController();
      final profile = FingerprintProfile(
        profileId: 'duplicate-test',
        metadata: const FingerprintProfileMetadata(name: 'Duplicate Test'),
        inputs: const TlsClientHelloInputs(
          cipherSuites: [1, 2, 1, 3],
          extensions: [10, 11, 10],
          signatureAlgorithms: [1027, 1027],
          alpnProtocols: ['h2', 'h2', 'http/1.1'],
        ),
      );

      controller.loadProfile(profile);

      expect(controller.selectedCiphers, [1, 2, 3]);
      expect(controller.selectedExtensions, [10, 11]);
      expect(controller.selectedSignatures, [1027]);
      expect(controller.selectedAlpn, ['h2', 'http/1.1']);
    },
  );

  test(
    'registry reload preserves unknown imported IDs and dedupes order',
    () async {
      final controller = ConfiguratorController(
        registryService: _FakeRegistryService(
          const RegistryBundle(
            cipherSuites: [
              RegistryItem(id: 4865, name: 'TLS_AES_128_GCM_SHA256'),
              RegistryItem(id: 4866, name: 'TLS_AES_256_GCM_SHA384'),
            ],
            extensions: [
              RegistryItem(id: 0, name: 'server_name'),
              RegistryItem(id: 13, name: 'signature_algorithms'),
            ],
            signatureSchemes: [
              RegistryItem(id: 2052, name: 'rsa_pss_rsae_sha256'),
            ],
          ),
        ),
      );

      controller.loadProfile(_profileWithUnknownIds());
      await controller.loadRegistries();

      expect(controller.selectedCiphers, [9999, 4865, 4866, 49161]);
      expect(controller.selectedExtensions, [0, 9998, 13]);
      expect(controller.selectedSignatures, [65000, 2052]);
    },
  );

  test(
    'captured profile replay keeps captured source and emits exact cipher mode',
    () {
      final controller = ConfiguratorController();
      final profile = FingerprintProfile(
        profileId: 'captured-zen',
        metadata: const FingerprintProfileMetadata(
          name: 'Zen',
          source: 'captured',
        ),
        inputs: const TlsClientHelloInputs(
          cipherSuites: [4865, 4867, 49162, 49161],
          alpnProtocols: ['h2', 'http/1.1'],
          extensions: [0, 10, 13, 43],
          signatureAlgorithms: [1027, 2052],
          sniMode: 'present',
        ),
      );

      controller.loadProfile(profile);
      final effective = controller.toFingerprintProfile();
      final args = profileToArgs(effective);

      expect(effective.metadata.source, 'captured');
      expect(
        args,
        containsAllInOrder(['--cipher-suites', '4865,4867,49162,49161']),
      );
      expect(args, containsAllInOrder(['--cipher-mode', 'exact']));
    },
  );

  test('captured profile preserves signature_algorithms duplicates on launch '
      '(Apple-Safari 0x0805 quirk)', () {
    final controller = ConfiguratorController();
    final safariProfile = FingerprintProfile(
      profileId: 'captured-safari',
      metadata: const FingerprintProfileMetadata(
        name: 'Captured Safari',
        source: 'captured',
      ),
      inputs: const TlsClientHelloInputs(
        cipherSuites: [4865, 4867, 4866],
        alpnProtocols: ['h2', 'http/1.1'],
        extensions: [0, 10, 13],
        signatureAlgorithms: [1027, 2052, 1025, 1283, 2053, 2053, 1281],
        sniMode: 'present',
      ),
    );

    controller.loadProfile(safariProfile);
    // UI list stays deduped to keep ReorderableListView safe.
    expect(controller.selectedSignatures, [1027, 2052, 1025, 1283, 2053, 1281]);
    // But the launch path must round-trip the original duplicate so the
    // wire-byte JA4 hash matches the captured Safari fingerprint.
    final args = profileToArgs(controller.toFingerprintProfile());
    expect(
      args,
      containsAllInOrder([
        '--signature-algorithms',
        '1027,2052,1025,1283,2053,2053,1281',
      ]),
    );
  });

  test(
    'editing signature_algorithms after load drops the captured raw snapshot',
    () {
      final controller = ConfiguratorController();
      final safariProfile = FingerprintProfile(
        profileId: 'captured-safari-edit',
        metadata: const FingerprintProfileMetadata(
          name: 'Captured Safari',
          source: 'captured',
        ),
        inputs: const TlsClientHelloInputs(
          signatureAlgorithms: [2053, 2053, 1027],
        ),
      );

      controller.loadProfile(safariProfile);
      // User toggles a sig-alg in the editor (any setter call counts as
      // an edit) — the launch path must now reflect the deduped UI list.
      controller.selectedSignatures = [2053, 1027, 1283];
      final args = profileToArgs(controller.toFingerprintProfile());
      expect(
        args,
        containsAllInOrder(['--signature-algorithms', '2053,1027,1283']),
      );
    },
  );
}
