import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/utils/tls_client_hello_parser.dart';

/// Builds a minimal but valid TLS ClientHello record from parts.
Uint8List _buildClientHello({
  int recordVersion = 0x0301,
  int clientVersion = 0x0303,
  List<int> cipherSuites = const [0x1301, 0x1302],
  List<int> compressionMethods = const [0x00],
  List<_Ext> extensions = const [],
}) {
  // --- Build extensions block ---
  final extBytes = <int>[];
  for (final ext in extensions) {
    extBytes.addAll([(ext.type >> 8) & 0xff, ext.type & 0xff]);
    extBytes.addAll([(ext.data.length >> 8) & 0xff, ext.data.length & 0xff]);
    extBytes.addAll(ext.data);
  }
  final extBlock = <int>[];
  if (extBytes.isNotEmpty) {
    extBlock.addAll([(extBytes.length >> 8) & 0xff, extBytes.length & 0xff]);
    extBlock.addAll(extBytes);
  }

  // --- Build ClientHello body ---
  final body = <int>[];
  // client_version
  body.addAll([(clientVersion >> 8) & 0xff, clientVersion & 0xff]);
  // random (32 bytes)
  body.addAll(List.filled(32, 0xab));
  // session_id (empty)
  body.add(0);
  // cipher_suites
  final csLen = cipherSuites.length * 2;
  body.addAll([(csLen >> 8) & 0xff, csLen & 0xff]);
  for (final cs in cipherSuites) {
    body.addAll([(cs >> 8) & 0xff, cs & 0xff]);
  }
  // compression_methods
  body.add(compressionMethods.length);
  body.addAll(compressionMethods);
  // extensions
  body.addAll(extBlock);

  // --- Handshake header ---
  final handshake = <int>[];
  handshake.add(0x01); // ClientHello
  handshake.addAll([
    (body.length >> 16) & 0xff,
    (body.length >> 8) & 0xff,
    body.length & 0xff,
  ]);
  handshake.addAll(body);

  // --- TLS record ---
  final record = <int>[];
  record.add(0x16); // Handshake
  record.addAll([(recordVersion >> 8) & 0xff, recordVersion & 0xff]);
  record.addAll([(handshake.length >> 8) & 0xff, handshake.length & 0xff]);
  record.addAll(handshake);

  return Uint8List.fromList(record);
}

class _Ext {
  const _Ext(this.type, this.data);
  final int type;
  final List<int> data;
}

/// Builds SNI extension data for a hostname.
List<int> _sniExtData(String hostname) {
  final nameBytes = hostname.codeUnits;
  final nameLen = nameBytes.length;
  // ServerNameList: list_length(2) + type(1) + name_length(2) + name
  final listLen = 1 + 2 + nameLen;
  return [
    (listLen >> 8) & 0xff, listLen & 0xff, // list length
    0x00, // host_name type
    (nameLen >> 8) & 0xff, nameLen & 0xff, // name length
    ...nameBytes,
  ];
}

/// Builds ALPN extension data.
List<int> _alpnExtData(List<String> protocols) {
  final protoBytes = <int>[];
  for (final p in protocols) {
    protoBytes.add(p.length);
    protoBytes.addAll(p.codeUnits);
  }
  return [
    (protoBytes.length >> 8) & 0xff,
    protoBytes.length & 0xff,
    ...protoBytes,
  ];
}

/// Builds a uint16 list extension (e.g. supported_groups, sig_algs).
List<int> _uint16ListExtData(List<int> values) {
  final len = values.length * 2;
  final bytes = <int>[(len >> 8) & 0xff, len & 0xff];
  for (final v in values) {
    bytes.addAll([(v >> 8) & 0xff, v & 0xff]);
  }
  return bytes;
}

/// Builds supported_versions extension data (ClientHello format: 1-byte length prefix).
List<int> _supportedVersionsExtData(List<int> versions) {
  final len = versions.length * 2;
  final bytes = <int>[len];
  for (final v in versions) {
    bytes.addAll([(v >> 8) & 0xff, v & 0xff]);
  }
  return bytes;
}

