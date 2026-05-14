import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

import '../models/built_in_profiles.dart';
import '../models/fingerprint_profile.dart';
import '../utils/atomic_file.dart';

/// Persists and loads FCS-compatible fingerprint profiles.
///
/// Profiles are stored as JSON files in [profilesDir] (default: ~/.ja4-spoofer/profiles/).
class ProfileService {
  ProfileService({String? profilesDir})
    : profilesDir = profilesDir ?? _defaultProfilesDir();

  final String profilesDir;

  static String _defaultProfilesDir() {
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/.ja4-spoofer/profiles';
  }

  Future<List<FingerprintProfile>> loadAll() async {
    await _seedFromBundleIfNeeded();

    final userProfiles = <FingerprintProfile>[];
    final dir = Directory(profilesDir);
    if (dir.existsSync()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            // A profile with no usable name field can only come from a
            // legacy / partially-written file. Silently drop it from disk
            // so the catalog stops surfacing it as "Unnamed" on every
            // launch.
            final meta = json['metadata'];
            final hasName =
                meta is Map &&
                meta['name'] is String &&
                (meta['name'] as String).trim().isNotEmpty;
            if (!hasName) {
              try {
                await entity.delete();
              } catch (_) {
                /* best-effort */
              }
              continue;
            }
            userProfiles.add(FingerprintProfile.fromJson(json));
          } catch (_) {
            // Skip malformed files
          }
        }
      }
      userProfiles.sort(
        (a, b) =>
            (b.metadata.capturedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                  a.metadata.capturedAt ??
                      DateTime.fromMillisecondsSinceEpoch(0),
                ),
      );
    }

    // Built-in profiles first, then user profiles.
    return [...builtInProfiles, ...userProfiles];
  }

  Future<void> save(FingerprintProfile profile) async {
    final safeId = sanitizeProfileId(profile.profileId);
    final file = File('$profilesDir/$safeId.json');
    await writeJsonAtomic(file, profile.toJson());
  }

  Future<void> delete(String profileId) async {
    // Built-in profiles cannot be deleted.
    if (builtInProfiles.any((p) => p.profileId == profileId)) return;

    final safeId = sanitizeProfileId(profileId);
    final file = File('$profilesDir/$safeId.json');
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Parses a raw FCS JSON string and saves it as a profile.
  Future<FingerprintProfile> importFromJson(String jsonContent) async {
    final json = jsonDecode(jsonContent) as Map<String, dynamic>;
    final profile = FingerprintProfile.fromJson(json);
    await save(profile);
    return profile;
  }

  /// Parses a NSS INI dump (NSS_JA4_DUMP) and creates a FingerprintProfile from it.
  Future<FingerprintProfile?> importFromDump(
    String dumpContent, {
    String? profileId,
  }) async {
    final lines = dumpContent.split('\n');
    final values = <String, String>{};
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#') || !trimmed.contains('=')) continue;
      final idx = trimmed.indexOf('=');
      final key = trimmed.substring(0, idx).trim();
      final value = trimmed.substring(idx + 1).trim();
      values[key] = value;
    }

    if (values.isEmpty) return null;

    final id = profileId ?? 'nss-dump-${DateTime.now().millisecondsSinceEpoch}';
    final ciphers = _parseIntList(
      values['cipher_suites'] ?? values['CIPHER_SUITES'] ?? '',
    );
    final exts = _parseIntList(
      values['extension_order'] ?? values['EXTENSION_ORDER'] ?? '',
    );
    final sigs = _parseIntList(
      values['signature_algorithms'] ?? values['SIGNATURE_ALGORITHMS'] ?? '',
    );
    final supportedVersions = _parseIntList(
      values['supported_versions'] ?? values['SUPPORTED_VERSIONS'] ?? '',
    );
    final supportedGroups = _parseIntList(
      values['supported_groups'] ?? values['SUPPORTED_GROUPS'] ?? '',
    );
    final keyShareGroups = _parseIntList(
      values['key_share_groups'] ?? values['KEY_SHARE_GROUPS'] ?? '',
    );
    final pskModes = _parseIntList(
      values['psk_key_exchange_modes'] ??
          values['PSK_KEY_EXCHANGE_MODES'] ??
          '',
    );
    final alpnRaw = values['alpn'] ?? values['ALPN'] ?? '';
    final alpn = alpnRaw.isEmpty
        ? <String>[]
        : alpnRaw
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();

    final profile = FingerprintProfile(
      profileId: id,
      metadata: FingerprintProfileMetadata(
        name: 'NSS Dump ${DateTime.now().toIso8601String().substring(0, 10)}',
        source: 'captured',
        capturedAt: DateTime.now(),
      ),
      inputs: TlsClientHelloInputs(
        tlsMinVersion: values['tls_min'] ?? values['TLS_MIN'] ?? '1.2',
        tlsMaxVersion: values['tls_max'] ?? values['TLS_MAX'] ?? '1.3',
        cipherSuites: ciphers,
        extensions: exts,
        signatureAlgorithms: sigs,
        supportedVersions: supportedVersions,
        supportedGroups: supportedGroups,
        keyShareGroups: keyShareGroups,
        pskKeyExchangeModes: pskModes,
        alpnProtocols: alpn,
        sniMode: values['sni_mode'] ?? values['SNI_MODE'] ?? 'present',
        enableGrease: (values['enable_grease'] ?? '0') == '1',
        enableChXtnPermutation:
            (values['enable_ch_xtn_permutation'] ?? '0') == '1',
        cipherMode: _parseOptionalMode(
          values['cipher_mode'] ?? values['CIPHER_MODE'],
        ),
        extensionMode: _parseOptionalMode(
          values['extension_mode'] ?? values['EXTENSION_MODE'],
        ),
      ),
    );
    await save(profile);
    return profile;
  }

  List<int> _parseIntList(String raw) {
    if (raw.isEmpty) return [];
    return raw
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
  }

  String? _parseOptionalMode(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  /// Seeds [profilesDir] with bundled `assets/seed-profiles/*.json` and keeps
  /// them in sync across app upgrades.
  ///
  /// We persist the SHA-256 of each seeded file in `.seed-manifest.json`. On
  /// every launch:
  ///   • Missing locally + recorded → user deleted it; never recreate.
  ///   • Missing locally + no record → first seed; copy from bundle.
  ///   • Local matches recorded hash → user untouched; refresh from bundle if
  ///     bundle changed.
  ///   • Local diverges from recorded → user edited; preserve.
  ///
  /// Migration: a legacy `.seeded` marker (with no per-file manifest) means we
  /// previously seeded blindly and never tracked content. In that case we
  /// trust the bundle as source-of-truth for files whose names we own
  /// (`captured-*` etc.) and refresh them, since users who customize a seed
  /// profile are expected to "Save As" with a new ID.
  Future<void> _seedFromBundleIfNeeded() async {
    final dir = Directory(profilesDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final manifestFile = File('$profilesDir/.seed-manifest.json');
    final legacyMarker = File('$profilesDir/.seeded');
    final isLegacyMigration =
        !manifestFile.existsSync() && legacyMarker.existsSync();

    Map<String, String> recorded = {};
    if (manifestFile.existsSync()) {
      try {
        final raw = await manifestFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is String) {
              recorded[entry.key.toString()] = entry.value as String;
            }
          }
        }
      } catch (_) {
        recorded = {};
      }
    }

    try {
      final manifestRaw = await rootBundle.loadString(
        'assets/seed-profiles/manifest.yaml',
      );
      final manifest = loadYaml(manifestRaw);
      final files = (manifest is Map && manifest['files'] is List)
          ? (manifest['files'] as List).cast<String>()
          : const <String>[];

      final updated = <String, String>{};
      for (final name in files) {
        String bundleData;
        try {
          bundleData = await rootBundle.loadString(
            'assets/seed-profiles/$name',
          );
        } catch (_) {
          // Bundle missing — keep prior record so we don't forget the file.
          if (recorded.containsKey(name)) updated[name] = recorded[name]!;
          continue;
        }
        final bundleHash = _hash(bundleData);
        final dest = File('$profilesDir/$name');
        final localExists = dest.existsSync();
        final recordedHash = recorded[name];

        if (!localExists) {
          if (recordedHash != null) {
            // User deleted — respect that, keep record.
            updated[name] = recordedHash;
          } else {
            // First seed.
            await dest.writeAsString(bundleData);
            updated[name] = bundleHash;
          }
          continue;
        }

        if (isLegacyMigration && recordedHash == null) {
          // Pre-tracking install. Trust the bundle for our own seed
          // filenames (they're templates, not user data — see method
          // doc). Refresh and start tracking.
          if (_hash(await dest.readAsString()) != bundleHash) {
            await dest.writeAsString(bundleData);
          }
          updated[name] = bundleHash;
          continue;
        }

        if (recordedHash == null) {
          // Existing file with no record: don't overwrite, but start
          // tracking so future bundle bumps can reason about it.
          updated[name] = _hash(await dest.readAsString());
          continue;
        }

        final localHash = _hash(await dest.readAsString());
        if (localHash == recordedHash) {
          if (localHash != bundleHash) {
            await dest.writeAsString(bundleData);
          }
          updated[name] = bundleHash;
        } else {
          // User edited — preserve, keep prior baseline so a future
          // bundle that matches their edit naturally re-syncs.
          updated[name] = recordedHash;
        }
      }

      await manifestFile.writeAsString(jsonEncode(updated));
      if (legacyMarker.existsSync()) {
        try {
          await legacyMarker.delete();
        } catch (_) {
          /* best-effort cleanup */
        }
      }
    } catch (_) {
      // Manifest absent or malformed — nothing to seed.
    }
  }

  String _hash(String content) =>
      sha256.convert(utf8.encode(content)).toString();
}
