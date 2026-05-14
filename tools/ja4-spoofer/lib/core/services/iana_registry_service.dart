import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../models/registry_bundle.dart';
import '../models/registry_item.dart';

/// Pluggable HTTP fetcher so tests can inject a deterministic responder
/// without round-tripping through `dart:io`. Production code uses the
/// default which talks to `HttpClient` with the existing 12/20s timeouts.
typedef IanaHttpFetcher = Future<String> Function(Uri url);

/// Loads TLS registries from one of three sources, picked by the user in
/// Settings:
///
/// * [IanaSource.bundled] — parses the CSV snapshot bundled in
///   `assets/iana/` (no network, default for new installs).
/// * [IanaSource.online] — fetches fresh CSVs from iana.org. Falls back
///   to the bundled snapshot if the request fails.
/// * [IanaSource.disabled] — returns the empty bundle. No names are
///   resolved anywhere; pickers and selection rows fall back to hex IDs.
class IanaRegistryService {
  IanaRegistryService({IanaHttpFetcher? fetcher, String? cacheDir})
    : _fetcher = fetcher ?? _defaultFetcher,
      _cacheDir = cacheDir ?? _defaultCacheDir();

  final IanaHttpFetcher _fetcher;
  final String _cacheDir;

  static const Duration _cacheTtl = Duration(days: 7);

  static String _defaultCacheDir() {
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/.ja4-spoofer/cache/iana';
  }

  static const _bundledCipherCsv = 'assets/iana/tls-parameters-4.csv';
  static const _bundledExtensionCsv =
      'assets/iana/tls-extensiontype-values-1.csv';
  static const _bundledSignatureCsv = 'assets/iana/tls-signaturescheme.csv';

  static const _onlineCipherUrl =
      'https://www.iana.org/assignments/tls-parameters/tls-parameters-4.csv';
  static const _onlineExtensionUrl =
      'https://www.iana.org/assignments/tls-extensiontype-values/tls-extensiontype-values-1.csv';
  static const _onlineSignatureUrl =
      'https://www.iana.org/assignments/tls-parameters/tls-signaturescheme.csv';

  static const fallbackBundle = RegistryBundle(
    cipherSuites: _fallbackCipherSuites,
    extensions: _fallbackExtensions,
    signatureSchemes: _fallbackSignatureSchemes,
  );

  /// Empty bundle — used for [IanaSource.disabled] so no names appear in
  /// the GUI anywhere.
  static const emptyBundle = RegistryBundle(
    cipherSuites: <RegistryItem>[],
    extensions: <RegistryItem>[],
    signatureSchemes: <RegistryItem>[],
  );

  /// Returns a registry bundle picked according to [source].
  ///
  /// `disabled` returns [emptyBundle] (no names anywhere). `bundled` parses
  /// the CSV snapshot in `assets/iana/`. `online` fetches live and falls
  /// through to the bundled snapshot on network failure.
  Future<RegistryBundle> load(IanaSource source) async {
    switch (source) {
      case IanaSource.disabled:
        return emptyBundle;
      case IanaSource.bundled:
        return _loadBundled();
      case IanaSource.online:
        try {
          return await _loadOnline();
        } catch (_) {
          return _loadBundled();
        }
    }
  }

  /// Back-compat shortcut still used by callers that always want fresh
  /// data — equivalent to [load] with [IanaSource.online].
  Future<RegistryBundle> loadAll() => load(IanaSource.online);

  Future<RegistryBundle> _loadBundled() async {
    try {
      final cipherText = await rootBundle.loadString(_bundledCipherCsv);
      final extensionText = await rootBundle.loadString(_bundledExtensionCsv);
      final signatureText = await rootBundle.loadString(_bundledSignatureCsv);
      return _bundleFromCsv(
        cipherCsv: cipherText,
        extensionCsv: extensionText,
        signatureCsv: signatureText,
      );
    } catch (_) {
      return fallbackBundle;
    }
  }

  Future<RegistryBundle> _loadOnline() async {
    final results = await Future.wait<String>([
      _fetchCached(_onlineCipherUrl),
      _fetchCached(_onlineExtensionUrl),
      _fetchCached(_onlineSignatureUrl),
    ]);
    return _bundleFromCsv(
      cipherCsv: results[0],
      extensionCsv: results[1],
      signatureCsv: results[2],
    );
  }

