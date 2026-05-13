import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/controllers/profile_catalog_controller.dart';
import '../../core/models/fingerprint_profile.dart';
import '../../core/services/app_descriptor_service.dart';
import '../../core/services/patch_service.dart';
import '../../core/services/script_bundle_service.dart';
import '../../features/app_launcher/app_launcher_controller.dart';
import '../../features/configurator/configurator_controller.dart';
import '../../features/configurator/configurator_page.dart';
import '../../features/ja4_capture/ja4_capture_page.dart';
import '../../features/profile_library/profile_library_controller.dart';
import '../../features/profile_library/profile_library_page.dart';
import '../../features/quick_launch/quick_launch_controller.dart';
import '../../features/quick_launch/quick_launch_page.dart';
import '../../features/settings/settings_controller.dart';
import '../../features/settings/settings_page.dart';
import 'nav_item.dart';
import 'settings_scope.dart';

final _navEntries = <({String route, IconData icon, String label})>[
  (route: '/quick', icon: LucideIcons.zap, label: 'Launch'),
  (
    route: '/configurator',
    icon: LucideIcons.slidersHorizontal,
    label: 'TLS Configurator',
  ),
  (route: '/profiles', icon: LucideIcons.library, label: 'Profile Library'),
  (route: '/capture', icon: LucideIcons.radio, label: 'JA4 Capture'),
];

class _NavigateIntent extends Intent {
  const _NavigateIntent(this.route);
  final String route;
}

