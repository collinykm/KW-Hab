import 'dart:async';

import 'package:flutter/foundation.dart';

import 'accessibility_settings.dart';
import 'settings_storage.dart';
import 'support_contact.dart';

/// The app's single source of truth for user settings: accessibility choices,
/// support contacts, and whether onboarding is done. Saved to disk on every
/// change.
///
/// Built once in `main.dart`. How to reach it:
/// - Flutter widgets: `SettingsScope.of(context)` (rebuilds on change).
/// - Dart services (monitoring, bridges): take it as a constructor argument
///   and `addListener` if they need to react.
/// - Injected page JS/CSS: `kwHab.settings` / `kwHab.onSettings`, and
///   `data-kw-*` attributes + `--kw-*` variables on `<html>`
///   (see `page_settings_bridge.dart`). Only accessibility settings reach the
///   page; support contacts stay in Dart.
class AppSettings extends ChangeNotifier {
  AppSettings({SettingsStorage? storage}) : _storage = storage ?? FileSettingsStorage();

  /// Bump when the saved format changes incompatibly, and migrate in [load].
  static const int schemaVersion = 1;

  final SettingsStorage _storage;

  AccessibilitySettings _accessibility = const AccessibilitySettings();
  List<SupportContact> _supportContacts = const [];
  bool _onboardingComplete = false;

  AccessibilitySettings get accessibility => _accessibility;

  /// Support people, in the order they were entered. Never contains empty
  /// entries.
  List<SupportContact> get supportContacts => _supportContacts;

  /// False until onboarding has been finished once. The shell shows the
  /// onboarding screen after the first Facebook login while this is false.
  bool get onboardingComplete => _onboardingComplete;

  /// Reads saved settings. Call once before [runApp].
  Future<void> load() async {
    Map<String, Object?>? json;
    try {
      json = await _storage.read();
    } catch (e) {
      debugPrint('[kw-hab:settings] could not read settings: $e');
    }
    if (json == null) return;
    _accessibility = AccessibilitySettings.fromJson(json['accessibility']);
    final contacts = json['supportContacts'];
    _supportContacts = List.unmodifiable([
      if (contacts is List)
        for (final c in contacts)
          if (SupportContact.fromJson(c) case final contact? when !contact.isEmpty) contact,
    ]);
    _onboardingComplete = json['onboardingComplete'] == true;
    notifyListeners();
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'onboardingComplete': _onboardingComplete,
        'accessibility': _accessibility.toJson(),
        'supportContacts': [for (final c in _supportContacts) c.toJson()],
      };

  set accessibility(AccessibilitySettings value) {
    if (value == _accessibility) return;
    _accessibility = value;
    _changed();
  }

  /// Convenience for one-field changes:
  /// `settings.updateAccessibility((a) => a.copyWith(boldText: true))`.
  void updateAccessibility(AccessibilitySettings Function(AccessibilitySettings) update) =>
      accessibility = update(_accessibility);

  /// Replaces the whole list. Blank entries are dropped.
  set supportContacts(List<SupportContact> value) {
    final cleaned = List<SupportContact>.unmodifiable(value.where((c) => !c.isEmpty));
    if (listEquals(cleaned, _supportContacts)) return;
    _supportContacts = cleaned;
    _changed();
  }

  void completeOnboarding() {
    if (_onboardingComplete) return;
    _onboardingComplete = true;
    _changed();
  }

  void _changed() {
    notifyListeners();
    unawaited(_save());
  }

  // Saves are serialized: while one is writing, further changes just mark the
  // settings dirty and are written once it finishes (sliders fire a lot).
  Future<void>? _saving;
  bool _dirty = false;

  Future<void> _save() {
    if (_saving != null) {
      _dirty = true;
      return _saving!;
    }
    return _saving = () async {
      do {
        _dirty = false;
        try {
          await _storage.write(toJson());
        } catch (e) {
          debugPrint('[kw-hab:settings] could not save settings: $e');
        }
      } while (_dirty);
      _saving = null;
    }();
  }

  /// Completes when everything changed so far is on disk (tests, shutdown).
  Future<void> flush() => _saving ?? Future.value();
}
