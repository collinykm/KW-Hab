import 'package:flutter/foundation.dart';

/// How the user wants the app to look and behave. Chosen during onboarding
/// (with their support person) and changeable later from Settings (⌘,).
///
/// Everything here is safe to share with the Facebook page: it is sent to the
/// page as `kwHab.settings` (see [toPageJson]) so injected CSS/JS can adapt.
@immutable
class AccessibilitySettings {
  const AccessibilitySettings({
    this.textScale = 1.0,
    this.boldText = false,
    this.buttonScale = 1.0,
    this.readAloud = false,
    this.talkToType = false,
  });

  static const double minTextScale = 1.0;
  static const double maxTextScale = 2.0;
  static const double minButtonScale = 1.0;
  static const double maxButtonScale = 2.0;

  /// Multiplier for all text, 1.0 = normal.
  final double textScale;

  /// Make all text bold.
  final bool boldText;

  /// Multiplier for buttons and other things you click, 1.0 = normal.
  final double buttonScale;

  /// Text read aloud (text-to-speech).
  final bool readAloud;

  /// Talk to type (speech-to-text for input).
  final bool talkToType;

  AccessibilitySettings copyWith({
    double? textScale,
    bool? boldText,
    double? buttonScale,
    bool? readAloud,
    bool? talkToType,
  }) =>
      AccessibilitySettings(
        textScale: _clamp(textScale ?? this.textScale, minTextScale, maxTextScale),
        boldText: boldText ?? this.boldText,
        buttonScale: _clamp(buttonScale ?? this.buttonScale, minButtonScale, maxButtonScale),
        readAloud: readAloud ?? this.readAloud,
        talkToType: talkToType ?? this.talkToType,
      );

  Map<String, Object?> toJson() => {
        'textScale': textScale,
        'boldText': boldText,
        'buttonScale': buttonScale,
        'readAloud': readAloud,
        'talkToType': talkToType,
      };

  /// What the Facebook page sees. Currently identical to [toJson]; kept
  /// separate so a private field added later doesn't leak into the page.
  Map<String, Object?> toPageJson() => toJson();

  /// Lenient: missing or malformed fields fall back to the defaults, so an
  /// older or hand-edited settings file never stops the app from starting.
  factory AccessibilitySettings.fromJson(Object? json) {
    if (json is! Map) return const AccessibilitySettings();
    double num_(Object? v, double fallback) => v is num ? v.toDouble() : fallback;
    bool bool_(Object? v) => v is bool && v;
    return const AccessibilitySettings().copyWith(
      textScale: num_(json['textScale'], 1.0),
      boldText: bool_(json['boldText']),
      buttonScale: num_(json['buttonScale'], 1.0),
      readAloud: bool_(json['readAloud']),
      talkToType: bool_(json['talkToType']),
    );
  }

  static double _clamp(double v, double min, double max) =>
      v.isFinite ? v.clamp(min, max) : min;

  @override
  bool operator ==(Object other) =>
      other is AccessibilitySettings &&
      other.textScale == textScale &&
      other.boldText == boldText &&
      other.buttonScale == buttonScale &&
      other.readAloud == readAloud &&
      other.talkToType == talkToType;

  @override
  int get hashCode => Object.hash(textScale, boldText, buttonScale, readAloud, talkToType);
}
