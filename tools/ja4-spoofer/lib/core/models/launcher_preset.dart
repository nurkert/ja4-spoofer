/// Immutable preset definition used by the launcher UI.
class LauncherPreset {
  const LauncherPreset({
    required this.id,
    required this.label,
    required this.profileDir,
    required this.tlsMin,
    required this.tlsMax,
    required this.enableGrease,
    required this.enablePermutation,
    required this.cipherSuites,
    required this.alpn,
    required this.signatureAlgorithms,
    required this.extensionOrder,
    required this.sniMode,
    required this.targetUrl,
  });

  final String id;
  final String label;
  final String profileDir;
  final String tlsMin;
  final String tlsMax;
  final String enableGrease;
  final String enablePermutation;
  final List<int> cipherSuites;
  final List<String> alpn;
  final List<int> signatureAlgorithms;
  final List<int> extensionOrder;
  final String sniMode;
  final String targetUrl;
}

/// Presets mirrored from the original web UI / shell commands.
const defaultLauncherPresets = <LauncherPreset>[
  LauncherPreset(
    id: 'nss_defaultish',
    label: 'Preset: baseline (deterministic)',
    profileDir: '/tmp/ja4-clean-profile',
    tlsMin: '1.2',
    tlsMax: '1.3',
    enableGrease: '0',
    enablePermutation: '0',
    cipherSuites: [4865, 4867, 4866, 49195, 49199],
    alpn: ['h2', 'http/1.1'],
    signatureAlgorithms: [1027, 1283, 1539, 2052, 2053],
    extensionOrder: [
      0,
      23,
      65281,
      10,
      11,
      35,
      16,
      5,
      34,
      18,
      51,
      43,
      13,
      45,
      28,
    ],
    sniMode: 'present',
    targetUrl: 'https://example.com',
  ),
  LauncherPreset(
    id: 'maxdiff',
    label: 'Preset: maxdiff',
    profileDir: '/tmp/ja4-maxdiff-profile',
    tlsMin: '1.3',
    tlsMax: '1.3',
    enableGrease: '0',
    enablePermutation: '0',
    cipherSuites: [4867, 4866, 4865, 49195, 49199, 49196, 49200],
    alpn: ['http/1.1'],
    signatureAlgorithms: [2052, 2053, 2054, 1539, 1283, 1027, 1025],
    extensionOrder: [0, 43, 10, 13, 16, 45, 51, 23, 11, 5, 34, 18, 28, 65281],
    sniMode: 'present',
    targetUrl: 'https://example.com',
  ),
];
