import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/app_settings.dart';
import 'package:ja4_spoofer/core/services/settings_service.dart';

void main() {
  late Directory tempDir;
  late String settingsPath;
  late SettingsService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ja4_settings_test_');
    settingsPath = '${tempDir.path}/settings.json';
    service = SettingsService(settingsPath: settingsPath);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('SettingsService.load', () {
    test('non-existent file → returns AppSettings() defaults', () async {
      final settings = await service.load();
      expect(settings.repoPath, isNull);
      expect(settings.ianaSource, IanaSource.bundled);
    });

    test('malformed JSON → returns AppSettings() defaults', () async {
      File(settingsPath).writeAsStringSync('not-json{{{');
      final settings = await service.load();
      expect(settings.repoPath, isNull);
      expect(settings.ianaSource, IanaSource.bundled);
    });
  });

  group('SettingsService.save + load round-trip', () {
    test('all fields survive', () async {
      const original = AppSettings(
        repoPath: '/my/repo',
        quickLaunchProfileId: 'abc-123',
        ianaSource: IanaSource.online,
      );
      await service.save(original);
      final loaded = await service.load();
      expect(loaded.repoPath, '/my/repo');
      expect(loaded.quickLaunchProfileId, 'abc-123');
      expect(loaded.ianaSource, IanaSource.online);
    });

    test('nullable fields null → null after load', () async {
      const original = AppSettings();
      await service.save(original);
      final loaded = await service.load();
      expect(loaded.repoPath, isNull);
      expect(loaded.quickLaunchProfileId, isNull);
      expect(loaded.ianaSource, IanaSource.bundled);
    });

    test('creates parent directory if missing', () async {
      final nested = SettingsService(
        settingsPath: '${tempDir.path}/nested/deep/settings.json',
      );
      await nested.save(const AppSettings());
      expect(
        File('${tempDir.path}/nested/deep/settings.json').existsSync(),
        isTrue,
      );
    });

    test('leaves no .tmp file after a successful save', () async {
      await service.save(const AppSettings(repoPath: '/x'));
      final leftovers = tempDir
          .listSync()
          .where((e) => e.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });
  });
}
