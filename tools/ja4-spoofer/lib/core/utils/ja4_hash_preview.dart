import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Computes a JA4 fingerprint hash preview following the official FoxIO
/// reference implementation.
///
/// JA4 = Prefix _ CiphersHash _ ExtensionsHash
///
/// where ExtensionsHash includes signature algorithms appended to the
/// extensions string before hashing.
class Ja4HashPreview {
  const Ja4HashPreview();

  /// GREASE values to exclude from JA4 computation.
  static const _greaseValues = {
    0x0a0a,
    0x1a1a,
    0x2a2a,
    0x3a3a,
    0x4a4a,
    0x5a5a,
    0x6a6a,
    0x7a7a,
    0x8a8a,
    0x9a9a,
    0xaaaa,
    0xbaba,
    0xcaca,
    0xdada,
    0xeaea,
    0xfafa,
  };

  String compute({
    required String tlsMaxVersion,
    required String sniMode,
    required List<int> cipherSuites,
    required List<int> extensions,
    required List<int> signatureAlgorithms,
    required List<String> alpnProtocols,
    bool isQuic = false,
  }) {
    // Protocol: 't' for TCP, 'q' for QUIC
    final protocol = isQuic ? 'q' : 't';

    // TLS version
    final version = _tlsVersionCode(tlsMaxVersion);

    // SNI: 'd' = domain present, 'i' = no domain / IP / none
    final sni = switch (sniMode) {
      'present' => 'd',
      'domain' => 'd',
      'ip' => 'i',
      'none' => 'i',
      _ => 'd',
    };

    // Filter GREASE from ciphers and extensions
    final filteredCiphers = cipherSuites
        .where((c) => !_greaseValues.contains(c))
        .toList(growable: false);
    final filteredExtensions = extensions
        .where((e) => !_greaseValues.contains(e))
        .toList(growable: false);

    // Counts (2-digit, max 99)
    final cipherCount = filteredCiphers.length.clamp(0, 99);
    final extCount = filteredExtensions.length.clamp(0, 99);

    // First ALPN protocol
    final firstAlpn = alpnProtocols.isEmpty
        ? '00'
        : _alpnPrefix(alpnProtocols.first);

    // Ciphers hash: sorted, hex, comma-separated
    final sortedCiphers = filteredCiphers.toList()..sort();
    final ciphersHash = sortedCiphers.isEmpty
        ? '000000000000'
        : _sha256Prefix(sortedCiphers.map(_toHex4).join(','));

    // Extensions hash: sorted (excluding SNI=0 and ALPN=16), hex,
    // comma-separated, then append _sigAlgs before hashing
    final sortedExts =
        filteredExtensions.where((e) => e != 0 && e != 16).toList()..sort();
    final extString = sortedExts.map(_toHex4).join(',');
    final sigString = signatureAlgorithms.map(_toHex4).join(',');

    String extensionsHash;
    if (sortedExts.isEmpty && signatureAlgorithms.isEmpty) {
      extensionsHash = '000000000000';
    } else {
      final combined = sigString.isEmpty
          ? extString
          : '${extString}_$sigString';
      extensionsHash = _sha256Prefix(combined);
    }

    final prefix =
        '$protocol$version$sni${cipherCount.toString().padLeft(2, '0')}${extCount.toString().padLeft(2, '0')}$firstAlpn';
    return '${prefix}_${ciphersHash}_$extensionsHash';
  }

  String _tlsVersionCode(String version) {
    switch (version) {
      case '1.3':
        return '13';
      case '1.2':
        return '12';
      case '1.1':
        return '11';
      case '1.0':
        return '10';
      default:
        return '13';
    }
  }

  String _alpnPrefix(String alpn) {
    if (alpn.isEmpty) return '00';
    // Non-ASCII: first byte > 127
    if (alpn.codeUnitAt(0) > 127) return '99';
    // More than 2 chars: first + last character
    if (alpn.length > 2) return '${alpn[0]}${alpn[alpn.length - 1]}';
    // 1-2 chars: use as-is, pad with '0' if needed
    return alpn.padRight(2, '0');
  }

  /// Formats an integer as a 4-digit lowercase hex string.
  String _toHex4(int value) => value.toRadixString(16).padLeft(4, '0');

  String _sha256Prefix(String input) {
    final digest = sha256.convert(utf8.encode(input));
    return digest.toString().substring(0, 12);
  }
}
