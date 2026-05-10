import 'package:flutter/foundation.dart';

/// Metadata section of an AppDescriptor.
@immutable
class AppDescriptorMetadata {
  const AppDescriptorMetadata({
    required this.name,
    this.description,
    this.iconUrl,
  });

  final String name;
  final String? description;
  final String? iconUrl;
}

/// A single build requirement (tool, version constraint, install hint).
@immutable
class BuildRequirement {
  const BuildRequirement({required this.name, this.version, this.hint});

  /// Tool or dependency name (e.g. "python", "Xcode").
  final String name;

  /// Version constraint (e.g. "<= 3.12", ">= 4").
  final String? version;

  /// Human-readable install/fix hint.
  final String? hint;

  @override
  String toString() {
    final buf = StringBuffer(name);
    if (version != null) buf.write(' $version');
    if (hint != null) buf.write(' — $hint');
    return buf.toString();
  }
}

/// Build configuration for an AppDescriptor.
@immutable
class AppBuildConfig {
  const AppBuildConfig({
    required this.script,
    required this.builtBinaryPaths,
    this.sslOnlyScript,
    this.requirements = const [],
  });

  /// Relative path from the source checkout or packaged runtime to the full
  /// build script.
  final String script;

  /// Optional script to build only the SSL library (faster, skips the browser).
  final String? sslOnlyScript;

  /// Ordered list of binary paths to probe for "already built" detection.
  /// First existing path wins.
  final List<String> builtBinaryPaths;

  /// System requirements for building (shown in GUI and checked by scripts).
  final List<BuildRequirement> requirements;
}

/// Launch configuration for an AppDescriptor.
@immutable
class AppLaunchRuntimeConfig {
  const AppLaunchRuntimeConfig({
    this.kind = AppRuntimeKind.gui,
    this.argsPlaceholder,
    this.argsExample,
    this.passUserArgsAfterDoubleDash = false,
  });

  final AppRuntimeKind kind;
  final String? argsPlaceholder;
  final String? argsExample;
  final bool passUserArgsAfterDoubleDash;

  bool get isCli => kind == AppRuntimeKind.cli;
}

enum AppRuntimeKind { gui, cli }

@immutable
class AppLaunchConfig {
  const AppLaunchConfig({
    required this.script,
    required this.profileFormat,
    this.dumpPath,
    this.runtime = const AppLaunchRuntimeConfig(),
  });

  /// Relative path from the source checkout or packaged runtime to the launch
  /// script.
  final String script;

  /// Identifies which config format the launcher expects (e.g. "nss").
  final String profileFormat;

  /// Path where the effective config dump is written.
  final String? dumpPath;

  /// Runtime-specific UI hints, such as CLI argument input.
  final AppLaunchRuntimeConfig runtime;
}

/// TLS defaults declaring which cipher suites, extensions, etc. an SSL
/// library supports. Used for profile compatibility checks.
@immutable
class AppTlsDefaults {
  const AppTlsDefaults({
    this.tlsVersions = const [],
    this.cipherSuites = const [],
    this.extensions = const [],
    this.signatureAlgorithms = const [],
    this.alpnProtocols = const [],
  });

  final List<String> tlsVersions;
  final List<int> cipherSuites;
  final List<int> extensions;
  final List<int> signatureAlgorithms;
  final List<String> alpnProtocols;

  bool get isEmpty =>
      tlsVersions.isEmpty &&
      cipherSuites.isEmpty &&
      extensions.isEmpty &&
      signatureAlgorithms.isEmpty &&
      alpnProtocols.isEmpty;
}

/// Describes a launchable application in the App Launcher feature.
///
/// Loaded from ~/.ja4-spoofer/apps/[id].yaml or built-in defaults.
@immutable
class AppDescriptor {
  const AppDescriptor({
    required this.appId,
    required this.metadata,
    required this.build,
    required this.launch,
    this.tlsDefaults = const AppTlsDefaults(),
  });

  final String appId;
  final AppDescriptorMetadata metadata;
  final AppBuildConfig build;
  final AppLaunchConfig launch;
  final AppTlsDefaults tlsDefaults;
}
