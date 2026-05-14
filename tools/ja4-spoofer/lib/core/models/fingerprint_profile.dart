import 'package:flutter/foundation.dart';

import '../utils/atomic_file.dart';

/// Metadata attached to a stored fingerprint profile.
@immutable
class FingerprintProfileMetadata {
  const FingerprintProfileMetadata({
    required this.name,
    this.source = 'manual',
    this.capturedAt,
    this.userAgent,
    this.profileFormat,
    this.iconUrl,
    this.version,
  });

  final String name;

  /// Source of the profile: "manual", "captured", "imported".
  final String source;
  final DateTime? capturedAt;
  final String? userAgent;

  /// Which SSL library this profile was crafted for: "nss", "boringssl", or null (universal).
  final String? profileFormat;

  /// Optional URL to an icon/logo image for this profile.
  final String? iconUrl;

  /// Optional version string (e.g. "18.2", "133.0").
  final String? version;

  Map<String, dynamic> toJson() => {
    'name': name,
    'source': source,
    if (capturedAt != null) 'captured_at': capturedAt!.toIso8601String(),
    if (userAgent != null) 'user_agent': userAgent,
    if (profileFormat != null) 'profile_format': profileFormat,
    if (iconUrl != null) 'icon_url': iconUrl,
    if (version != null) 'version': version,
  };

  factory FingerprintProfileMetadata.fromJson(Map<String, dynamic> json) {
    return FingerprintProfileMetadata(
      name: json['name'] as String? ?? 'Unnamed',
      source: json['source'] as String? ?? 'manual',
      capturedAt: json['captured_at'] != null
          ? DateTime.tryParse(json['captured_at'] as String)
          : null,
      userAgent: json['user_agent'] as String?,
      profileFormat: json['profile_format'] as String?,
      iconUrl: json['icon_url'] as String?,
      version: json['version'] as String?,
    );
  }

  FingerprintProfileMetadata copyWith({
    String? name,
    String? source,
    DateTime? capturedAt,
    String? userAgent,
    String? profileFormat,
    String? iconUrl,
    String? version,
  }) {
    return FingerprintProfileMetadata(
      name: name ?? this.name,
      source: source ?? this.source,
      capturedAt: capturedAt ?? this.capturedAt,
      userAgent: userAgent ?? this.userAgent,
      profileFormat: profileFormat ?? this.profileFormat,
      iconUrl: iconUrl ?? this.iconUrl,
      version: version ?? this.version,
    );
  }
}

/// TLS Client Hello inputs — the "inputs" section of FCS JSON.
@immutable
class TlsClientHelloInputs {
  const TlsClientHelloInputs({
    this.tlsMinVersion = '1.2',
    this.tlsMaxVersion = '1.3',
    this.cipherSuites = const [],
    this.alpnProtocols = const [],
    this.extensions = const [],
    this.signatureAlgorithms = const [],
    this.supportedVersions = const [],
    this.supportedGroups = const [],
    this.keyShareGroups = const [],
    this.pskKeyExchangeModes = const [],
    this.enableGrease = false,
    this.enableChXtnPermutation = false,
    this.sniMode = 'present',
    this.cipherMode,
    this.extensionMode,
  });

  final String tlsMinVersion;
  final String tlsMaxVersion;
  final List<int> cipherSuites;
  final List<String> alpnProtocols;
  final List<int> extensions;
  final List<int> signatureAlgorithms;
  final List<int> supportedVersions;
  final List<int> supportedGroups;
  final List<int> keyShareGroups;
  final List<int> pskKeyExchangeModes;
  final bool enableGrease;
  final bool enableChXtnPermutation;
  final String sniMode;
  final String? cipherMode;
  final String? extensionMode;

