import 'package:flutter/foundation.dart';

import '../../core/models/app_settings.dart';
import '../../core/services/settings_service.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({SettingsService? settingsService})
    : _service = settingsService ?? SettingsService();

  final SettingsService _service;

  bool loading = true;
  AppSettings settings = const AppSettings();

  Future<void> load() async {
    loading = true;
    // Yield once before notifying so that callers who invoke load() from
    // initState (or any other build-adjacent context) don't fan a synchronous
    // markNeedsBuild through SettingsScope while a frame is still building.
    await null;
    notifyListeners();
    try {
      settings = await _service.load();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> save(AppSettings updated) async {
    settings = updated;
    notifyListeners();
    await _service.save(updated);
  }

  Future<void> setRepoPath(String? path) async {
    await save(
      settings.copyWith(repoPath: (path == null || path.isEmpty) ? null : path),
    );
  }

  Future<void> setIanaSource(IanaSource value) async {
    await save(settings.copyWith(ianaSource: value));
  }

  Future<void> setLoadRemoteIcons(bool value) async {
    await save(settings.copyWith(loadRemoteIcons: value));
  }
}
