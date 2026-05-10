import 'package:flutter_test/flutter_test.dart';

import 'package:ja4_spoofer/app/ja4_app.dart';

void main() {
  testWidgets('sidebar renders navigation labels', (WidgetTester tester) async {
    await tester.pumpWidget(const Ja4App());
    // Give one frame for the initial synchronous build
    await tester.pump();

    // Sidebar nav labels — always visible, independent of async controller init
    expect(find.text('Launch'), findsOneWidget);
    expect(find.text('TLS Configurator'), findsOneWidget);
    expect(find.text('Profile Library'), findsOneWidget);
    expect(find.text('JA4 Capture'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