  /// Returns the CSV body for [url], using a 7-day on-disk cache. On a
  /// cache miss (or stale entry) tries the network; if that fails and a
  /// stale cache exists, returns it with a warning. Otherwise rethrows
  /// so [load]'s top-level catch can fall through to the bundled
  /// snapshot.
  Future<String> _fetchCached(String url) async {
    final cacheFile = File('$_cacheDir/${_cacheFilename(url)}');
    final fresh = _isFresh(cacheFile);
    if (fresh) {
      try {
        return await cacheFile.readAsString();
      } catch (_) {
        // Treat as miss.
      }
    }
    try {
      final body = await _fetcher(Uri.parse(url));
      await _writeCache(cacheFile, body);
      return body;
    } catch (e) {
      if (cacheFile.existsSync()) {
        developer.log(
          'IANA fetch for $url failed ($e); serving stale cache.',
          name: 'IanaRegistryService',
        );
        return await cacheFile.readAsString();
      }
      rethrow;
    }
  }

  bool _isFresh(File cacheFile) {
    if (!cacheFile.existsSync()) return false;
    final age = DateTime.now().difference(cacheFile.lastModifiedSync());
    return age < _cacheTtl;
  }

  Future<void> _writeCache(File cacheFile, String body) async {
    try {
      final parent = cacheFile.parent;
      if (!parent.existsSync()) parent.createSync(recursive: true);
      await cacheFile.writeAsString(body, flush: true);
    } catch (e) {
      developer.log(
        'IANA cache write failed for ${cacheFile.path}: $e',
        name: 'IanaRegistryService',
      );
    }
  }

  String _cacheFilename(String url) {
    // Hand-rolled basename: every IANA URL ends with the CSV's natural
    // filename, so this stays stable across the three sources.
    final last = url.split('/').last;
    return last.isEmpty ? 'unknown.csv' : last;
  }

  RegistryBundle _bundleFromCsv({
    required String cipherCsv,
    required String extensionCsv,
    required String signatureCsv,
  }) {
    final ciphers = _parseCiphers(cipherCsv);
    final extensions = _parseExtensions(extensionCsv);
    final signatures = _parseSignatures(signatureCsv);
    return RegistryBundle(
      cipherSuites: ciphers.isEmpty ? fallbackBundle.cipherSuites : ciphers,
      extensions: extensions.isEmpty ? fallbackBundle.extensions : extensions,
      signatureSchemes: signatures.isEmpty
          ? fallbackBundle.signatureSchemes
          : signatures,
    );
  }

