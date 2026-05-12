import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../models/capture_record.dart';
import '../models/fingerprint_profile.dart';
import '../utils/ja4_hash_preview.dart';
import '../utils/tls_client_hello_parser.dart';

/// GREASE values — kept in sync with [Ja4HashPreview].
const _greaseValues = {
  0x0a0a,
  0x1a1a,
  0x2a2a,
  0x3a3a,
  0x4a4a,
  0x5a5a,
  0x6a6a,
  0x7a7a,
  0x8a8a,
  0x9a9a,
  0xaaaa,
  0xbaba,
  0xcaca,
  0xdada,
  0xeaea,
  0xfafa,
};

/// TLS capture server that sniffs ClientHello fingerprints.
///
/// Listens on a raw TCP socket. When a TLS client connects, the server reads
/// the ClientHello, extracts all JA4-relevant fields, stores the capture, and
/// closes the connection.
class Ja4CaptureServer {
  Ja4CaptureServer({
    this.port = 8443,
    this.maxHistory = 500,
    this.deduplicationWindow = const Duration(seconds: 5),
  });

  final int port;
  final int maxHistory;

  /// Time window within which captures with the same JA4 hash are grouped.
  final Duration deduplicationWindow;

  ServerSocket? _server;
  final List<CaptureRecord> _history = [];
  final _controller = StreamController<CaptureRecord>.broadcast();

  static const _parser = TlsClientHelloParser();
  static const _hashPreview = Ja4HashPreview();

  bool get isRunning => _server != null;

  Stream<CaptureRecord> get onCapture => _controller.stream;
  List<CaptureRecord> get history => List.unmodifiable(_history);
  CaptureRecord? get lastCapture => _history.isEmpty ? null : _history.last;

  Future<void> start() async {
    if (_server != null) return;
    // Bind on all IPv4 interfaces so captures can come from other devices on
    // the LAN (phones, VMs). The server only reads the ClientHello bytes,
    // sends a TLS handshake_failure alert, and closes — no TLS termination,
    // no HTTP, no filesystem access — so LAN exposure is low-risk.
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleConnection);
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  void dispose() {
    unawaited(stop());
    unawaited(_controller.close());
  }

  // ---------------------------------------------------------------------------
  // TLS sniffer
  // ---------------------------------------------------------------------------

  void _handleConnection(Socket socket) async {
    try {
      final bytes = await _readClientHello(socket);
      if (bytes == null) {
        socket.destroy();
        return;
      }

      final hello = _parser.parse(bytes);
      if (hello != null) {
        _addRecord(_recordFromHello(hello, socket.remoteAddress));
      }

      // Send a TLS fatal alert (handshake_failure) so the client gets a clean
      // error instead of a connection-reset.
      try {
        socket.add(
          Uint8List.fromList([
            0x15, // ContentType: Alert
            0x03, 0x01, // Version: TLS 1.0
            0x00, 0x02, // Length: 2
            0x02, // Level: fatal
            0x28, // Description: handshake_failure
          ]),
        );
        await socket.flush();
      } catch (_) {}
    } catch (_) {
      // Ignore malformed connections.
    } finally {
      socket.destroy();
    }
  }

  /// Reads bytes from [socket] until a full TLS record is received or the
  /// timeout fires.
  Future<Uint8List?> _readClientHello(Socket socket) async {
    final buf = <int>[];
    final completer = Completer<Uint8List?>();
    Timer? timer;

    void complete(Uint8List? result) {
      timer?.cancel();
      if (!completer.isCompleted) completer.complete(result);
    }

    late StreamSubscription<Uint8List> sub;
    sub = socket.listen(
      (data) {
        buf.addAll(data);
        if (buf.length >= 5 && buf[0] == 0x16) {
          final recordLen = (buf[3] << 8) | buf[4];
          if (buf.length >= 5 + recordLen) {
            unawaited(sub.cancel());
            complete(Uint8List.fromList(buf));
          }
        } else if (buf.isNotEmpty && buf[0] != 0x16) {
          unawaited(sub.cancel());
          complete(null);
        }
      },
      onError: (_) {
        unawaited(sub.cancel());
        complete(null);
      },
      onDone: () {
        complete(buf.isNotEmpty ? Uint8List.fromList(buf) : null);
      },
    );

    timer = Timer(const Duration(seconds: 3), () {
      unawaited(sub.cancel());
      complete(buf.isNotEmpty ? Uint8List.fromList(buf) : null);
    });

    return completer.future;
  }

  CaptureRecord _recordFromHello(
    ParsedClientHello hello,
    InternetAddress remote,
  ) {
    final ciphers = hello.cipherSuites
        .where((c) => !_greaseValues.contains(c))
        .toList();
    final extensions = hello.extensionIds
        .where((e) => !_greaseValues.contains(e))
        .toList();
    final sigAlgs = hello.signatureAlgorithms
        .where((s) => !_greaseValues.contains(s))
        .toList();

    final tlsInputs = TlsClientHelloInputs(
      tlsMinVersion: hello.minTlsVersion,
      tlsMaxVersion: hello.maxTlsVersion,
      cipherSuites: ciphers,
      extensions: extensions,
      signatureAlgorithms: sigAlgs,
      alpnProtocols: hello.alpnProtocols,
      sniMode: hello.sniMode,
      enableGrease: hello.hasGrease,
      enableChXtnPermutation: false,
    );

    final ja4Hash = _hashPreview.compute(
      tlsMaxVersion: tlsInputs.tlsMaxVersion,
      sniMode: tlsInputs.sniMode,
      cipherSuites: tlsInputs.cipherSuites,
      extensions: tlsInputs.extensions,
      signatureAlgorithms: tlsInputs.signatureAlgorithms,
      alpnProtocols: tlsInputs.alpnProtocols,
    );

    return CaptureRecord(
      capturedAt: DateTime.now(),
      ja4Hash: ja4Hash,
      sni: hello.sni,
      sourceAddress: remote.address,
      tlsInputs: tlsInputs,
    );
  }

  void _addRecord(CaptureRecord record) {
    // Scan recent history for a duplicate JA4 hash within the dedup window.
    final scanLimit = _history.length < 20 ? _history.length : 20;
    for (var i = _history.length - 1; i >= _history.length - scanLimit; i--) {
      final existing = _history[i];
      if (existing.ja4Hash == record.ja4Hash) {
        final ref = existing.lastSeenAt ?? existing.capturedAt;
        if (record.capturedAt.difference(ref) < deduplicationWindow) {
          final updated = existing.copyWithIncrement(
            lastSeenAt: record.capturedAt,
          );
          _history[i] = updated;
          _controller.add(updated);
          return;
        }
      }
    }

    _history.add(record);
    if (_history.length > maxHistory) _history.removeAt(0);
    _controller.add(record);
  }
}
