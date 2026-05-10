import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/services/app_descriptor_service.dart';

const _validYaml = '''
app_id: firefox-nss-ja4
metadata:
  name: Firefox (NSS JA4)
  description: Firefox with patched NSS
build:
  script: scripts/build_nss.sh
  ssl_only_script: scripts/build_nss_only.sh
  built_binary_paths:
    - dist/nss/lib/libssl.dylib
launch:
  script: scripts/run_firefox_with_ja4.sh
  profile_format: nss
  dump_path: /tmp/nss_ja4_dump.ini
''';

const _anotherYaml = '''
app_id: chromium-boringssl-ja4
metadata:
  name: Chromium (BoringSSL JA4)
build:
  script: scripts/build_chromium.sh
  built_binary_paths: []
launch:
  script: scripts/run_chromium_with_ja4.sh
  profile_format: boringssl
''';

const _cliYaml = '''
app_id: curl-openssl-ja4
metadata:
  name: curl (OpenSSL)
build:
  script: scripts/build_curl_with_openssl.sh
  built_binary_paths: []
launch:
  script: scripts/run_curl_with_ja4.sh
  profile_format: openssl
  runtime:
    kind: cli
    args_placeholder: https://example.com/raw
    args_example: -I https://example.com
    pass_user_args_after_double_dash: true
''';

