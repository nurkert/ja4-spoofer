import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/models/capture_record.dart';

void main() {
  group('CaptureRecord.fromJson', () {
    test('all fields present', () {
      final r = CaptureRecord.fromJson({
        'captured_at': '2024-06-01T12:00:00.000Z',
        'ja4': 't13d1234h2_abc_def_ghi',
        'user_agent': 'Mozilla/5.0',
        'extra': 'data',
      });
      expect(r.capturedAt, DateTime.utc(2024, 6, 1, 12));
      expect(r.ja4Hash, 't13d1234h2_abc_def_ghi');
      expect(r.userAgent, 'Mozilla/5.0');
      expect(r.rawData['extra'], 'data');
    });

    test('missing captured_at → falls back to DateTime.now() (no throw)', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final r = CaptureRecord.fromJson({'ja4': 'hash'});
      expect(r.capturedAt.isAfter(before), isTrue);
    });

    test('uses ja4_hash key when ja4 is absent', () {
      final r = CaptureRecord.fromJson({'ja4_hash': 'alt-hash'});
      expect(r.ja4Hash, 'alt-hash');
    });

    test('missing both ja4 keys → em dash', () {
      final r = CaptureRecord.fromJson({});
      expect(r.ja4Hash, '—');
    });
  });

  group('CaptureRecord.toJson', () {
    test('omits user_agent when null', () {
      final r = CaptureRecord(capturedAt: DateTime.utc(1970), ja4Hash: 'hash');
      final j = r.toJson();
      expect(j.containsKey('user_agent'), isFalse);
    });

    test('spreads rawData into the map', () {
      final r = CaptureRecord(
        capturedAt: DateTime.utc(1970),
        ja4Hash: 'hash',
        rawData: const {'foo': 'bar', 'num': 42},
      );
      final j = r.toJson();
      expect(j['foo'], 'bar');
      expect(j['num'], 42);
    });
  });
}
