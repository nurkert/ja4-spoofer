import 'package:flutter/widgets.dart';

import '../../features/settings/settings_controller.dart';

/// Exposes the app-wide [SettingsController] to any descendant widget that
/// needs to react to user-facing toggles (e.g. the network/privacy switches).
///
/// Use [SettingsScope.of] to read the current settings; this also subscribes
/// the calling widget to controller change notifications, so it rebuilds when
/// the user flips a switch.
class SettingsScope extends InheritedNotifier<SettingsController> {
  const SettingsScope({
    super.key,
    required SettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static SettingsController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SettingsScope>()
        ?.notifier;
  }

  static SettingsController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(
      controller != null,
      'SettingsScope.of() called without a SettingsScope ancestor.',
    );
    return controller!;
  }
}
