import 'dart:convert';
import 'dart:io';

/// Lightweight process handle exposed to the controller.
class RunningScript {
  const RunningScript({
    required this.process,
    required this.stdout,
    required this.stderr,
  });

  final Process process;
  final Stream<String> stdout;
  final Stream<String> stderr;
}

/// Starts and stops `run_firefox_with_ja4.sh`.
class ScriptLauncherService {
  const ScriptLauncherService();

  Future<RunningScript> start({
    required String scriptPath,
    required List<String> args,
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      scriptPath,
      args,
      runInShell: false,
      environment: environment,
    );
    return RunningScript(
      process: process,
      stdout: process.stdout.transform(utf8.decoder),
      stderr: process.stderr.transform(utf8.decoder),
    );
  }

  bool stop(Process process, {bool force = false}) {
    if (force) {
      return process.kill(ProcessSignal.sigkill);
    }
    // SIGTERM is the standard graceful-shutdown signal on macOS/Linux.
    // Firefox and Chromium both handle it correctly.
    final sent = process.kill(ProcessSignal.sigterm);
    if (sent) return true;
    // Fall back to SIGKILL if SIGTERM could not be delivered.
    return process.kill(ProcessSignal.sigkill);
  }
}
