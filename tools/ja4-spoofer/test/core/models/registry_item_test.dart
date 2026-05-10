import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/registry_item.dart';

void main() {
  group('RegistryItem', () {
    test('hex for id=0', () {
      const item = RegistryItem(id: 0, name: 'zero');
      expect(item.hex, '0x0000');
    });

    test('hex for id=4865 (0x1301)', () {
      const item = RegistryItem(id: 4865, name: 'TLS_AES_128_GCM_SHA256');
      expect(item.hex, '0x1301');
    });

    test('label format', () {
      const item = RegistryItem(id: 4865, name: 'TLS_AES_128_GCM_SHA256');
      expect(item.label, '4865  0x1301  TLS_AES_128_GCM_SHA256');
    });

    test('hex is uppercase', () {
      const item = RegistryItem(id: 0xabcd, name: 'test');
      expect(item.hex, '0xABCD');
    });
  });
}