const _requirementsYaml = '''
app_id: req-test
metadata:
  name: Requirements Test
build:
  script: scripts/build.sh
  built_binary_paths: []
  requirements:
    - name: git
    - { name: "   " }
    - { tool: cmake, version: ">= 3.22" }
    - ""
    - null
launch:
  script: scripts/run.sh
  profile_format: nss
''';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ja4_desc_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('AppDescriptorService.loadAll', () {
    test('from bundled YAML string → returns parsed AppDescriptor', () async {
      final service = AppDescriptorService(
        appsDir: '${tempDir.path}/no-user-apps',
        bundledYamlContents: [_validYaml],
      );
      final descriptors = await service.loadAll();
      expect(descriptors.length, 1);
      expect(descriptors.first.appId, 'firefox-nss-ja4');
      expect(descriptors.first.metadata.name, 'Firefox (NSS JA4)');
      expect(descriptors.first.build.sslOnlyScript, isNotNull);
      expect(descriptors.first.launch.profileFormat, 'nss');
    });

    test('user YAML overrides bundled one with same appId', () async {
      final appsDir = Directory('${tempDir.path}/apps')..createSync();
      // User YAML has same app_id but different name
      File('${appsDir.path}/firefox-nss-ja4.yaml').writeAsStringSync('''
app_id: firefox-nss-ja4
metadata:
  name: Firefox Override
build:
  script: custom_build.sh
  built_binary_paths: []
launch:
  script: custom_launch.sh
  profile_format: nss
''');
      final service = AppDescriptorService(
        appsDir: appsDir.path,
        bundledYamlContents: [_validYaml],
      );
      final descriptors = await service.loadAll();
      expect(descriptors.length, 1);
      expect(descriptors.first.metadata.name, 'Firefox Override');
    });

    test('two bundled YAMLs → two descriptors', () async {
      final service = AppDescriptorService(
        appsDir: '${tempDir.path}/no-user-apps',
        bundledYamlContents: [_validYaml, _anotherYaml],
      );
      final descriptors = await service.loadAll();
      expect(descriptors.length, 2);
    });

    test('launch runtime config is parsed for cli apps', () async {
      final service = AppDescriptorService(
        appsDir: '${tempDir.path}/no-user-apps',
        bundledYamlContents: [_cliYaml],
      );
      final descriptors = await service.loadAll();
      expect(descriptors, hasLength(1));
      final launch = descriptors.single.launch;
      expect(launch.runtime.isCli, isTrue);
      expect(launch.runtime.argsPlaceholder, 'https://example.com/raw');
      expect(launch.runtime.argsExample, '-I https://example.com');
      expect(launch.runtime.passUserArgsAfterDoubleDash, isTrue);
    });

    test(
      'build requirements are sanitized and fallback to tool field',
      () async {
        final service = AppDescriptorService(
          appsDir: '${tempDir.path}/no-user-apps',
          bundledYamlContents: [_requirementsYaml],
        );
        final descriptors = await service.loadAll();
        expect(descriptors, hasLength(1));
        final reqs = descriptors.single.build.requirements;
        expect(reqs.map((r) => r.name).toList(), ['git', 'cmake']);
        expect(reqs.last.version, '>= 3.22');
      },
    );

    test(
      'firefox-nss-ja4 descriptor keeps Zen CBC suites in tls_defaults',
      () async {
        final descriptorYaml = File(
          'assets/descriptors/firefox-nss-ja4.yaml',
        ).readAsStringSync();
        final service = AppDescriptorService(
          appsDir: '${tempDir.path}/no-user-apps',
          bundledYamlContents: [descriptorYaml],
        );
        final descriptors = await service.loadAll();
        expect(descriptors.length, 1);

        final cipherIds = descriptors.single.tlsDefaults.cipherSuites;
        expect(cipherIds, containsAll([49161, 49162]));
        expect(cipherIds.indexOf(49161), lessThan(cipherIds.indexOf(49171)));
        expect(cipherIds.indexOf(49162), lessThan(cipherIds.indexOf(49171)));
      },
    );

    test('malformed YAML → handled gracefully, no crash', () async {
      final service = AppDescriptorService(
        appsDir: '${tempDir.path}/no-user-apps',
        bundledYamlContents: ['{{{{invalid yaml}}}}'],
      );
      final descriptors = await service.loadAll();
      // Should not throw; malformed YAML is skipped
      expect(descriptors, isEmpty);
    });

    test('malformed user YAML file → skipped gracefully', () async {
      final appsDir = Directory('${tempDir.path}/apps-bad')..createSync();
      File('${appsDir.path}/bad.yaml').writeAsStringSync('{{{{bad}');
      final service = AppDescriptorService(
        appsDir: appsDir.path,
        bundledYamlContents: [_validYaml],
      );
      final descriptors = await service.loadAll();
      // Bundled still loads
      expect(descriptors.length, 1);
    });

    group('_parseYaml edge cases', () {
      test('missing metadata section → returns null (skipped)', () async {
        const yaml = '''
app_id: no-meta
build:
  script: build.sh
  built_binary_paths: []
launch:
  script: launch.sh
  profile_format: nss
''';
        final service = AppDescriptorService(
          appsDir: '${tempDir.path}/x',
          bundledYamlContents: [yaml],
        );
        expect(await service.loadAll(), isEmpty);
      });

      test('missing build section → returns null (skipped)', () async {
        const yaml = '''
app_id: no-build
metadata:
  name: Test
launch:
  script: launch.sh
  profile_format: nss
''';
        final service = AppDescriptorService(
          appsDir: '${tempDir.path}/x',
          bundledYamlContents: [yaml],
        );
        expect(await service.loadAll(), isEmpty);
      });

      test('missing launch section → returns null (skipped)', () async {
        const yaml = '''
app_id: no-launch
metadata:
  name: Test
build:
  script: build.sh
  built_binary_paths: []
''';
        final service = AppDescriptorService(
          appsDir: '${tempDir.path}/x',
          bundledYamlContents: [yaml],
        );
        expect(await service.loadAll(), isEmpty);
      });

      test('non-YamlMap input → returns null (skipped)', () async {
        const yaml = '- just a list';
        final service = AppDescriptorService(
          appsDir: '${tempDir.path}/x',
          bundledYamlContents: [yaml],
        );
        expect(await service.loadAll(), isEmpty);
      });
    });
  });

  group('_resolvePath (via loadAll with repoRoot)', () {
    test('absolute path → unchanged', () async {
      const yaml = '''
app_id: abs-test
metadata:
  name: Test
build:
  script: /absolute/path/build.sh
  built_binary_paths: []
launch:
  script: /absolute/launch.sh
  profile_format: nss
''';
      final service = AppDescriptorService(
        appsDir: '${tempDir.path}/x',
        bundledYamlContents: [yaml],
        repoRoot: '/my/repo',
      );
      final desc = (await service.loadAll()).first;
      expect(desc.build.script, '/absolute/path/build.sh');
    });

    test('home-relative ~/... → unchanged', () async {
      const yaml = '''
app_id: home-test
metadata:
  name: Test
build:
  script: ~/scripts/build.sh
  built_binary_paths: []
launch:
  script: ~/scripts/launch.sh
  profile_format: nss
''';
      final service = AppDescriptorService(
        appsDir: '${tempDir.path}/x',
        bundledYamlContents: [yaml],
        repoRoot: '/my/repo',
      );
      final desc = (await service.loadAll()).first;
      expect(desc.build.script, '~/scripts/build.sh');
    });

    test('relative path + repoRoot → prefixed', () async {
      const yaml = '''
app_id: rel-test
metadata:
  name: Test
build:
  script: scripts/build.sh
  built_binary_paths: []
launch:
  script: scripts/launch.sh
  profile_format: nss
''';
      final service = AppDescriptorService(
        appsDir: '${tempDir.path}/x',
        bundledYamlContents: [yaml],
        repoRoot: '/my/repo',
      );
      final desc = (await service.loadAll()).first;
      expect(desc.build.script, '/my/repo/scripts/build.sh');
      expect(desc.launch.script, '/my/repo/scripts/launch.sh');
    });

    test('no repoRoot → relative path unchanged', () async {
      const yaml = '''
app_id: no-root-test
metadata:
  name: Test
build:
  script: scripts/build.sh
  built_binary_paths: []
launch:
  script: scripts/launch.sh
  profile_format: nss
''';
      final service = AppDescriptorService(
        appsDir: '${tempDir.path}/x',
        bundledYamlContents: [yaml],
      );
      final desc = (await service.loadAll()).first;
      expect(desc.build.script, 'scripts/build.sh');
    });

    test('null sslOnlyScript → null in descriptor', () async {
      // _validYaml has ssl_only_script, but this one does not
      const yaml = '''
app_id: no-ssl-only
metadata:
  name: Test
build:
  script: build.sh
  built_binary_paths: []
launch:
  script: launch.sh
  profile_format: nss
''';
      final service = AppDescriptorService(
        appsDir: '${tempDir.path}/x',
        bundledYamlContents: [yaml],
      );
      final desc = (await service.loadAll()).first;
      expect(desc.build.sslOnlyScript, isNull);
    });
  });
}
