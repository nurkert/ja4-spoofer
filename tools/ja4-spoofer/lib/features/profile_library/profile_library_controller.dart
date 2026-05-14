import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../core/controllers/profile_catalog_controller.dart';
import '../../core/models/app_descriptor.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/fingerprint_profile.dart';
import '../../core/models/registry_bundle.dart';
import '../../core/models/registry_item.dart';
import '../../core/services/iana_registry_service.dart';
import '../../core/services/profile_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/utils/compatibility_checker.dart';

class ProfileLibraryController extends ChangeNotifier {
  ProfileLibraryController({
    required ProfileCatalogController profileCatalogController,
    ProfileService? service,
    SettingsService? settingsService,
    List<AppDescriptor> apps = const [],
  }) : _service = service ?? ProfileService(),
       _settingsService = settingsService ?? SettingsService(),
       _apps = apps,
       _profileCatalogController = profileCatalogController {
    _profileCatalogController.addListener(_onCatalogChanged);
  }

  final ProfileService _service;
  final SettingsService _settingsService;
  final ProfileCatalogController _profileCatalogController;
  static final IanaRegistryService _ianaService = IanaRegistryService();
  final CompatibilityChecker _checker = const CompatibilityChecker();

  /// Source for IANA name resolution. Disabled = hex IDs only.
  IanaSource ianaSource = IanaSource.bundled;

  /// Whether to resolve IANA names for integer IDs.
  bool get showIanaNames => ianaSource != IanaSource.disabled;

  /// Loaded IANA registry bundle (null until first load).
  RegistryBundle? registry;

  String filterText = '';
  String _localStatus = '';

  List<AppDescriptor> _apps;
  List<AppDescriptor> get apps => _apps;
  bool get loading => _profileCatalogController.loading;
  List<FingerprintProfile> get profiles => _profileCatalogController.profiles;
  String? get selectedProfileId => _profileCatalogController.selectedProfileId;
  String get status => _localStatus.isNotEmpty
      ? _localStatus
      : (_profileCatalogController.statusMessage ?? '');

  @override
  void dispose() {
    _profileCatalogController.removeListener(_onCatalogChanged);
    super.dispose();
  }

  void _onCatalogChanged() {
    notifyListeners();
  }

  void updateApps(List<AppDescriptor> apps) {
    _apps = apps;
    notifyListeners();
  }

  FingerprintProfile? get selectedProfile =>
      _profileCatalogController.selectedProfile;

  List<FingerprintProfile> get filteredProfiles {
    if (filterText.isEmpty) return profiles;
    final q = filterText.toLowerCase();
    return profiles
        .where(
          (p) =>
              p.metadata.name.toLowerCase().contains(q) ||
              p.profileId.toLowerCase().contains(q) ||
              (p.metadata.source.toLowerCase().contains(q)),
        )
        .toList();
  }

  /// Returns compatibility results for the selected profile against all apps.
  /// When [showIanaNames] is on, unsupported-cipher / extension / sig-alg
  /// messages are decorated with their resolved IANA names.
  List<CompatibilityResult> get compatibilityResults {
    final profile = selectedProfile;
    if (profile == null) return [];
    final reg = showIanaNames ? registry : null;
    return _apps
        .where((app) => !app.tlsDefaults.isEmpty)
        .map((app) => _checker.check(profile, app, registry: reg))
        .toList();
  }

  Future<void> loadProfiles() async {
    await _profileCatalogController.load();
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.load();
    final previous = ianaSource;
    ianaSource = settings.ianaSource;
    if (previous != ianaSource) {
      registry = null;
    }
    if (showIanaNames && registry == null) {
      try {
        registry = await _ianaService.load(ianaSource);
      } catch (_) {
        registry = IanaRegistryService.fallbackBundle;
      }
    }
  }

  /// Resolves an integer ID to "0xHEX name" using the registry, or just "id (0xHEX)".
  String _resolveId(int id, List<RegistryItem>? items) {
    final hex = '0x${id.toRadixString(16).padLeft(4, '0').toUpperCase()}';
    if (!showIanaNames || items == null) return '$id ($hex)';
    for (final item in items) {
      if (item.id == id) return '$hex ${item.name}';
    }
    return '$id ($hex)';
  }

  /// Formats a list of cipher suite IDs with optional IANA names.
  String formatCiphers(List<int> ids) =>
      ids.map((id) => _resolveId(id, registry?.cipherSuites)).join(', ');

  /// Formats a list of extension IDs with optional IANA names.
  String formatExtensions(List<int> ids) =>
      ids.map((id) => _resolveId(id, registry?.extensions)).join(', ');

  /// Formats a list of signature algorithm IDs with optional IANA names.
  String formatSignatures(List<int> ids) =>
      ids.map((id) => _resolveId(id, registry?.signatureSchemes)).join(', ');

  Future<void> selectProfile(String? id) =>
      _profileCatalogController.selectProfile(id);

  void setFilter(String text) {
    filterText = text;
    notifyListeners();
  }

  Future<void> deleteProfile(String id) async {
    await _profileCatalogController.deleteProfile(id);
  }

  Future<void> importFromFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    try {
      final content = await File(path).readAsString();
      final profile = await _service.importFromJson(content);
      _localStatus = '';
      await _profileCatalogController.refresh();
      await _profileCatalogController.selectProfile(profile.profileId);
    } catch (e) {
      _localStatus = 'Import failed: $e';
      notifyListeners();
    }
  }
}
