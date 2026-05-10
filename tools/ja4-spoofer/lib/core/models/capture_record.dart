import 'fingerprint_profile.dart';

/// A single JA4 capture event received by the capture server.
///
/// When deduplication is active, multiple captures with the same JA4 hash
/// within a time window are grouped: [count] tracks how many raw captures
/// this record represents and [lastSeenAt] is the timestamp of the most
/// recent one.
class CaptureRecord {
  const CaptureRecord({
    required this.capturedAt,
    required this.ja4Hash,
    this.userAgent,
    this.rawData = const {},
    this.tlsInputs,
    this.sni,
    this.sourceAddress,
    this.count = 1,
    this.lastSeenAt,
  });

  final DateTime capturedAt;
  final String ja4Hash;
  final String? userAgent;
  final Map<String, dynamic> rawData;

  /// Parsed TLS ClientHello inputs (populated by TLS sniffer captures).
  final TlsClientHelloInputs? tlsInputs;

  /// SNI hostname from the ClientHello (if present).
  final String? sni;

  /// Remote address of the captured client.
  final String? sourceAddress;

  /// Number of raw captures grouped into this record (deduplication).
  final int count;

  /// Timestamp of the most recent capture in this group.
  final DateTime? lastSeenAt;

  /// Returns a copy with an incremented count and updated [lastSeenAt].
  CaptureRecord copyWithIncrement({required DateTime lastSeenAt}) {
    return CaptureRecord(
      capturedAt: capturedAt,
      ja4Hash: ja4Hash,
      userAgent: userAgent,
      rawData: rawData,
      tlsInputs: tlsInputs,
      sni: sni,
      sourceAddress: sourceAddress,
      count: count + 1,
      lastSeenAt: lastSeenAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'captured_at': capturedAt.toIso8601String(),
    'ja4': ja4Hash,
    if (userAgent != null) 'user_agent': userAgent,
    if (sni != null) 'sni': sni,
    if (sourceAddress != null) 'source_address': sourceAddress,
    if (tlsInputs != null) 'tls_inputs': tlsInputs!.toJson(),
    if (count > 1) 'count': count,
    if (lastSeenAt != null) 'last_seen_at': lastSeenAt!.toIso8601String(),
    ...rawData,
  };

  factory CaptureRecord.fromJson(Map<String, dynamic> json) {
    final raw = Map<String, dynamic>.from(json);
    final tlsJson = json['tls_inputs'] as Map<String, dynamic>?;
    return CaptureRecord(
      capturedAt: json['captured_at'] != null
          ? DateTime.tryParse(json['captured_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      ja4Hash: json['ja4'] as String? ?? json['ja4_hash'] as String? ?? '—',
      userAgent: json['user_agent'] as String?,
      sni: json['sni'] as String?,
      sourceAddress: json['source_address'] as String?,
      tlsInputs: tlsJson != null
          ? TlsClientHelloInputs.fromJson(tlsJson)
          : null,
      rawData: raw,
      count: json['count'] as int? ?? 1,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'] as String)
          : null,
    );
  }
}
