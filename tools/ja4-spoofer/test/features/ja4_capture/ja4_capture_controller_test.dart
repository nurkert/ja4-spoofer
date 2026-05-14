import 'package:flutter_test/flutter_test.dart';
import 'package:ja4_spoofer/core/controllers/profile_catalog_controller.dart';
import 'package:ja4_spoofer/features/ja4_capture/ja4_capture_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('construct and dispose without firing any listener', () async {
    // Smoke test: covers the constructor + dispose contract. The
    // disposed-state guards (`_disposed`, throttle-timer cancel) are
    // what make the controller safe to throw away mid-capture; this
    // test ensures the happy path of "open then close the page"
    // doesn't throw, leak, or trip the ChangeNotifier-after-dispose
    // assertion.
    final catalog = ProfileCatalogController();
    addTearDown(catalog.dispose);

    final controller = Ja4CaptureController(
      port: 0,
      profileCatalogController: catalog,
    );

    // Initial state: no server, no captures yet.
    expect(controller.serverRunning, isFalse);
    expect(controller.captures, isEmpty);

    // Disposing while the controller hasn't started its TLS server is
    // the common "user closes the page without ever toggling capture"
    // flow. It must complete without throwing.
    expect(controller.dispose, returnsNormally);
  });
}
