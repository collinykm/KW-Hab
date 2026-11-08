import 'package:flutter/widgets.dart';

import 'app_settings.dart';

/// Makes [AppSettings] available to every Flutter widget below it, and
/// rebuilds the widgets that read it when a setting changes.
///
/// ```dart
/// final a11y = SettingsScope.of(context).accessibility;
/// ```
class SettingsScope extends InheritedNotifier<AppSettings> {
  const SettingsScope({super.key, required AppSettings settings, required super.child})
      : super(notifier: settings);

  static AppSettings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'No SettingsScope above this widget (see lib/app.dart).');
    return scope!.notifier!;
  }
}
