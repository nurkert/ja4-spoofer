import 'dart:async';
import 'dart:io';

/// Watches a file path for content changes using polling.
///
/// On macOS, FileSystemEntity.watch() may be restricted in the sandbox,
/// so we use a 500ms polling interval as a reliable fallback.
class DumpWatcherService {
  DumpWatcherService({this.pollInterval = const Duration(milliseconds: 500)});

  final Duration pollInterval;

  Timer? _timer;
  String? _lastContent;
  final _controller = StreamController<String>.broadcast();

  /// Stream of file content whenever it changes.
  Stream<String> get onChange => _controller.stream;

  /// Starts watching [path] for changes.
  void start(String path) {
    stop();
    _lastContent = null;
    _timer = Timer.periodic(pollInterval, (_) => _poll(path));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    unawaited(_controller.close());
  }

  Future<void> _poll(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return;
      final content = await file.readAsString();
      if (content != _lastContent) {
        _lastContent = content;
        _controller.add(content);
      }
    } catch (_) {
      // File may not be readable yet; ignore
    }
  }
}
