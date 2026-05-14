import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/app_settings.dart';

void main() {
  group('AppSettings.fromJson', () {
    test('all fields present (new schema)', () {
      final s = AppSettings.fromJson({
        'repo_path': '/repo',
        'quick_launch_profile_id': 'prof-1',
        'iana_source': 'online',
        'load_remote_icons': false,
      });
      expect(s.repoPath, '/repo');
      expect(s.quickLaunchProfileId, 'prof-1');
      expect(s.ianaSource, IanaSource.online);
      expect(s.loadRemoteIcons, isFalse);
    });

    test('missing fields → defaults (bundled IANA, icons on)', () {
      final s = AppSettings.fromJson({});
      expect(s.repoPath, isNull);
      expect(s.quickLaunchProfileId, isNull);
      expect(s.ianaSource, IanaSource.bundled);
      expect(s.loadRemoteIcons, isTrue);
    });

    test('legacy show_iana_names=true migrates to online', () {
      final s = AppSettings.fromJson({'show_iana_names': true});
      expect(s.ianaSource, IanaSource.online);
    });

    test('legacy show_iana_names=false migrates to disabled', () {
      final s = AppSettings.fromJson({'show_iana_names': false});
      expect(s.ianaSource, IanaSource.disabled);
    });

    test('iana_source wins over legacy show_iana_names', () {
      final s = AppSettings.fromJson({
        'iana_source': 'bundled',
        'show_iana_names': true,
      });
      expect(s.ianaSource, IanaSource.bundled);
    });

    test('unknown iana_source value falls back to bundled', () {
      final s = AppSettings.fromJson({'iana_source': 'martian'});
      expect(s.ianaSource, IanaSource.bundled);
    });
  });

  group('AppSettings.toJson', () {
    test('omits null-valued optional keys', () {
      const s = AppSettings();
      final j = s.toJson();
      expect(j.containsKey('repo_path'), isFalse);
      expect(j.containsKey('quick_launch_profile_id'), isFalse);
      expect(j['iana_source'], 'bundled');
      expect(j['load_remote_icons'], isTrue);
      // Old key must not leak through.
      expect(j.containsKey('show_iana_names'), isFalse);
    });

    test('includes all keys when fully populated', () {
      const s = AppSettings(
        repoPath: '/repo',
        quickLaunchProfileId: 'abc',
        ianaSource: IanaSource.online,
        loadRemoteIcons: false,
      );
      final j = s.toJson();
      expect(j['repo_path'], '/repo');
      expect(j['quick_launch_profile_id'], 'abc');
      expect(j['iana_source'], 'online');
      expect(j['load_remote_icons'], isFalse);
    });

    test('always emits schema_version=1', () {
      expect(const AppSettings().toJson()['schema_version'], 1);
      const populated = AppSettings(
        repoPath: '/x',
        ianaSource: IanaSource.online,
      );
      expect(populated.toJson()['schema_version'], 1);
    });
  });

  group('AppSettings.fromJson schema_version', () {
    test('reads v1 schema normally', () {
      final s = AppSettings.fromJson({
        'schema_version': 1,
        'repo_path': '/repo',
        'iana_source': 'online',
        'load_remote_icons': false,
      });
      expect(s.repoPath, '/repo');
      expect(s.ianaSource, IanaSource.online);
      expect(s.loadRemoteIcons, isFalse);
    });

    test('legacy file without schema_version still parses (v0 path)', () {
      // Pre-schema_version persistence: only `show_iana_names` existed.
      // Migration path is exercised by other tests; here we just verify
      // that absence of schema_version does NOT throw.
      final s = AppSettings.fromJson({
        'repo_path': '/legacy',
        'show_iana_names': true,
      });
      expect(s.repoPath, '/legacy');
      expect(s.ianaSource, IanaSource.online);
    });

    test('future schema_version=99 parses best-effort, does not throw', () {
      // A newer app wrote unknown fields; we drop them and parse what
      // we recognize. Important: the load must NOT throw, otherwise the
      // older app silently resets the user's settings on downgrade.
      final s = AppSettings.fromJson({
        'schema_version': 99,
        'repo_path': '/from-future',
        'iana_source': 'bundled',
        'load_remote_icons': true,
        'some_new_field_we_dont_know': 'x',
      });
      expect(s.repoPath, '/from-future');
      expect(s.ianaSource, IanaSource.bundled);
    });
  });

  group('AppSettings.copyWith', () {
    const base = AppSettings(
      repoPath: '/repo',
      quickLaunchProfileId: 'prof-1',
      ianaSource: IanaSource.online,
      loadRemoteIcons: false,
    );

    test('no args → equal values', () {
      final copy = base.copyWith();
      expect(copy.repoPath, base.repoPath);
      expect(copy.quickLaunchProfileId, base.quickLaunchProfileId);
      expect(copy.ianaSource, base.ianaSource);
      expect(copy.loadRemoteIcons, base.loadRemoteIcons);
    });

    test('updates specific fields', () {
      final copy = base.copyWith(
        repoPath: '/new-repo',
        ianaSource: IanaSource.disabled,
      );
      expect(copy.repoPath, '/new-repo');
      expect(copy.ianaSource, IanaSource.disabled);
      expect(copy.quickLaunchProfileId, 'prof-1');
      expect(copy.loadRemoteIcons, isFalse);
    });

    test('toggles loadRemoteIcons independently', () {
      final copy = base.copyWith(loadRemoteIcons: true);
      expect(copy.loadRemoteIcons, isTrue);
      expect(copy.ianaSource, IanaSource.online);
    });

    test('clears nullable field to null by passing explicit null', () {
      final copy = base.copyWith(repoPath: null, quickLaunchProfileId: null);
      expect(copy.repoPath, isNull);
      expect(copy.quickLaunchProfileId, isNull);
      expect(copy.ianaSource, IanaSource.online);
    });
  });

  group('AppSettings.resolvesIanaNames', () {
    test('bundled and online resolve names; disabled does not', () {
      expect(
        const AppSettings(ianaSource: IanaSource.bundled).resolvesIanaNames,
        isTrue,
      );
      expect(
        const AppSettings(ianaSource: IanaSource.online).resolvesIanaNames,
        isTrue,
      );
      expect(
        const AppSettings(ianaSource: IanaSource.disabled).resolvesIanaNames,
        isFalse,
      );
    });
  });
}
