import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/controllers/profile_catalog_controller.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/capture_record.dart';
import '../../core/models/fingerprint_profile.dart';
import '../../core/models/registry_bundle.dart';
import '../../core/services/iana_registry_service.dart';
import '../../core/services/ja4_capture_server.dart';
import '../../core/services/settings_service.dart';

class Ja4CaptureController extends ChangeNotifier {
  Ja4CaptureController({
    int port = 8443,
    required ProfileCatalogController profileCatalogController,
  }) : _server = Ja4CaptureServer(port: port),
       _profileCatalogController = profileCatalogController {
    unawaited(_loadSettings());
  }

  final Ja4CaptureServer _server;
  final ProfileCatalogController _profileCatalogController;
  final SettingsService _settingsService = SettingsService();
  static const _ianaService = IanaRegistryService();

  bool get serverRunning => _server.isRunning;
  int get port => _server.port;
  List<CaptureRecord> get captures => _server.history;
  CaptureRecord? get lastCapture => _server.lastCapture;

  /// Source for IANA name resolution. Disabled = hex only in capture detail.
  IanaSource ianaSource = IanaSource.bundled;

  /// Whether IANA names should be shown in capture details.
  bool get showIanaNames => ianaSource != IanaSource.disabled;

  /// Loaded IANA registry (null until first load).
  RegistryBundle? registry;
  bool _registryLoading = false;

  StreamSubscription<CaptureRecord>? _captureSub;
  bool _disposed = false;

  // Throttle UI updates to avoid excessive rebuilds during rapid captures.
  Timer? _throttleTimer;
  bool _pendingNotify = false;
  static const _throttleInterval = Duration(milliseconds: 300);

  Future<void> _loadSettings() async {
    final settings = await _settingsService.load();
    if (_disposed) return;
    final previous = ianaSource;
    ianaSource = settings.ianaSource;
    // Drop a stale registry when the source changes so the next access
    // re-resolves with the freshly chosen backend.
    if (previous != ianaSource) {
      registry = null;
    }
    if (showIanaNames) {
      await _ensureRegistry();
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> refreshSettings() async {
    await _loadSettings();
  }

  Future<void> _ensureRegistry() async {
    if (registry != null || _registryLoading) return;
    _registryLoading = true;
    try {
      registry = await _ianaService.load(ianaSource);
    } catch (_) {
      registry = IanaRegistryService.fallbackBundle;
    }
    _registryLoading = false;
    if (!_disposed) notifyListeners();
  }

  /// Resolves an integer ID to its IANA name, or returns the hex string.
  String resolveName(int id, List<dynamic>? registryItems) {
    final hex = '0x${id.toRadixString(16).padLeft(4, '0')}';
    if (!showIanaNames || registryItems == null) return hex;
    for (final item in registryItems) {
      if (item.id == id) return '$hex ${item.name}';
    }
    return hex;
  }

  void _throttledNotify() {
    if (_throttleTimer?.isActive ?? false) {
      _pendingNotify = true;
      return;
    }
    notifyListeners();
    _throttleTimer = Timer(_throttleInterval, () {
      if (_pendingNotify && !_disposed) {
        _pendingNotify = false;
        notifyListeners();
      }
    });
  }

  Future<void> toggleServer() async {
    if (_server.isRunning) {
      await _captureSub?.cancel();
      _captureSub = null;
      await _server.stop();
    } else {
      await _server.start();
      _captureSub = _server.onCapture.listen((_) => _throttledNotify());
    }
    notifyListeners();
  }

  Future<void> saveCapture(
    CaptureRecord record, {
    required String name,
    String? version,
    String? iconUrl,
  }) async {
    if (record.tlsInputs != null) {
      final profile = FingerprintProfile(
        profileId: 'captured-${record.capturedAt.millisecondsSinceEpoch}',
        metadata: FingerprintProfileMetadata(
          name: name,
          source: 'captured',
          capturedAt: record.capturedAt,
          version: version,
          iconUrl: iconUrl,
        ),
        inputs: record.tlsInputs!,
      );
      await _profileCatalogController.saveProfile(profile);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _throttleTimer?.cancel();
    unawaited(_captureSub?.cancel() ?? Future<void>.value());
    _server.dispose();
    super.dispose();
  }
}