/// Root layout widget: sidebar + content area.
///
/// Navigation is managed via a [ValueNotifier<String>] — no router needed.
/// All shared controllers are created here and passed to pages via constructors.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _currentRoute = ValueNotifier<String>('/quick');
  bool _sidebarCollapsed = false;

  /// Shared controllers — null while initializing.
  AppLauncherController? _launcherController;
  SettingsController? _settingsController;
  ConfiguratorController? _configuratorController;
  QuickLaunchController? _quickLaunchController;
  ProfileCatalogController? _profileCatalogController;
  ProfileLibraryController? _profileLibraryController;

  /// Re-entry guard for [_initControllers]. Settings-save triggers a re-init
  /// (see [_buildPage] '/settings'); without this, a rapid toggle would
  /// start a second `_initControllers` while the first is still inside
  /// `ScriptBundleService.ensureExtracted()`, leaving both racing on
  /// `dispose()` and `setState`.
  bool _initInProgress = false;

  void _reportInitError(Object error, [StackTrace? stack]) {
    debugPrint('AppShell init failure: $error');
    if (stack != null) debugPrintStack(stackTrace: stack);
    if (!mounted) return;
    ShadSonner.of(context).show(
      ShadToast.destructive(description: Text('Initialisation failed: $error')),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initControllers());
  }

  Future<void> _initControllers() async {
    if (_initInProgress) return;
    _initInProgress = true;
    try {
      await _initControllersUnchecked();
    } catch (e, st) {
      _reportInitError(e, st);
    } finally {
      _initInProgress = false;
    }
  }

  Future<void> _initControllersUnchecked() async {
    _quickLaunchController?.dispose();
    _profileLibraryController?.dispose();
    _profileCatalogController?.dispose();
    _configuratorController?.dispose();
    _launcherController?.dispose();

    // 1. Settings controller — kept alive across re-inits because it is
    // also held by SettingsScope and SettingsPage; disposing it would
    // crash any toggle the user flips during a re-init pass.
    final settingsController = _settingsController ?? SettingsController();
    await settingsController.load();

    // 2. Load bundled YAML assets
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final descriptorKeys = assetManifest
        .listAssets()
        .where(
          (k) => k.startsWith('assets/descriptors/') && k.endsWith('.yaml'),
        )
        .toList();
    final yamls = await Future.wait(
      descriptorKeys.map((k) => rootBundle.loadString(k)),
    );

    // Resolve runtime roots for script and build paths.
    //
    // Source checkout (Settings or local auto-discovery) wins for development.
    // Installed packages fall back to the writable bundled runtime under
    // ~/.ja4-spoofer/runtime/<version>, which mirrors the repository layout.
    final settings = settingsController.settings;

    final configuredRepoRoot = settings.repoPath;
    String? runtimeRoot;
    if (configuredRepoRoot != null &&
        Directory('$configuredRepoRoot/scripts').existsSync() &&
        Directory('$configuredRepoRoot/patches').existsSync()) {
      runtimeRoot = configuredRepoRoot;
    } else {
      final discoveredRepoRoot = PatchService.discoverRepoRoot();
      if (discoveredRepoRoot != null &&
          Directory('$discoveredRepoRoot/scripts').existsSync() &&
          Directory('$discoveredRepoRoot/patches').existsSync()) {
        runtimeRoot = discoveredRepoRoot;
      }
    }

    runtimeRoot ??= await ScriptBundleService().ensureExtracted();

    if (!mounted) return;

    // 3. AppLauncherController
    final launcherController = AppLauncherController(
      descriptorService: AppDescriptorService(
        bundledYamlContents: yamls,
        repoRoot: runtimeRoot,
        buildRepoRoot: runtimeRoot,
      ),
      repoRoot: runtimeRoot,
    );

    // 4. ConfiguratorController — single source of truth for TLS config
    final configuratorController = ConfiguratorController();
    final profileCatalogController = ProfileCatalogController();
    final profileLibraryController = ProfileLibraryController(
      profileCatalogController: profileCatalogController,
    );

    setState(() {
      _settingsController = settingsController;
      _launcherController = launcherController;
      _configuratorController = configuratorController;
      _profileCatalogController = profileCatalogController;
      _profileLibraryController = profileLibraryController;
    });

    unawaited(
      launcherController
          .loadApps()
          .then((_) {
            if (!mounted) return;
            // 5. QuickLaunchController — after apps are loaded
            final quickLaunchController = QuickLaunchController(
              apps: launcherController.apps,
              configuratorController: configuratorController,
              profileCatalogController: profileCatalogController,
            );
            setState(() => _quickLaunchController = quickLaunchController);
            unawaited(
              profileCatalogController
                  .load()
                  .then((_) {
                    if (!mounted) return Future<void>.value();
                    return quickLaunchController
                        .restoreSelectionIntoConfigurator();
                  })
                  .catchError((Object e, StackTrace st) {
                    _reportInitError(e, st);
                  }),
            );
          })
          .catchError((Object e, StackTrace st) {
            _reportInitError(e, st);
          }),
    );

    // Load registries once here, not on every tab visit. Honour the
    // ianaSource privacy choice: bundled snapshot, online fetch, or off.
    unawaited(
      configuratorController
          .loadRegistries(source: settingsController.settings.ianaSource)
          .catchError((Object e, StackTrace st) {
            _reportInitError(e, st);
          }),
    );
  }

  @override
  void dispose() {
    _quickLaunchController?.dispose();
    _profileLibraryController?.dispose();
    _profileCatalogController?.dispose();
    _configuratorController?.dispose();
    _settingsController?.dispose();
    _launcherController?.dispose();
    _currentRoute.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final sidebarWidth = _sidebarCollapsed ? 60.0 : 220.0;

    return Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true):
            const _NavigateIntent('/quick'),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true):
            const _NavigateIntent('/configurator'),
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true):
            const _NavigateIntent('/profiles'),
        const SingleActivator(LogicalKeyboardKey.digit4, meta: true):
            const _NavigateIntent('/capture'),
      },
      child: Actions(
        actions: {
          _NavigateIntent: CallbackAction<_NavigateIntent>(
            onInvoke: (intent) {
              _currentRoute.value = intent.route;
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sidebar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  width: sidebarWidth,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: theme.colorScheme.border),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 170;
                          final showCompactHeader =
                              _sidebarCollapsed || isNarrow;
                          if (showCompactHeader) {
                            return GestureDetector(
                              onTap: _sidebarCollapsed
                                  ? () => setState(
                                      () => _sidebarCollapsed = false,
                                    )
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: Center(
                                  child: Icon(
                                    LucideIcons.shield,
                                    size: 18,
                                    color: theme.colorScheme.foreground,
                                  ),
                                ),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(14, 16, 8, 12),
                            child: Row(
                              children: [
                                const Icon(LucideIcons.shield, size: 18),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'JA4 Spoofer',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () =>
                                      setState(() => _sidebarCollapsed = true),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      LucideIcons.chevronsLeft,
                                      size: 16,
                                      color: theme.colorScheme.mutedForeground,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const ShadSeparator.horizontal(),
                      const SizedBox(height: 8),
                      // Nav items (main)
                      Expanded(
                        child: ValueListenableBuilder<String>(
                          valueListenable: _currentRoute,
                          builder: (context, route, _) {
                            return ListView(
                              shrinkWrap: true,
                              children: _navEntries
                                  .asMap()
                                  .entries
                                  .map((entry) {
                                    final idx = entry.key;
                                    final nav = entry.value;
                                    return NavItem(
                                      icon: nav.icon,
                                      label: nav.label,
                                      route: nav.route,
                                      currentRoute: route,
                                      onTap: () =>
                                          _currentRoute.value = nav.route,
                                      collapsed: _sidebarCollapsed,
                                      shortcutHint: _sidebarCollapsed
                                          ? null
                                          : '\u2318${idx + 1}',
                                    );
                                  })
                                  .toList(growable: false),
                            );
                          },
                        ),
                      ),
                      const ShadSeparator.horizontal(),
                      // Settings at bottom
                      ValueListenableBuilder<String>(
                        valueListenable: _currentRoute,
                        builder: (context, route, _) {
                          return NavItem(
                            icon: LucideIcons.settings,
                            label: 'Settings',
                            route: '/settings',
                            currentRoute: route,
                            onTap: () => _currentRoute.value = '/settings',
                            collapsed: _sidebarCollapsed,
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                // Content area
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final sc = _settingsController;
                      final routedContent = ValueListenableBuilder<String>(
                        valueListenable: _currentRoute,
                        builder: (context, route, _) => _buildPage(route),
                      );
                      if (sc == null) return routedContent;
                      return SettingsScope(
                        controller: sc,
                        child: routedContent,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(String route) {
    final lc = _launcherController;
    final sc = _settingsController;
    final cc = _configuratorController;
    final qlc = _quickLaunchController;
    final plc = _profileLibraryController;
    final pcc = _profileCatalogController;

    // Show a loader while the shared controllers are still initializing.
    if (lc == null || sc == null || cc == null || plc == null || pcc == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return switch (route) {
      '/quick' => QuickLaunchPage(
        launcherController: lc,
        quickLaunchController: qlc,
        configuratorController: cc,
        settingsController: sc,
        onNavigateToConfigurator: ([FingerprintProfile? profile]) {
          if (profile != null) cc.loadProfile(profile);
          _currentRoute.value = '/configurator';
        },
      ),
      '/configurator' => ConfiguratorPage(
        controller: cc,
        profileCatalogController: pcc,
        settingsController: sc,
        onNavigateToQuickLaunch: () => _currentRoute.value = '/quick',
      ),
      '/profiles' => ProfileLibraryPage(
        controller: plc,
        apps: lc.apps.map((s) => s.descriptor).toList(),
        onEditProfile: (profile) {
          cc.loadProfile(profile);
          _currentRoute.value = '/configurator';
        },
      ),
      '/capture' => Ja4CapturePage(profileCatalogController: pcc),
      '/settings' => SettingsPage(
        controller: sc,
        onSaved: () => unawaited(_initControllers()),
      ),
      _ => QuickLaunchPage(
        launcherController: lc,
        quickLaunchController: qlc,
        configuratorController: cc,
        settingsController: sc,
        onNavigateToConfigurator: ([FingerprintProfile? profile]) {
          if (profile != null) cc.loadProfile(profile);
          _currentRoute.value = '/configurator';
        },
      ),
    };
  }
}
