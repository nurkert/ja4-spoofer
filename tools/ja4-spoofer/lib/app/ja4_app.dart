import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'ja4_theme.dart';
import 'widgets/app_shell.dart';

/// Root application widget.
///
/// Routing and theme live here; feature logic lives in feature modules.
class Ja4App extends StatelessWidget {
  const Ja4App({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      debugShowCheckedModeBanner: false,
      title: 'JA4 Spoofer',
      themeMode: ThemeMode.system,
      theme: Ja4Theme.light(),
      darkTheme: Ja4Theme.dark(),
      builder: (context, child) => ShadSonner(child: child!),
      home: const AppShell(),
    );
  }
}
