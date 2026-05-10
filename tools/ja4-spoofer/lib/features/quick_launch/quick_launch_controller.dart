import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/controllers/profile_catalog_controller.dart';
import '../../core/models/fingerprint_profile.dart';
import '../../core/utils/compat_prober.dart';
import '../../core/utils/random_engine.dart';
import '../app_launcher/app_launcher_controller.dart';
import '../configurator/configurator_controller.dart';

enum QuickLaunchSection { profile, tlsConfiguration, randomize }

/// Controller for the Quick Launch page.
///
/// Fully generic — no browser IDs are hardcoded here.
/// Delegates TLS state to [ConfiguratorController] for cross-tab sharing.
class QuickLaunchController extends ChangeNotifier {
  QuickLaunchController({
    required List<AppState> apps,
    required ConfiguratorController configuratorController,
    required ProfileCatalogController profileCatalogController,
    RandomEngine? randomEngine,
    CompatProber? compatProber,
  }) : apps = List.unmodifiable(apps),
       _configuratorController = configuratorController,
       _profileCatalogController = profileCatalogController,
       _engine = randomEngine ?? const RandomEngine(),
       _prober = compatProber ?? const CompatProber() {
    _profileCatalogController.addListener(_onCatalogChanged);
    masterSeed = RandomEngine.randomSeed();
  }

  final List<AppState> apps;
  final ConfiguratorController _configuratorController;
  final ProfileCatalogController _profileCatalogController;
  final RandomEngine _engine;
  final CompatProber _prober;

  ConfiguratorController get configuratorController => _configuratorController;
  ProfileCatalogController get profileCatalogController =>
      _profileCatalogController;

  QuickLaunchSection selectedSection = QuickLaunchSection.profile;

  List<FingerprintProfile> get profiles => _profileCatalogController.profiles;
  bool get profilesLoading => _profileCatalogController.loading;
  FingerprintProfile? get selectedProfile =>
      _profileCatalogController.selectedProfile;

  // ---------- Random state ----------

  late String masterSeed;

  RandomConfig randomConfig = const RandomConfig();

  final Map<String, RolledProfile> _perAppRolls = {};
  final Map<String, CompatScore> _perAppCompat = {};
  final Set<String> _probingApps = {};

  bool hasRollFor(String appId) => _perAppRolls.containsKey(appId);
  RolledProfile? rollFor(String appId) => _perAppRolls[appId];
  CompatScore? compatFor(String appId) => _perAppCompat[appId];
  bool isProbing(String appId) => _probingApps.contains(appId);

  // ---------- lifecycle ----------

  @override
  void dispose() {
    _disposed = true;
    _profileCatalogController.removeListener(_onCatalogChanged);
    super.dispose();
  }

  void _onCatalogChanged() {
    if (_profileCatalogController.selectedProfile == null &&
        selectedSection == QuickLaunchSection.profile) {
      selectedSection = QuickLaunchSection.tlsConfiguration;
    }
    notifyListeners();
  }

  Future<void> restoreSelectionIntoConfigurator() async {
    final profile = _profileCatalogController.selectedProfile;
    if (profile != null) {
      _configuratorController.loadProfile(profile);
    }
  }

  Future<void> selectProfile(FingerprintProfile? profile) async {
    selectedSection = QuickLaunchSection.profile;
    if (profile != null) {
      _configuratorController.loadProfile(profile);
    }
    await _profileCatalogController.selectProfile(profile?.profileId);
    notifyListeners();
  }

  FingerprintProfile get effectiveProfile =>
      _configuratorController.toFingerprintProfile();

  FingerprintProfile profileForLaunch(AppState app) {
    if (selectedSection == QuickLaunchSection.randomize) {
      final rolled = _perAppRolls[app.descriptor.appId];
      if (rolled != null) return rolled.profile;
    }
    return effectiveProfile;
  }

  void selectSection(QuickLaunchSection section) {
    if (selectedSection == section) return;
    selectedSection = section;
    if (section == QuickLaunchSection.randomize && _perAppRolls.isEmpty) {
      roll();
      return;
    }
    notifyListeners();
  }

  // ---------- Random actions ----------

  void setSeed(String seed) {
    masterSeed = seed.trim();
    _autoRoll();
  }

