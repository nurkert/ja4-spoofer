import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/built_in_profiles.dart';
import 'package:ja4_spoofer/core/models/fingerprint_profile.dart';
import 'package:ja4_spoofer/core/services/profile_service.dart';

FingerprintProfile _makeProfile({
  required String id,
  required String name,
  DateTime? capturedAt,
}) => FingerprintProfile(
  profileId: id,
  metadata: FingerprintProfileMetadata(
    name: name,
    source: 'manual',
    capturedAt: capturedAt,
  ),
  inputs: const TlsClientHelloInputs(
    cipherSuites: [4865, 4866],
    alpnProtocols: ['h2'],
  ),
);

void main() {
  late Directory tempDir;
  late ProfileService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ja4_profiles_test_');
    service = ProfileService(profilesDir: tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('ProfileService.loadAll', () {
    test('non-existent dir → only built-in profiles', () async {
      final nonExistent = ProfileService(
        profilesDir: '${tempDir.path}/does-not-exist',
      );
      expect(await nonExistent.loadAll(), hasLength(builtInProfiles.length));
    });

    test('skips malformed JSON silently', () async {
      File('${tempDir.path}/bad.json').writeAsStringSync('{broken');
      final profiles = await service.loadAll();
      expect(profiles, hasLength(builtInProfiles.length));
    });

    test('sorts by capturedAt descending (newest first)', () async {
      final older = _makeProfile(
        id: 'older',
        name: 'Older',
        capturedAt: DateTime.utc(2023),
      );
      final newer = _makeProfile(
        id: 'newer',
        name: 'Newer',
        capturedAt: DateTime.utc(2024),
      );
      await service.save(older);
      await service.save(newer);
      final profiles = await service.loadAll();
      // Built-in profiles first, then user profiles.
      final userProfiles = profiles.skip(builtInProfiles.length).toList();
      expect(userProfiles.first.profileId, 'newer');
    });

    test('null capturedAt sorts to end', () async {
      final withDate = _makeProfile(
        id: 'dated',
        name: 'Dated',
        capturedAt: DateTime.utc(2024),
      );
      final noDate = _makeProfile(id: 'nodated', name: 'No Date');
      await service.save(withDate);
      await service.save(noDate);
      final profiles = await service.loadAll();
      expect(profiles.last.profileId, 'nodated');
    });
  });

  group('ProfileService.save + loadAll round-trip', () {
    test('saved profile is loaded back', () async {
      final profile = _makeProfile(
        id: 'test-1',
        name: 'Test Profile',
        capturedAt: DateTime.utc(2024, 6, 1),
      );
      await service.save(profile);
      final loaded = await service.loadAll();
      expect(loaded.length, builtInProfiles.length + 1);
      expect(loaded.any((p) => p.profileId == 'test-1'), isTrue);
    });

    test('rejects path-traversal profile_id at save', () async {
      final bad = FingerprintProfile(
        profileId: '../escape',
        metadata: const FingerprintProfileMetadata(name: 'Bad'),
        inputs: const TlsClientHelloInputs(),
      );
      await expectLater(service.save(bad), throwsA(isA<FormatException>()));
      // No file should have been created above profilesDir.
      expect(File('${tempDir.path}/../escape.json').existsSync(), isFalse);
    });

    test('leaves no .tmp file after a successful save', () async {
      await service.save(_makeProfile(id: 'atomic-1', name: 'A'));
      final leftovers = tempDir
          .listSync()
          .where((e) => e.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });
  });

  group('ProfileService.delete', () {
    test('removes the file', () async {
      final profile = _makeProfile(id: 'del-me', name: 'Delete Me');
      await service.save(profile);
      expect(await service.loadAll(), hasLength(builtInProfiles.length + 1));
      await service.delete('del-me');
      expect(await service.loadAll(), hasLength(builtInProfiles.length));
    });

    test('non-existent profileId → no throw', () async {
      await expectLater(service.delete('does-not-exist'), completes);
    });
  });

  group('ProfileService.importFromJson', () {
    test('valid JSON string → saved and returned', () async {
      final profile = _makeProfile(
        id: 'imported',
        name: 'Imported',
        capturedAt: DateTime.utc(2024),
      );
      final jsonStr = jsonEncode(profile.toJson());
      final imported = await service.importFromJson(jsonStr);
      expect(imported.profileId, 'imported');
      final all = await service.loadAll();
      expect(all.any((p) => p.profileId == 'imported'), isTrue);
    });
  });

  group('ProfileService.importFromDump', () {
    test('empty dump → null', () async {
      final result = await service.importFromDump('');
      expect(result, isNull);
    });

    test('comment lines and blank lines skipped', () async {
      const dump = '''
# This is a comment

cipher_suites = 4865,4866
''';
      final result = await service.importFromDump(dump, profileId: 'from-dump');
      expect(result, isNotNull);
      expect(result!.inputs.cipherSuites, [4865, 4866]);
    });

    test('uppercase key variants', () async {
      const dump = '''
CIPHER_SUITES = 4865,4866
TLS_MIN = 1.2
TLS_MAX = 1.3
ALPN = h2,http/1.1
''';
      final result = await service.importFromDump(dump, profileId: 'upper');
      expect(result, isNotNull);
      expect(result!.inputs.cipherSuites, [4865, 4866]);
      expect(result.inputs.tlsMinVersion, '1.2');
      expect(result.inputs.tlsMaxVersion, '1.3');
      expect(result.inputs.alpnProtocols, ['h2', 'http/1.1']);
    });

    test('enable_grease=1 → enableGrease=true', () async {
      const dump = 'enable_grease = 1\ncipher_suites = 4865';
      final result = await service.importFromDump(
        dump,
        profileId: 'grease-test',
      );
      expect(result!.inputs.enableGrease, isTrue);
    });

    test('valid NSS dump parsed correctly', () async {
      const dump = '''
cipher_suites = 4865,4866,4867
cipher_mode = exact
extension_order = 0,10,11,13
extension_mode = reorder
signature_algorithms = 2052,2053
alpn = h2
tls_min = 1.2
tls_max = 1.3
sni_mode = present
''';
      final result = await service.importFromDump(dump, profileId: 'nss-test');
      expect(result, isNotNull);
      expect(result!.inputs.cipherSuites, [4865, 4866, 4867]);
      expect(result.inputs.cipherMode, 'exact');
      expect(result.inputs.extensions, [0, 10, 11, 13]);
      expect(result.inputs.extensionMode, 'reorder');
      expect(result.inputs.signatureAlgorithms, [2052, 2053]);
      expect(result.inputs.alpnProtocols, ['h2']);
      expect(result.inputs.tlsMinVersion, '1.2');
      expect(result.inputs.tlsMaxVersion, '1.3');
      expect(result.inputs.sniMode, 'present');
    });
  });

  group('_parseIntList (via importFromDump)', () {
    test('empty string → []', () async {
      const dump = 'cipher_suites =\nalpn = h2';
      final result = await service.importFromDump(
        dump,
        profileId: 'empty-list',
      );
      expect(result!.inputs.cipherSuites, isEmpty);
    });

    test('invalid tokens skipped', () async {
      const dump = 'cipher_suites = 4865,abc,4866,xyz\nalpn = h2';
      final result = await service.importFromDump(
        dump,
        profileId: 'invalid-tokens',
      );
      expect(result!.inputs.cipherSuites, [4865, 4866]);
    });
  });
}
