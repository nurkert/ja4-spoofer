import 'dart:developer' as developer;
import 'dart:typed_data';

/// GREASE values defined by RFC 8701.
const _greaseValues = {
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

bool _isGrease(int value) => _greaseValues.contains(value);

/// All JA4-relevant fields extracted from a TLS ClientHello.
class ParsedClientHello {
  const ParsedClientHello({
    required this.recordVersion,
    required this.handshakeVersion,
    required this.cipherSuites,
    required this.compressionMethods,
    required this.extensionIds,
    required this.extensionData,
  });

  /// TLS record layer version (e.g. 0x0301).
  final int recordVersion;

  /// ClientHello.client_version field (e.g. 0x0303 = TLS 1.2).
  final int handshakeVersion;

  /// Cipher suite IDs in wire order.
  final List<int> cipherSuites;

  /// Compression method IDs.
  final List<int> compressionMethods;

  /// Extension type IDs in wire order.
  final List<int> extensionIds;

  /// Extension type → raw extension payload bytes.
  final Map<int, Uint8List> extensionData;

  // ---------------------------------------------------------------------------
  // Parsed extension helpers
  // ---------------------------------------------------------------------------

  /// SNI hostname (extension 0x0000).
  String? get sni {
    final data = extensionData[0x0000];
    if (data == null || data.length < 5) return null;
    // ServerNameList: list_length(2) + name_type(1) + name_length(2) + name
    final nameLength = (data[3] << 8) | data[4];
    if (data.length < 5 + nameLength) return null;
    return String.fromCharCodes(data.sublist(5, 5 + nameLength));
  }

  /// Supported groups / elliptic curves (extension 0x000a).
  List<int> get supportedGroups => _parseUint16List(extensionData[0x000a]);

  /// Signature algorithms (extension 0x000d).
  List<int> get signatureAlgorithms => _parseUint16List(extensionData[0x000d]);

  /// ALPN protocols (extension 0x0010).
  List<String> get alpnProtocols {
    final data = extensionData[0x0010];
    if (data == null || data.length < 2) return [];
    final listLength = (data[0] << 8) | data[1];
    final protocols = <String>[];
    var i = 2;
    while (i < data.length && i < 2 + listLength) {
      final len = data[i];
      i++;
      if (i + len > data.length) break;
      protocols.add(String.fromCharCodes(data.sublist(i, i + len)));
      i += len;
    }
    return protocols;
  }

  /// Supported versions (extension 0x002b) — client-side list.
  List<int> get supportedVersions {
    final data = extensionData[0x002b];
    if (data == null || data.isEmpty) return [];
    final length = data[0]; // 1-byte length prefix in ClientHello
    // Fail closed on truncated extensions: if the declared length runs
    // past the buffer we'd otherwise return a partial list and the
    // caller wouldn't know its data was lying. Treat as malformed and
    // surface an empty list.
    if (1 + length > data.length) return const [];
    final versions = <int>[];
    for (var i = 1; i + 1 < 1 + length; i += 2) {
      versions.add((data[i] << 8) | data[i + 1]);
    }
    return versions;
  }

  // ---------------------------------------------------------------------------
  // Derived JA4 values
  // ---------------------------------------------------------------------------

  /// Highest offered TLS version as human-readable string.
  String get maxTlsVersion {
    final versions = supportedVersions.where((v) => !_isGrease(v)).toList();
    if (versions.isNotEmpty) {
      return _versionString(versions.reduce((a, b) => a > b ? a : b));
    }
    return _versionString(handshakeVersion);
  }

  /// Lowest offered TLS version as human-readable string.
  String get minTlsVersion {
    final versions = supportedVersions.where((v) => !_isGrease(v)).toList();
    if (versions.isNotEmpty) {
      return _versionString(versions.reduce((a, b) => a < b ? a : b));
    }
    return _versionString(handshakeVersion);
  }

  /// Whether GREASE values are present anywhere.
  bool get hasGrease =>
      cipherSuites.any(_isGrease) || extensionIds.any(_isGrease);

  /// SNI mode for JA4: 'd' if a hostname is present, 'i' otherwise.
  String get sniMode => (sni != null && sni!.isNotEmpty) ? 'present' : 'none';

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Parses a uint16 list preceded by a 2-byte length prefix.
  static List<int> _parseUint16List(Uint8List? data) {
    if (data == null || data.length < 2) return [];
    final length = (data[0] << 8) | data[1];
    final result = <int>[];
    for (var i = 2; i + 1 < data.length && i < 2 + length; i += 2) {
      result.add((data[i] << 8) | data[i + 1]);
    }
    return result;
  }

  static String _versionString(int version) => switch (version) {
    0x0304 => '1.3',
    0x0303 => '1.2',
    0x0302 => '1.1',
    0x0301 => '1.0',
    _ => '1.3',
  };
}

/// Parses raw TCP bytes into a [ParsedClientHello].
class TlsClientHelloParser {
  const TlsClientHelloParser();

  /// Returns a [ParsedClientHello] or `null` if [data] is not a valid
  /// TLS ClientHello record.
  ParsedClientHello? parse(Uint8List data) {
    if (data.length < 5) return null;

    // --- TLS Record Header ---
    if (data[0] != 0x16) return null; // ContentType: Handshake
    final recordVersion = (data[1] << 8) | data[2];
    final recordLength = (data[3] << 8) | data[4];
    if (data.length < 5 + recordLength) return null;

    var offset = 5;

    // --- Handshake Header ---
    if (offset + 4 > data.length) return null;
    if (data[offset] != 0x01) return null; // HandshakeType: ClientHello
    offset += 4; // type(1) + length(3)

    // --- ClientHello.client_version ---
    if (offset + 2 > data.length) return null;
    final clientVersion = (data[offset] << 8) | data[offset + 1];
    offset += 2;

    // --- Random (32 bytes) ---
    if (offset + 32 > data.length) return null;
    offset += 32;

    // --- Session ID ---
    if (offset >= data.length) return null;
    final sessionIdLen = data[offset];
    offset++;
    if (offset + sessionIdLen > data.length) return null;
    offset += sessionIdLen;

    // --- Cipher Suites ---
    if (offset + 2 > data.length) return null;
    final cipherLen = (data[offset] << 8) | data[offset + 1];
    offset += 2;
    if (offset + cipherLen > data.length) return null;

    final cipherSuites = <int>[];
    for (var i = 0; i < cipherLen; i += 2) {
      cipherSuites.add((data[offset + i] << 8) | data[offset + i + 1]);
    }
    offset += cipherLen;

    // --- Compression Methods ---
    if (offset >= data.length) return null;
    final compLen = data[offset];
    offset++;
    if (offset + compLen > data.length) return null;

    final compressionMethods = <int>[];
    for (var i = 0; i < compLen; i++) {
      compressionMethods.add(data[offset + i]);
    }
    offset += compLen;

    // --- Extensions ---
    final extensionIds = <int>[];
    final extensionData = <int, Uint8List>{};

    if (offset + 2 <= data.length) {
      final extTotalLen = (data[offset] << 8) | data[offset + 1];
      offset += 2;
      final extEnd = offset + extTotalLen;

      while (offset + 4 <= extEnd && offset + 4 <= data.length) {
        final extType = (data[offset] << 8) | data[offset + 1];
        offset += 2;
        final extLen = (data[offset] << 8) | data[offset + 1];
        offset += 2;

        if (offset + extLen > data.length || offset + extLen > extEnd) {
          // Extension claims to be longer than the buffer (or longer
          // than the announced extension block). Stop parsing — the
          // remaining bytes can't be trusted to be aligned, and silently
          // advancing `offset` here used to produce garbage IDs.
          developer.log(
            'truncated extension type=0x${extType.toRadixString(16)} '
            'declared_len=$extLen remaining=${data.length - offset}',
            name: 'TlsClientHelloParser',
          );
          break;
        }
        extensionIds.add(extType);
        extensionData[extType] = Uint8List.fromList(
          data.sublist(offset, offset + extLen),
        );
        offset += extLen;
      }
    }

    return ParsedClientHello(
      recordVersion: recordVersion,
      handshakeVersion: clientVersion,
      cipherSuites: cipherSuites,
      compressionMethods: compressionMethods,
      extensionIds: extensionIds,
      extensionData: extensionData,
    );
  }
}