  void randomizeSeed() {
    masterSeed = RandomEngine.randomSeed();
    _autoRoll();
  }

  void setComponentPool(RandomComponent component, RandomPool pool) {
    final cfg = randomConfig.forComponent(component).copyWith(pool: pool);
    _setComponent(component, cfg);
  }

  void toggleMutation(RandomComponent component, MutationType type) {
    final current = randomConfig.forComponent(component);
    final next = Set<MutationType>.from(current.mutations);
    if (next.contains(type)) {
      next.remove(type);
    } else {
      next.add(type);
    }
    _setComponent(component, current.copyWith(mutations: next));
  }

  void setAllowIncompat(bool value) {
    randomConfig = randomConfig.copyWith(allowIncompat: value);
    _autoRoll();
  }

  void setSniMode(SniRandomMode mode) {
    randomConfig = randomConfig.copyWith(sniMode: mode);
    _autoRoll();
  }

  void setTlsVersionMode(TlsVersionMode mode) {
    randomConfig = randomConfig.copyWith(tlsVersionMode: mode);
    _autoRoll();
  }

  void setAlpnMode(AlpnMode mode) {
    randomConfig = randomConfig.copyWith(alpnMode: mode);
    _autoRoll();
  }

  void setDropAmount(int amount) {
    randomConfig = randomConfig.copyWith(dropAmount: amount.clamp(1, 10));
    _autoRoll();
  }

  void setJunkAmount(int amount) {
    randomConfig = randomConfig.copyWith(junkAmount: amount.clamp(1, 10));
    _autoRoll();
  }

  void _setComponent(RandomComponent component, ComponentConfig cfg) {
    switch (component) {
      case RandomComponent.cipher:
        randomConfig = randomConfig.copyWith(cipher: cfg);
      case RandomComponent.extension:
        randomConfig = randomConfig.copyWith(extension: cfg);
      case RandomComponent.sigalg:
        randomConfig = randomConfig.copyWith(sigalg: cfg);
    }
    _autoRoll();
  }

  /// Re-rolls immediately if the randomize section is active; otherwise just
  /// notifies listeners so the UI stays in sync.
  void _autoRoll() {
    if (selectedSection == QuickLaunchSection.randomize && apps.isNotEmpty) {
      roll();
    } else {
      notifyListeners();
    }
  }

  void roll() {
    if (apps.isEmpty) return;
    if (masterSeed.trim().isEmpty) {
      masterSeed = RandomEngine.randomSeed();
    }
    _perAppRolls.clear();
    _perAppCompat.clear();
    for (final app in apps) {
      final rolled = _engine.roll(
        app: app.descriptor,
        config: randomConfig,
        masterSeed: masterSeed,
      );
      _perAppRolls[app.descriptor.appId] = rolled;
    }
    selectedSection = QuickLaunchSection.randomize;
    notifyListeners();
  }

  void clearRolls() {
    _perAppRolls.clear();
    _perAppCompat.clear();
    notifyListeners();
  }

  Future<void> scheduleCompatProbe(String appId) async {
    final rolled = _perAppRolls[appId];
    if (rolled == null) return;
    final appIndex = apps.indexWhere((a) => a.descriptor.appId == appId);
    if (appIndex == -1) return;
    final app = apps[appIndex];
    if (_probingApps.contains(appId)) return;
    _probingApps.add(appId);
    notifyListeners();
    try {
      final score = await _prober.probe(
        app: app.descriptor,
        profile: rolled.profile,
      );
      if (!_disposed) _perAppCompat[appId] = score;
    } catch (_) {
      // Ignored — score bleibt absent, UI zeigt einfach nichts.
    } finally {
      _probingApps.remove(appId);
      if (!_disposed) notifyListeners();
    }
  }

  bool _disposed = false;

  void moveRollToConfigurator(String appId) {
    final rolled = _perAppRolls[appId];
    if (rolled == null) return;
    final suggestedName = 'random-$appId-${rolled.subSeedHex.substring(0, 8)}';
    _configuratorController.loadFromRandomRoll(
      rolled.profile,
      suggestedName: suggestedName,
    );
    selectedSection = QuickLaunchSection.tlsConfiguration;
    notifyListeners();
  }
}