void main() {
  const parser = TlsClientHelloParser();

  group('Basic parsing', () {
    test('parses minimal ClientHello', () {
      final data = _buildClientHello();
      final result = parser.parse(data);
      expect(result, isNotNull);
      expect(result!.handshakeVersion, 0x0303);
      expect(result.cipherSuites, [0x1301, 0x1302]);
      expect(result.compressionMethods, [0x00]);
    });

    test('returns null for non-TLS data', () {
      expect(parser.parse(Uint8List.fromList([0x47, 0x45, 0x54])), isNull);
    });

    test('returns null for truncated data', () {
      expect(parser.parse(Uint8List.fromList([0x16, 0x03])), isNull);
    });

    test('returns null for non-ClientHello handshake', () {
      final data = _buildClientHello();
      // Change handshake type from 0x01 to 0x02 (ServerHello)
      data[5] = 0x02;
      expect(parser.parse(data), isNull);
    });
  });

  group('Cipher suites', () {
    test('parses multiple cipher suites in order', () {
      final data = _buildClientHello(
        cipherSuites: [0x1301, 0xc02b, 0x009c, 0x0035],
      );
      final result = parser.parse(data)!;
      expect(result.cipherSuites, [0x1301, 0xc02b, 0x009c, 0x0035]);
    });

    test('detects GREASE in cipher suites', () {
      final data = _buildClientHello(cipherSuites: [0x0a0a, 0x1301, 0x1302]);
      final result = parser.parse(data)!;
      expect(result.hasGrease, isTrue);
    });
  });

  group('Extensions', () {
    test('parses extension IDs in order', () {
      final data = _buildClientHello(
        extensions: [
          _Ext(0x0000, _sniExtData('example.com')),
          _Ext(0x000a, _uint16ListExtData([0x001d, 0x0017])),
          _Ext(0x0010, _alpnExtData(['h2', 'http/1.1'])),
        ],
      );
      final result = parser.parse(data)!;
      expect(result.extensionIds, [0x0000, 0x000a, 0x0010]);
    });

    test('parses SNI hostname', () {
      final data = _buildClientHello(
        extensions: [_Ext(0x0000, _sniExtData('example.com'))],
      );
      final result = parser.parse(data)!;
      expect(result.sni, 'example.com');
    });

    test('no SNI → null', () {
      final data = _buildClientHello(
        extensions: [
          _Ext(0x000a, _uint16ListExtData([0x001d])),
        ],
      );
      expect(parser.parse(data)!.sni, isNull);
    });

    test('parses ALPN protocols', () {
      final data = _buildClientHello(
        extensions: [
          _Ext(0x0010, _alpnExtData(['h2', 'http/1.1'])),
        ],
      );
      final result = parser.parse(data)!;
      expect(result.alpnProtocols, ['h2', 'http/1.1']);
    });

    test('parses supported groups', () {
      final data = _buildClientHello(
        extensions: [
          _Ext(0x000a, _uint16ListExtData([0x001d, 0x0017, 0x0018])),
        ],
      );
      final result = parser.parse(data)!;
      expect(result.supportedGroups, [0x001d, 0x0017, 0x0018]);
    });

    test('parses signature algorithms', () {
      final data = _buildClientHello(
        extensions: [
          _Ext(0x000d, _uint16ListExtData([0x0403, 0x0804, 0x0401])),
        ],
      );
      final result = parser.parse(data)!;
      expect(result.signatureAlgorithms, [0x0403, 0x0804, 0x0401]);
    });

    test('parses supported versions', () {
      final data = _buildClientHello(
        extensions: [
          _Ext(0x002b, _supportedVersionsExtData([0x0304, 0x0303])),
        ],
      );
      final result = parser.parse(data)!;
      expect(result.supportedVersions, [0x0304, 0x0303]);
    });

    test('detects GREASE in extensions', () {
      final data = _buildClientHello(
        extensions: [
          _Ext(0x0a0a, []), // GREASE extension
          _Ext(0x000a, _uint16ListExtData([0x001d])),
        ],
      );
      final result = parser.parse(data)!;
      expect(result.hasGrease, isTrue);
    });
  });

  group('TLS version detection', () {
    test('maxTlsVersion from supported_versions extension', () {
      final data = _buildClientHello(
        clientVersion: 0x0303,
        extensions: [
          _Ext(0x002b, _supportedVersionsExtData([0x0304, 0x0303])),
        ],
      );
      final result = parser.parse(data)!;
      expect(result.maxTlsVersion, '1.3');
      expect(result.minTlsVersion, '1.2');
    });

    test('falls back to handshake version without supported_versions', () {
      final data = _buildClientHello(clientVersion: 0x0303);
      final result = parser.parse(data)!;
      expect(result.maxTlsVersion, '1.2');
    });

    test('ignores GREASE in supported versions', () {
      final data = _buildClientHello(
        extensions: [
          _Ext(0x002b, _supportedVersionsExtData([0x0a0a, 0x0304, 0x0303])),
        ],
      );
      final result = parser.parse(data)!;
      expect(result.minTlsVersion, '1.2');
    });
  });

  group('SNI mode', () {
    test("hostname present → 'present'", () {
      final data = _buildClientHello(
        extensions: [_Ext(0x0000, _sniExtData('example.com'))],
      );
      expect(parser.parse(data)!.sniMode, 'present');
    });

    test("no SNI extension → 'none'", () {
      final data = _buildClientHello();
      expect(parser.parse(data)!.sniMode, 'none');
    });
  });

  group('Full round-trip scenario', () {
    test('Chrome-like ClientHello captures all fields', () {
      final data = _buildClientHello(
        clientVersion: 0x0303,
        cipherSuites: [0x0a0a, 0x1301, 0x1302, 0x1303, 0xc02b, 0xc02f],
        extensions: [
          _Ext(0x0a0a, []), // GREASE
          _Ext(0x0000, _sniExtData('www.google.com')),
          _Ext(0x0017, []),
          _Ext(0xff01, [0x00]),
          _Ext(0x000a, _uint16ListExtData([0x0a0a, 0x001d, 0x0017, 0x0018])),
          _Ext(0x000b, _uint16ListExtData([])),
          _Ext(0x0023, []),
          _Ext(0x0010, _alpnExtData(['h2', 'http/1.1'])),
          _Ext(0x0005, [0x01, 0x00, 0x00, 0x00, 0x00]),
          _Ext(
            0x000d,
            _uint16ListExtData([
              0x0403,
              0x0804,
              0x0401,
              0x0503,
              0x0805,
              0x0501,
            ]),
          ),
          _Ext(0x0033, _uint16ListExtData([0x001d])),
          _Ext(0x002d, [0x01, 0x01]),
          _Ext(0x002b, _supportedVersionsExtData([0x0a0a, 0x0304, 0x0303])),
          _Ext(0x0015, []),
        ],
      );

      final result = parser.parse(data)!;

      // Cipher suites include GREASE
      expect(result.cipherSuites, [
        0x0a0a,
        0x1301,
        0x1302,
        0x1303,
        0xc02b,
        0xc02f,
      ]);
      expect(result.hasGrease, isTrue);

      // Extensions in wire order
      expect(result.extensionIds.length, 14);
      expect(result.extensionIds.first, 0x0a0a); // GREASE
      expect(result.extensionIds[1], 0x0000); // SNI

      // Parsed fields
      expect(result.sni, 'www.google.com');
      expect(result.alpnProtocols, ['h2', 'http/1.1']);
      expect(result.signatureAlgorithms, [
        0x0403,
        0x0804,
        0x0401,
        0x0503,
        0x0805,
        0x0501,
      ]);
      expect(result.supportedGroups, [0x0a0a, 0x001d, 0x0017, 0x0018]);
      expect(result.maxTlsVersion, '1.3');
      expect(result.minTlsVersion, '1.2');
      expect(result.sniMode, 'present');
    });
  });
}