  List<RegistryItem> _parseCiphers(String text) {
    final rows = const CsvDecoder(dynamicTyping: false).convert(text);
    if (rows.length < 2) return [];

    final header = rows.first.map((e) => e.toString()).toList(growable: false);
    final valueIdx = header.indexOf('Value');
    final descIdx = header.indexOf('Description');
    if (valueIdx < 0 || descIdx < 0) return [];

    final out = <int, RegistryItem>{};
    for (final row in rows.skip(1)) {
      final value = _cell(row, valueIdx);
      final desc = _cell(row, descIdx);
      if (value.isEmpty || desc.isEmpty) continue;
      final parsed = _parseCipherValue(value);
      if (parsed == null) continue;
      out.putIfAbsent(parsed, () => RegistryItem(id: parsed, name: desc));
    }
    final list = out.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  List<RegistryItem> _parseExtensions(String text) {
    final rows = const CsvDecoder(dynamicTyping: false).convert(text);
    if (rows.length < 2) return [];

    final header = rows.first.map((e) => e.toString()).toList(growable: false);
    final valueIdx = header.indexOf('Value');
    final nameIdx = header.indexOf('Extension Name');
    if (valueIdx < 0 || nameIdx < 0) return [];

    final out = <int, RegistryItem>{};
    for (final row in rows.skip(1)) {
      final value = _cell(row, valueIdx);
      final name = _cell(row, nameIdx);
      if (value.isEmpty || name.isEmpty || value.contains('-')) continue;
      final parsed = int.tryParse(value);
      if (parsed == null) continue;
      out.putIfAbsent(parsed, () => RegistryItem(id: parsed, name: name));
    }
    final list = out.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  List<RegistryItem> _parseSignatures(String text) {
    final rows = const CsvDecoder(dynamicTyping: false).convert(text);
    if (rows.length < 2) return [];

    final header = rows.first.map((e) => e.toString()).toList(growable: false);
    final valueIdx = header.indexOf('Value');
    final descIdx = header.indexOf('Description');
    if (valueIdx < 0 || descIdx < 0) return [];

    final out = <int, RegistryItem>{};
    for (final row in rows.skip(1)) {
      final value = _cell(row, valueIdx);
      final desc = _cell(row, descIdx);
      if (value.isEmpty || desc.isEmpty || value.contains('-')) continue;
      final parsed = _parseHexOrDec(value);
      if (parsed == null) continue;
      out.putIfAbsent(parsed, () => RegistryItem(id: parsed, name: desc));
    }
    final list = out.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  String _cell(List<dynamic> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index].toString().trim();
  }

  int? _parseCipherValue(String raw) {
    // IANA format is usually "0x00,0x2F".
    final parts = raw.split(',').map((p) => p.trim()).toList(growable: false);
    if (parts.length != 2) return null;
    if (!parts[0].toLowerCase().startsWith('0x') ||
        !parts[1].toLowerCase().startsWith('0x')) {
      return null;
    }
    final hi = int.tryParse(parts[0].substring(2), radix: 16);
    final lo = int.tryParse(parts[1].substring(2), radix: 16);
    if (hi == null || lo == null) return null;
    return (hi << 8) | lo;
  }

  int? _parseHexOrDec(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.toLowerCase().startsWith('0x')) {
      return int.tryParse(value.substring(2), radix: 16);
    }
    return int.tryParse(value);
  }
}

Future<String> _defaultFetcher(Uri url) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 12);
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, 'ja4_spoofer/1.0');
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode} for $url');
    }
    return await utf8.decoder.bind(response).join();
  } finally {
    client.close(force: true);
  }
}

const _fallbackCipherSuites = <RegistryItem>[
  RegistryItem(id: 4865, name: 'TLS_AES_128_GCM_SHA256'),
  RegistryItem(id: 4866, name: 'TLS_AES_256_GCM_SHA384'),
  RegistryItem(id: 4867, name: 'TLS_CHACHA20_POLY1305_SHA256'),
  RegistryItem(id: 49195, name: 'TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256'),
  RegistryItem(id: 49199, name: 'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256'),
  RegistryItem(id: 49196, name: 'TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384'),
  RegistryItem(id: 49200, name: 'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384'),
  RegistryItem(id: 49161, name: 'TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA'),
  RegistryItem(id: 49162, name: 'TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA'),
];

const _fallbackExtensions = <RegistryItem>[
  RegistryItem(id: 0, name: 'server_name'),
  RegistryItem(id: 5, name: 'status_request'),
  RegistryItem(id: 10, name: 'supported_groups'),
  RegistryItem(id: 11, name: 'ec_point_formats'),
  RegistryItem(id: 13, name: 'signature_algorithms'),
  RegistryItem(id: 16, name: 'application_layer_protocol_negotiation'),
  RegistryItem(id: 18, name: 'signed_certificate_timestamp'),
  RegistryItem(id: 23, name: 'extended_main_secret'),
  RegistryItem(id: 28, name: 'record_size_limit'),
  RegistryItem(id: 34, name: 'delegated_credentials'),
  RegistryItem(id: 35, name: 'session_ticket'),
  RegistryItem(id: 43, name: 'supported_versions'),
  RegistryItem(id: 45, name: 'psk_key_exchange_modes'),
  RegistryItem(id: 51, name: 'key_share'),
  RegistryItem(id: 65281, name: 'renegotiation_info'),
];

const _fallbackSignatureSchemes = <RegistryItem>[
  RegistryItem(id: 1025, name: 'rsa_pkcs1_sha1'),
  RegistryItem(id: 1027, name: 'ecdsa_secp256r1_sha256'),
  RegistryItem(id: 1283, name: 'ecdsa_secp384r1_sha384'),
  RegistryItem(id: 1539, name: 'ecdsa_secp521r1_sha512'),
  RegistryItem(id: 2052, name: 'rsa_pss_rsae_sha256'),
  RegistryItem(id: 2053, name: 'rsa_pss_rsae_sha384'),
  RegistryItem(id: 2054, name: 'rsa_pss_rsae_sha512'),
];
