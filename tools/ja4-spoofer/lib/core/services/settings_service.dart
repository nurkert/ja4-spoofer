import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';

/// Persists [AppSettings] to ~/.ja4-spoofer/settings.json.
class SettingsService {
  SettingsService({String? settingsPath})
    : _settingsPath = settingsPath ?? _defaultSettingsPath();

  final String _settingsPath;

  static String _defaultSettingsPath() {
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/.ja4-spoofer/settings.json';
  }

  Future<AppSettings> load() async {
    final file = File(_settingsPath);
    if (!file.existsSync()) return const AppSettings();
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return AppSettings.fromJson(json);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final file = File(_settingsPath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final json = const JsonEncoder.withIndent('  ').convert(settings.toJson());
    await file.writeAsString(json);
  }
}
