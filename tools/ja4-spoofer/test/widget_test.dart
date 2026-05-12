import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ja4_spoofer/app/ja4_app.dart';

void main() {
  testWidgets('sidebar renders navigation labels', (WidgetTester tester) async {
    // Ensure the sidebar is wide enough that NavItem renders labels
    // (it hides them when constraints.maxWidth < 90).
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Silence FlutterError handlers during async controller init. The
    // controllers' background loads (asset extraction, registry fetch)
    // may surface errors as destructive toasts in production; in this
    // unit test we only care that the static sidebar renders.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = originalOnError);

    await tester.pumpWidget(const Ja4App());
    // Pump a few frames so the layout settles. Stay synchronous —
    // we don't want to wait on real I/O from controller init.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('Launch'), findsAtLeastNWidgets(1));
    expect(find.text('TLS Configurator'), findsAtLeastNWidgets(1));
    expect(find.text('Profile Library'), findsAtLeastNWidgets(1));
    expect(find.text('JA4 Capture'), findsAtLeastNWidgets(1));
    expect(find.text('Settings'), findsAtLeastNWidgets(1));
  });
}
