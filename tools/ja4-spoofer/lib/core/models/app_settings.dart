import 'package:flutter/foundation.dart';

/// Where the GUI sources IANA TLS registry data from.
///
/// Drives every place numeric TLS IDs (cipher suites, extensions,
/// signature schemes) are resolved to human-readable names —
/// configurator picker, capture detail, profile-library compatibility.
enum IanaSource {
  /// Use the bundled offline CSV snapshot in `assets/iana/`. No network.
  bundled,

  /// Fetch fresh CSVs from iana.org on first use. Falls back to bundled
  /// snapshot when the network is unavailable.
  online,

  /// Skip name resolution entirely; show hex IDs only. No network, no
  /// asset read. The configurator picker's selectable list still uses
  /// the small hardcoded fallback (so you can still build profiles).
  disabled,
}

IanaSource _parseIanaSource(String? raw) {
  switch (raw) {
    case 'online':
      return IanaSource.online;
    case 'disabled':
      return IanaSource.disabled;
    case 'bundled':
      return IanaSource.bundled;
    default:
      return IanaSource.bundled;
  }
}

String _ianaSourceToString(IanaSource source) {
  switch (source) {
    case IanaSource.bundled:
      return 'bundled';
    case IanaSource.online:
      return 'online';
    case IanaSource.disabled:
      return 'disabled';
  }
}

/// Persistent application settings for JA4 Spoofer.
///
/// Deep-dive launch flags (target URL, custom script path, custom profile
/// directory, --dump, --dry-run, --show-config, --set, extra browser args,
/// existing-process mode, …) used to live here under a "Launch Defaults"
/// section. They have been removed from the GUI: power users invoke the
/// shell scripts directly. See `docs/advanced-launch.md`.
@immutable
class AppSettings {
  const AppSettings({
    this.repoPath,
    this.quickLaunchProfileId,
    this.ianaSource = IanaSource.bundled,
    this.loadRemoteIcons = true,
  });

  static const _sentinel = Object();

  /// Optional source checkout override for local development. Installed
  /// packages normally use the bundled runtime under ~/.ja4-spoofer.
  final String? repoPath;

  /// Last selected profile ID in Quick Launch.
  final String? quickLaunchProfileId;

  /// Where IANA registry data comes from. `bundled` is the default and
  /// covers the common case (offline-friendly + named IDs). `online`
  /// pulls fresh CSVs from iana.org. `disabled` shows hex only.
  final IanaSource ianaSource;

  /// Whether to load remote profile and app icons over the network.
  /// When `false`, all icon widgets render nothing (no placeholders) and
  /// no HTTP request is issued for icon URLs.
  final bool loadRemoteIcons;

  /// Convenience: any source other than `disabled` resolves names.
  bool get resolvesIanaNames => ianaSource != IanaSource.disabled;

  /// Pass [_sentinel] (the default) to keep the existing value.
  /// Pass `null` explicitly to clear a nullable field.
  AppSettings copyWith({
    Object? repoPath = _sentinel,
    Object? quickLaunchProfileId = _sentinel,
    IanaSource? ianaSource,
    bool? loadRemoteIcons,
  }) {
    return AppSettings(
      repoPath: identical(repoPath, _sentinel)
          ? this.repoPath
          : repoPath as String?,
      quickLaunchProfileId: identical(quickLaunchProfileId, _sentinel)
          ? this.quickLaunchProfileId
          : quickLaunchProfileId as String?,
      ianaSource: ianaSource ?? this.ianaSource,
      loadRemoteIcons: loadRemoteIcons ?? this.loadRemoteIcons,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final IanaSource source;
    if (json.containsKey('iana_source')) {
      source = _parseIanaSource(json['iana_source'] as String?);
    } else if (json.containsKey('show_iana_names')) {
      // Legacy boolean: true → online (user opted into fetching), false →
      // disabled (user opted out of resolution). New "bundled" default
      // only applies to fresh installs.
      source = (json['show_iana_names'] as bool? ?? false)
          ? IanaSource.online
          : IanaSource.disabled;
    } else {
      source = IanaSource.bundled;
    }
    return AppSettings(
      repoPath: json['repo_path'] as String?,
      quickLaunchProfileId: json['quick_launch_profile_id'] as String?,
      ianaSource: source,
      loadRemoteIcons: json['load_remote_icons'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    if (repoPath != null) 'repo_path': repoPath,
    if (quickLaunchProfileId != null)
      'quick_launch_profile_id': quickLaunchProfileId,
    'iana_source': _ianaSourceToString(ianaSource),
    'load_remote_icons': loadRemoteIcons,
  };
}
