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

  test('setTlsMin above current tlsMax clamps tlsMax up', () {
    final controller = ConfiguratorController()
      ..setTlsMin('1.2')
      ..setTlsMax('1.2');
    controller.setTlsMin('1.3');
    expect(controller.tlsMin, '1.3');
    expect(
      controller.tlsMax,
      '1.3',
      reason: 'tlsMax should clamp up when min rises above it',
    );
  });

  test('setTlsMax below current tlsMin clamps tlsMin down', () {
    final controller = ConfiguratorController()
      ..setTlsMin('1.3')
      ..setTlsMax('1.3');
    controller.setTlsMax('1.0');
    expect(controller.tlsMax, '1.0');
    expect(
      controller.tlsMin,
      '1.0',
      reason: 'tlsMin should clamp down when max drops below it',
    );
  });

  group('unedited JA4 fields survive a configurator round-trip', () {
    // Regression: the configurator has no editor for these four, and used to
    // rebuild the inputs without them. Opening a profile here silently
    // stripped its supported_versions / supported_groups / key_share_groups /
    // psk_key_exchange_modes, so the launched ClientHello stopped matching the
    // profile the user thought they had selected.
    const richInputs = TlsClientHelloInputs(
      cipherSuites: [4865, 4866],
      cipherMode: 'exact',
      extensions: [0, 10, 16, 43, 45, 51],
      extensionMode: 'exact',
      signatureAlgorithms: [1027],
      alpnProtocols: ['h2'],
      supportedVersions: [772, 771],
      supportedGroups: [29, 23],
      keyShareGroups: [29],
      pskKeyExchangeModes: [1],
    );

    const richProfile = FingerprintProfile(
      profileId: 'rich',
      metadata: FingerprintProfileMetadata(name: 'Rich'),
      inputs: richInputs,
    );

    void expectPreserved(TlsClientHelloInputs actual) {
      expect(actual.supportedVersions, richInputs.supportedVersions);
      expect(actual.supportedGroups, richInputs.supportedGroups);
      expect(actual.keyShareGroups, richInputs.keyShareGroups);
      expect(actual.pskKeyExchangeModes, richInputs.pskKeyExchangeModes);
    }

    test('loadProfile preserves them', () {
      final controller = ConfiguratorController(
        registryService: _FakeRegistryService(
          IanaRegistryService.fallbackBundle,
        ),
      );
      controller.loadProfile(richProfile);
      expectPreserved(controller.toTlsClientHelloInputs());
    });

    test('cloneIntoEditor preserves them', () {
      final controller = ConfiguratorController(
        registryService: _FakeRegistryService(
          IanaRegistryService.fallbackBundle,
        ),
      );
      controller.cloneIntoEditor(richProfile);
      expectPreserved(controller.toTlsClientHelloInputs());
    });

    test('loadFromRandomRoll preserves them', () {
      final controller = ConfiguratorController(
        registryService: _FakeRegistryService(
          IanaRegistryService.fallbackBundle,
        ),
      );
      controller.loadFromRandomRoll(richProfile, suggestedName: 'Roll');
      expectPreserved(controller.toTlsClientHelloInputs());
    });

    test('they reach the launch args', () {
      final controller = ConfiguratorController(
        registryService: _FakeRegistryService(
          IanaRegistryService.fallbackBundle,
        ),
      );
      controller.loadProfile(richProfile);
      final args = profileToArgs(controller.toFingerprintProfile());
      expect(args, containsAllInOrder(['--supported-versions', '772,771']));
      expect(args, containsAllInOrder(['--supported-groups', '29,23']));
      expect(args, containsAllInOrder(['--key-share-groups', '29']));
      expect(args, containsAllInOrder(['--psk-key-exchange-modes', '1']));
    });

    test('a new profile starts without carried-over values', () {
      final controller = ConfiguratorController(
        registryService: _FakeRegistryService(
          IanaRegistryService.fallbackBundle,
        ),
      );
      controller.loadProfile(richProfile);
      controller.resetToDefaults();
      final inputs = controller.toTlsClientHelloInputs();
      expect(inputs.supportedVersions, isEmpty);
      expect(inputs.supportedGroups, isEmpty);
      expect(inputs.keyShareGroups, isEmpty);
      expect(inputs.pskKeyExchangeModes, isEmpty);
    });
  });

  test('a full random roll is launchable without a pre-flight prompt', () {
    final controller = ConfiguratorController(
      registryService: _FakeRegistryService(IanaRegistryService.fallbackBundle),
    );
    controller.randomizeAll();
    expect(controller.cipherMode, 'exact');
    expect(controller.extensionMode, 'exact');
  });
}
