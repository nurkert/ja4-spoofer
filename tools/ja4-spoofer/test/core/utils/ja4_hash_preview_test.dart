import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/utils/ja4_hash_preview.dart';

/// Helper: first 12 chars of SHA-256 hex digest.
String _sha256x12(String input) =>
    sha256.convert(utf8.encode(input)).toString().substring(0, 12);

void main() {
  const preview = Ja4HashPreview();

  group('SNI mode mapping', () {
    String sni(String mode) => preview
        .compute(
          tlsMaxVersion: '1.3',
          sniMode: mode,
          cipherSuites: [4865],
          extensions: [0],
          signatureAlgorithms: [],
          alpnProtocols: ['h2'],
        )
        .split('')[3]; // index 3 = SNI indicator

    test("'present' → 'd'", () => expect(sni('present'), 'd'));
    test("'domain' → 'd'", () => expect(sni('domain'), 'd'));
    test("'ip' → 'i'", () => expect(sni('ip'), 'i'));
    test("'none' → 'i' (spec has no 'n')", () => expect(sni('none'), 'i'));
    test("unknown → 'd'", () => expect(sni('bogus'), 'd'));
  });

  group('TLS version code', () {
    String version(String ver) => preview
        .compute(
          tlsMaxVersion: ver,
          sniMode: 'present',
          cipherSuites: [4865],
          extensions: [],
          signatureAlgorithms: [],
          alpnProtocols: [],
        )
        .substring(1, 3);

    test("'1.3' → '13'", () => expect(version('1.3'), '13'));
    test("'1.2' → '12'", () => expect(version('1.2'), '12'));
    test("'1.1' → '11'", () => expect(version('1.1'), '11'));
    test("'1.0' → '10'", () => expect(version('1.0'), '10'));
    test("'' → '13' (default)", () => expect(version(''), '13'));
  });

  group('ALPN prefix', () {
    String alpnPart(List<String> alpn) => preview
        .compute(
          tlsMaxVersion: '1.3',
          sniMode: 'present',
          cipherSuites: [4865],
          extensions: [],
          signatureAlgorithms: [],
          alpnProtocols: alpn,
        )
        .substring(8, 10);

    test("'h2' → 'h2' (2 chars, used as-is)", () {
      expect(alpnPart(['h2']), 'h2');
    });

    test("'http/1.1' → 'h1' (first + last char)", () {
      expect(alpnPart(['http/1.1']), 'h1');
    });

    test("empty → '00'", () {
      expect(alpnPart([]), '00');
    });

    test("'x' → 'x0' (1 char padded)", () {
      expect(alpnPart(['x']), 'x0');
    });

    test("non-ASCII → '99'", () {
      // codeUnit > 127
      expect(alpnPart(['\u0080test']), '99');
    });
  });

  group('Protocol indicator', () {
    test("TCP → 't'", () {
      final result = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [],
        extensions: [],
        signatureAlgorithms: [],
        alpnProtocols: [],
      );
      expect(result[0], 't');
    });

    test("QUIC → 'q'", () {
      final result = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [],
        extensions: [],
        signatureAlgorithms: [],
        alpnProtocols: [],
        isQuic: true,
      );
      expect(result[0], 'q');
    });
  });

  group('GREASE filtering', () {
    test('GREASE values excluded from cipher count', () {
      final withGrease = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [4865, 0x0a0a],
        extensions: [],
        signatureAlgorithms: [],
        alpnProtocols: [],
      );
      final withoutGrease = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [4865],
        extensions: [],
        signatureAlgorithms: [],
        alpnProtocols: [],
      );
      expect(withGrease.substring(4, 6), withoutGrease.substring(4, 6));
    });

    test('GREASE values excluded from extension count', () {
      final withGrease = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [],
        extensions: [10, 0x1a1a],
        signatureAlgorithms: [],
        alpnProtocols: [],
      );
      final withoutGrease = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [],
        extensions: [10],
        signatureAlgorithms: [],
        alpnProtocols: [],
      );
      expect(withGrease.substring(6, 8), withoutGrease.substring(6, 8));
    });
  });

  group('Empty lists', () {
    test('empty ciphers → count "00" and hash 000000000000', () {
      final result = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [],
        extensions: [],
        signatureAlgorithms: [],
        alpnProtocols: [],
      );
      expect(result.substring(4, 6), '00');
      final parts = result.split('_');
      expect(parts[1], '000000000000');
    });

    test('empty extensions and sig algs → hash 000000000000', () {
      final result = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [4865],
        extensions: [],
        signatureAlgorithms: [],
        alpnProtocols: [],
      );
      final parts = result.split('_');
      expect(parts[2], '000000000000');
    });
  });

  group('Cipher count clamped at 99', () {
    test('100 ciphers → "99"', () {
      final ciphers = List.generate(100, (i) => i + 1000);
      final result = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: ciphers,
        extensions: [],
        signatureAlgorithms: [],
        alpnProtocols: [],
      );
      expect(result.substring(4, 6), '99');
    });
  });

  group('Extensions hash', () {
    test('excludes SNI (0) and ALPN (16) from hash input', () {
      final withSniAlpn = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [],
        extensions: [0, 10, 16],
        signatureAlgorithms: [],
        alpnProtocols: [],
      );
      final withoutSniAlpn = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [],
        extensions: [10],
        signatureAlgorithms: [],
        alpnProtocols: [],
      );
      final hashA = withSniAlpn.split('_')[2];
      final hashB = withoutSniAlpn.split('_')[2];
      expect(hashA, hashB);
    });

    test('signature algorithms are combined into extensions hash', () {
      // ext=10 → hex "000a", sigAlg=2052 → hex "0804"
      // Expected: sha256("000a_0804")[:12]
      final result = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [],
        extensions: [10],
        signatureAlgorithms: [2052],
        alpnProtocols: [],
      );
      final parts = result.split('_');
      expect(
        parts.length,
        3,
        reason: 'JA4 has 3 sections: prefix_ciphers_extensions',
      );
      expect(parts[2], _sha256x12('000a_0804'));
    });
  });

  group('Hex formatting', () {
    test('ciphers are formatted as 4-digit hex and comma-separated', () {
      // 4865 = 0x1301, 4866 = 0x1302; sorted: [4865, 4866] → "1301,1302"
      final result = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [4866, 4865],
        extensions: [],
        signatureAlgorithms: [],
        alpnProtocols: [],
      );
      final parts = result.split('_');
      expect(parts[1], _sha256x12('1301,1302'));
    });

    test('small values are zero-padded to 4 hex digits', () {
      // 10 = 0x000a
      final result = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [10],
        extensions: [],
        signatureAlgorithms: [],
        alpnProtocols: [],
      );
      final parts = result.split('_');
      expect(parts[1], _sha256x12('000a'));
    });
  });

  group('Output structure', () {
    test('has exactly 3 sections (prefix_ciphers_extensions)', () {
      final result = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [4865, 4866],
        extensions: [10, 11],
        signatureAlgorithms: [2052],
        alpnProtocols: ['h2'],
      );
      final parts = result.split('_');
      expect(parts.length, 3);
      expect(parts[0].length, 10, reason: 'prefix is 10 chars');
      expect(parts[1].length, 12, reason: 'cipher hash is 12 chars');
      expect(parts[2].length, 12, reason: 'extensions hash is 12 chars');
    });

    test('deterministic: same input → same output', () {
      compute() => preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: [4865],
        extensions: [10, 11],
        signatureAlgorithms: [2052],
        alpnProtocols: ['h2'],
      );
      expect(compute(), compute());
    });
  });

  group('Reference vectors', () {
    test('TLS 1.3 Chrome-like profile', () {
      // Typical Chrome TLS 1.3 ciphers
      final ciphers = [4865, 4866, 4867]; // 1301, 1302, 1303
      final extensions = [
        0, // SNI – excluded from hash
        23, // 0x0017
        65281, // 0xff01
        10, // 0x000a
        11, // 0x000b
        35, // 0x0023
        16, // ALPN – excluded from hash
        5, // 0x0005
        13, // 0x000d
        51, // 0x0033
        45, // 0x002d
        43, // 0x002b
        21, // 0x0015
      ];
      final sigAlgs = [
        1027, // 0x0403
        2052, // 0x0804
        1025, // 0x0401
        1283, // 0x0503
        2053, // 0x0805
        1281, // 0x0501
      ];

      final result = preview.compute(
        tlsMaxVersion: '1.3',
        sniMode: 'present',
        cipherSuites: ciphers,
        extensions: extensions,
        signatureAlgorithms: sigAlgs,
        alpnProtocols: ['h2', 'http/1.1'],
      );

      // Verify prefix: t13d031302h2 (proto=t, ver=13, sni=d, 03 ciphers, 13 exts, alpn=h2)
      expect(result.substring(0, 10), 't13d0313h2');

      // Verify 3 sections
      final parts = result.split('_');
      expect(parts.length, 3);

      // Verify cipher hash: sorted [4865,4866,4867] → "1301,1302,1303"
      expect(parts[1], _sha256x12('1301,1302,1303'));

      // Extensions (sorted, minus SNI=0 and ALPN=16):
      // [5, 10, 11, 13, 21, 23, 35, 43, 45, 51, 65281]
      // hex: 0005,000a,000b,000d,0015,0017,0023,002b,002d,0033,ff01
      // sig algs hex: 0403,0804,0401,0503,0805,0501
      final extStr = '0005,000a,000b,000d,0015,0017,0023,002b,002d,0033,ff01';
      final sigStr = '0403,0804,0401,0503,0805,0501';
      expect(parts[2], _sha256x12('${extStr}_$sigStr'));
    });
  });
}