  TlsClientHelloInputs copyWith({
    String? tlsMinVersion,
    String? tlsMaxVersion,
    List<int>? cipherSuites,
    List<String>? alpnProtocols,
    List<int>? extensions,
    List<int>? signatureAlgorithms,
    List<int>? supportedVersions,
    List<int>? supportedGroups,
    List<int>? keyShareGroups,
    List<int>? pskKeyExchangeModes,
    bool? enableGrease,
    bool? enableChXtnPermutation,
    String? sniMode,
    String? cipherMode,
    String? extensionMode,
  }) {
    return TlsClientHelloInputs(
      tlsMinVersion: tlsMinVersion ?? this.tlsMinVersion,
      tlsMaxVersion: tlsMaxVersion ?? this.tlsMaxVersion,
      cipherSuites: cipherSuites ?? this.cipherSuites,
      alpnProtocols: alpnProtocols ?? this.alpnProtocols,
      extensions: extensions ?? this.extensions,
      signatureAlgorithms: signatureAlgorithms ?? this.signatureAlgorithms,
      supportedVersions: supportedVersions ?? this.supportedVersions,
      supportedGroups: supportedGroups ?? this.supportedGroups,
      keyShareGroups: keyShareGroups ?? this.keyShareGroups,
      pskKeyExchangeModes: pskKeyExchangeModes ?? this.pskKeyExchangeModes,
      enableGrease: enableGrease ?? this.enableGrease,
      enableChXtnPermutation:
          enableChXtnPermutation ?? this.enableChXtnPermutation,
      sniMode: sniMode ?? this.sniMode,
      cipherMode: cipherMode ?? this.cipherMode,
      extensionMode: extensionMode ?? this.extensionMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'tls_min_version': tlsMinVersion,
    'tls_max_version': tlsMaxVersion,
    'cipher_suites': cipherSuites,
    'alpn_protocols': alpnProtocols,
    'extensions': extensions,
    'signature_algorithms': signatureAlgorithms,
    'supported_versions': supportedVersions,
    'supported_groups': supportedGroups,
    'key_share_groups': keyShareGroups,
    'psk_key_exchange_modes': pskKeyExchangeModes,
    'enable_grease': enableGrease,
    'enable_ch_xtn_permutation': enableChXtnPermutation,
    'sni_mode': sniMode,
    if (cipherMode != null) 'cipher_mode': cipherMode,
    if (extensionMode != null) 'extension_mode': extensionMode,
  };

  factory TlsClientHelloInputs.fromJson(Map<String, dynamic> json) {
    return TlsClientHelloInputs(
      tlsMinVersion: json['tls_min_version'] as String? ?? '1.2',
      tlsMaxVersion: json['tls_max_version'] as String? ?? '1.3',
      cipherSuites: _toIntList(json['cipher_suites']),
      alpnProtocols: _toStringList(json['alpn_protocols']),
      extensions: _toIntList(json['extensions']),
      signatureAlgorithms: _toIntList(json['signature_algorithms']),
      supportedVersions: _toIntList(json['supported_versions']),
      supportedGroups: _toIntList(json['supported_groups']),
      keyShareGroups: _toIntList(json['key_share_groups']),
      pskKeyExchangeModes: _toIntList(json['psk_key_exchange_modes']),
      enableGrease: json['enable_grease'] as bool? ?? false,
      enableChXtnPermutation:
          json['enable_ch_xtn_permutation'] as bool? ?? false,
      sniMode: json['sni_mode'] as String? ?? 'present',
      cipherMode: _toOptionalMode(json['cipher_mode']),
      extensionMode: _toOptionalMode(json['extension_mode']),
    );
  }
}

/// A stored fingerprint profile in FCS JSON format.
@immutable
class FingerprintProfile {
  const FingerprintProfile({
    required this.profileId,
    required this.metadata,
    required this.inputs,
    this.isBuiltIn = false,
  });

  final String profileId;
  final FingerprintProfileMetadata metadata;
  final TlsClientHelloInputs inputs;

  /// Whether this is an immutable built-in default profile.
  final bool isBuiltIn;

  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'profile_id': profileId,
    'metadata': metadata.toJson(),
    'inputs': {'tls_client_hello': inputs.toJson()},
  };

  factory FingerprintProfile.fromJson(Map<String, dynamic> json) {
    final inputs = json['inputs'] as Map<String, dynamic>? ?? {};
    final tlsJson = inputs['tls_client_hello'] as Map<String, dynamic>? ?? {};
    final meta = json['metadata'] as Map<String, dynamic>? ?? {};
    return FingerprintProfile(
      // Reject any ID that contains separators or shell metachars before it
      // can be used as a filename; protects ProfileService.save/delete
      // against `../escape` and similar path-traversal payloads in imports.
      profileId: sanitizeProfileId(json['profile_id'] as String? ?? ''),
      metadata: FingerprintProfileMetadata.fromJson(meta),
      inputs: TlsClientHelloInputs.fromJson(tlsJson),
    );
  }
}

List<int> _toIntList(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) return raw.map((e) => (e as num).toInt()).toList();
  return [];
}

List<String> _toStringList(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) return raw.map((e) => e.toString()).toList();
  return [];
}

String? _toOptionalMode(dynamic raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}
