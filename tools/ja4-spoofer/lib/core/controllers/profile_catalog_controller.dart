import 'package:flutter/foundation.dart';

import '../models/fingerprint_profile.dart';
import '../services/profile_service.dart';
import '../services/settings_service.dart';

/// Shared app-wide profile catalog.
///
/// This is the single source of truth for persisted profiles and the current
/// globally selected profile. Feature-local controllers may derive filtered or
/// presentation-specific state from this controller, but they must not keep
/// their own profile snapshots.
class ProfileCatalogController extends ChangeNotifier {
  ProfileCatalogController({
    ProfileService? profileService,
    SettingsService? settingsService,
  }) : _profileService = profileService ?? ProfileService(),
       _settingsService = settingsService ?? SettingsService();

  final ProfileService _profileService;
  final SettingsService _settingsService;

  List<FingerprintProfile> _profiles = const [];
  bool _loading = false;
  String? _selectedProfileId;
  String? _statusMessage;

  List<FingerprintProfile> get profiles => _profiles;
  bool get loading => _loading;
  String? get selectedProfileId => _selectedProfileId;
  String? get statusMessage => _statusMessage;

  FingerprintProfile? get selectedProfile {
    final id = _selectedProfileId;
    if (id == null) return null;
    return _profiles.where((p) => p.profileId == id).firstOrNull;
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _profiles = await _profileService.loadAll();
      final settings = await _settingsService.load();
      _selectedProfileId = settings.quickLaunchProfileId;
      _reconcileSelection();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final selectedId = _selectedProfileId;
    _profiles = await _profileService.loadAll();
    _selectedProfileId = selectedId;
    _reconcileSelection();
    notifyListeners();
  }

  Future<void> selectProfile(String? profileId) async {
    _selectedProfileId = profileId;
    _reconcileSelection();
    final settings = await _settingsService.load();
    await _settingsService.save(
      settings.copyWith(quickLaunchProfileId: _selectedProfileId),
    );
    notifyListeners();
  }

  Future<void> saveProfile(FingerprintProfile profile) async {
    await _profileService.save(profile);
    _upsertInMemory(profile);
    _statusMessage = 'Saved: ${profile.metadata.name}';
    notifyListeners();
  }

  Future<void> deleteProfile(String profileId) async {
    final profile = _profiles
        .where((p) => p.profileId == profileId)
        .firstOrNull;
    if (profile == null || profile.isBuiltIn) return;

    await _profileService.delete(profileId);
    _profiles = _profiles
        .where((p) => p.profileId != profileId)
        .toList(growable: false);
    if (_selectedProfileId == profileId) {
      _selectedProfileId = null;
      final settings = await _settingsService.load();
      await _settingsService.save(
        settings.copyWith(quickLaunchProfileId: null),
      );
    }
    _statusMessage = 'Deleted: ${profile.metadata.name}';
    notifyListeners();
  }

  void clearStatus() {
    if (_statusMessage == null || _statusMessage!.isEmpty) return;
    _statusMessage = null;
    notifyListeners();
  }

  void _upsertInMemory(FingerprintProfile profile) {
    final next = _profiles.toList();
    final index = next.indexWhere((p) => p.profileId == profile.profileId);
    if (index >= 0) {
      next[index] = profile;
    } else {
      next.insert(0, profile);
    }
    _profiles = List.unmodifiable(next);
    _selectedProfileId = profile.profileId;
  }

  void _reconcileSelection() {
    final id = _selectedProfileId;
    if (id == null) return;
    if (_profiles.any((p) => p.profileId == id)) return;
    _selectedProfileId = null;
  }
}
