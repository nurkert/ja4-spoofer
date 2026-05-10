import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

import '../models/app_descriptor.dart';

/// Loads [AppDescriptor] definitions from:
/// 1. [bundledYamlContents] — pre-loaded asset strings (shipped defaults).
/// 2. ~/.ja4-spoofer/apps/*.yaml — user-defined overrides and additions.
///
/// User YAMLs override bundled ones with the same [AppDescriptor.appId].
///
/// When [repoRoot] is provided, relative launch-script paths in descriptors
/// are resolved against it. Build-script paths are resolved against
/// [buildRepoRoot] (a source checkout or writable packaged runtime containing
/// `scripts/`, `patches/`, and `configs/`).
class AppDescriptorService {
  AppDescriptorService({
    String? appsDir,
    List<String>? bundledYamlContents,
    this.repoRoot,
    this.buildRepoRoot,
  }) : appsDir = appsDir ?? _defaultAppsDir(),
       _bundledYamlContents = bundledYamlContents ?? const [];

  final String appsDir;
  final List<String> _bundledYamlContents;

  /// Root used to resolve relative **launch** script paths.
  /// Can be a source checkout or the packaged runtime directory.
  final String? repoRoot;

  /// Root used to resolve relative **build** script paths.
  /// Can be a source checkout or the packaged runtime directory.
  /// When `null`, build script paths stay relative (builds will show an error).
  final String? buildRepoRoot;

  static String _defaultAppsDir() {
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/.ja4-spoofer/apps';
  }

  Future<List<AppDescriptor>> loadAll() async {
    final descriptors = <AppDescriptor>[];

    // 1. Bundled asset YAMLs (shipped defaults)
    for (final content in _bundledYamlContents) {
      try {
        final parsed = _parseYaml(content);
        if (parsed != null) descriptors.add(parsed);
      } catch (e) {
        debugPrint('[AppDescriptorService] bundled YAML parse error: $e');
      }
    }

    // 2. User YAMLs override or add to bundled ones
    final dir = Directory(appsDir);
    if (dir.existsSync()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.yaml')) {
          try {
            final content = await entity.readAsString();
            final parsed = _parseYaml(content);
            if (parsed != null) {
              descriptors.removeWhere((d) => d.appId == parsed.appId);
              descriptors.add(parsed);
            }
          } catch (e) {
            debugPrint(
              '[AppDescriptorService] user YAML parse error (${entity.path}): $e',
            );
          }
        }
      }
    }

    return descriptors;
  }

  AppDescriptor? _parseYaml(String content) {
    final doc = loadYaml(content);
    if (doc is! YamlMap) return null;

    final meta = doc['metadata'] as YamlMap?;
    final build = doc['build'] as YamlMap?;
    final launch = doc['launch'] as YamlMap?;

    if (meta == null || build == null || launch == null) return null;

    final binaryPaths =
        (build['built_binary_paths'] as YamlList?)
            ?.map((e) => e.toString())
            .toList(growable: false) ??
        <String>[];

    final requirements = _parseRequirements(build['requirements'] as YamlList?);

    // Parse tls_defaults section
    final tlsDef = doc['tls_defaults'] as YamlMap?;
    final tlsDefaults = tlsDef != null
        ? AppTlsDefaults(
            tlsVersions:
                (tlsDef['tls_versions'] as YamlList?)
                    ?.map((e) => e.toString())
                    .toList(growable: false) ??
                const [],
            cipherSuites:
                (tlsDef['cipher_suites'] as YamlList?)
                    ?.map((e) => (e as num).toInt())
                    .toList(growable: false) ??
                const [],
            extensions:
                (tlsDef['extensions'] as YamlList?)
                    ?.map((e) => (e as num).toInt())
                    .toList(growable: false) ??
                const [],
            signatureAlgorithms:
                (tlsDef['signature_algorithms'] as YamlList?)
                    ?.map((e) => (e as num).toInt())
                    .toList(growable: false) ??
                const [],
            alpnProtocols:
                (tlsDef['alpn_protocols'] as YamlList?)
                    ?.map((e) => e.toString())
                    .toList(growable: false) ??
                const [],
          )
        : const AppTlsDefaults();

    final runtime = launch['runtime'] as YamlMap?;
    final runtimeKindName = runtime?['kind'] as String? ?? 'gui';
    final runtimeKind = switch (runtimeKindName) {
      'cli' => AppRuntimeKind.cli,
      _ => AppRuntimeKind.gui,
    };

    return AppDescriptor(
      appId: doc['app_id'] as String? ?? 'unknown',
      metadata: AppDescriptorMetadata(
        name: meta['name'] as String? ?? 'Unknown App',
        description: meta['description'] as String?,
        iconUrl: meta['icon_url'] as String?,
      ),
      build: AppBuildConfig(
        script:
            _resolvePath(
              build['script'] as String? ?? '',
              root: buildRepoRoot,
            ) ??
            '',
        sslOnlyScript: _resolvePath(
          build['ssl_only_script'] as String?,
          root: buildRepoRoot,
        ),
        builtBinaryPaths: binaryPaths,
        requirements: requirements,
      ),
      launch: AppLaunchConfig(
        script: _resolvePath(launch['script'] as String? ?? '') ?? '',
        profileFormat: launch['profile_format'] as String? ?? 'nss',
        dumpPath: launch['dump_path'] as String?,
        runtime: AppLaunchRuntimeConfig(
          kind: runtimeKind,
          argsPlaceholder: runtime?['args_placeholder'] as String?,
          argsExample: runtime?['args_example'] as String?,
          passUserArgsAfterDoubleDash:
              runtime?['pass_user_args_after_double_dash'] as bool? ?? false,
        ),
      ),
      tlsDefaults: tlsDefaults,
    );
  }

  List<BuildRequirement> _parseRequirements(YamlList? raw) {
    if (raw == null) return const <BuildRequirement>[];

    final parsed = <BuildRequirement>[];
    for (final entry in raw) {
      if (entry is YamlMap) {
        final name = _firstNonEmptyString([
          entry['name'],
          entry['tool'],
          entry['id'],
        ]);
        final version = _nullableTrimmedString(entry['version']);
        final hint = _nullableTrimmedString(entry['hint']);

        if (name == null && version == null && hint == null) {
          continue;
        }
        parsed.add(
          BuildRequirement(
            name: name ?? 'Requirement',
            version: version,
            hint: hint,
          ),
        );
        continue;
      }

      final scalar = entry.toString().trim();
      if (scalar.isEmpty || scalar == 'null') continue;
      parsed.add(BuildRequirement(name: scalar));
    }
    return parsed;
  }

  String? _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final text = _nullableTrimmedString(value);
      if (text != null) return text;
    }
    return null;
  }

  String? _nullableTrimmedString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  /// Resolves [path] against [root] (defaulting to [repoRoot]) if relative.
  /// Absolute paths (starting with `/`) and home-relative paths (starting
  /// with `~/`) are returned as-is. Returns `null` if [path] is null.
  String? _resolvePath(String? path, {String? root}) {
    if (path == null) return null;
    if (path.isEmpty) return path;
    root ??= repoRoot;
    if (root == null) return path;
    if (path.startsWith('/') || path.startsWith('~/')) return path;
    return '$root/$path';
  }
}
