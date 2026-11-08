import 'package:flutter/material.dart';

import 'accessibility_settings.dart';
import 'settings_scope.dart';

/// The app's look for native Flutter screens (onboarding, dialogs, error
/// pages): Facebook-like colours and shapes, so moving between Facebook and
/// our screens doesn't feel like switching apps, with the user's
/// [AccessibilitySettings] applied. The Facebook page gets the same settings
/// through `css/accessibility.css`.

/// Facebook-style palette.
abstract final class KwColors {
  static const blue = Color(0xFF0866FF);
  static const blueTint = Color(0xFFEBF5FF); // info boxes, selected rows
  static const pageBackground = Color(0xFFF0F2F5);
  static const card = Color(0xFFFFFFFF);
  static const secondaryButton = Color(0xFFE4E6EB);
  static const divider = Color(0xFFCED0D4);
  static const inputBorder = Color(0xFFCCD0D5);
  static const primaryText = Color(0xFF050505);
  static const secondaryText = Color(0xFF65676B);
  static const danger = Color(0xFFE41E3F);
}

/// Text size and bold text, via [MediaQuery]: every [Text] widget honours
/// these without extra work.
Widget applyAccessibilityMediaQuery(
  BuildContext context,
  AccessibilitySettings a,
  Widget child,
) {
  final mq = MediaQuery.of(context);
  return MediaQuery(
    data: mq.copyWith(
      textScaler: TextScaler.linear(a.textScale),
      boldText: mq.boldText || a.boldText,
    ),
    child: child,
  );
}

/// [size] grown with the user's Text size, for icons and pictures that go with
/// a line of text (a row's icon, a field's icon), so they don't look tiny
/// next to bigger words.
double textSized(BuildContext context, double size) => MediaQuery.textScalerOf(context).scale(size);

/// Icons in buttons that have a label: grown with the button size, or with the
/// text size if that is bigger, so they keep up with the label.
double buttonIconSize(AccessibilitySettings a) =>
    20 * (a.buttonScale > a.textScale ? a.buttonScale : a.textScale);

/// Facebook-like theme, with buttons sized by [AccessibilitySettings.buttonScale].
ThemeData buildAppTheme(AccessibilitySettings a) {
  final s = a.buttonScale;
  final shape = WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)));
  const label = WidgetStatePropertyAll(TextStyle(fontSize: 15, fontWeight: FontWeight.w600));
  final base = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(64 * s, 36 * s)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16 * s, vertical: 8 * s)),
    iconSize: WidgetStatePropertyAll(buttonIconSize(a)),
    shape: shape,
    textStyle: label,
    elevation: const WidgetStatePropertyAll(0),
  );
  final scheme = ColorScheme.fromSeed(
    seedColor: KwColors.blue,
    primary: KwColors.blue,
    onPrimary: Colors.white,
    surface: KwColors.card,
    onSurface: KwColors.primaryText,
    onSurfaceVariant: KwColors.secondaryText,
    outline: KwColors.inputBorder,
    outlineVariant: KwColors.divider,
    error: KwColors.danger,
  );
  final textTheme = Typography.blackMountainView.apply(
    bodyColor: KwColors.primaryText,
    displayColor: KwColors.primaryText,
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: KwColors.pageBackground,
    textTheme: textTheme.copyWith(
      headlineSmall: textTheme.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
      titleMedium: textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      bodyLarge: textTheme.bodyLarge?.copyWith(fontSize: 15, height: 1.35),
      bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.35),
    ),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    dividerTheme: const DividerThemeData(color: KwColors.divider, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: KwColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    // Primary: solid blue.
    filledButtonTheme: FilledButtonThemeData(
      style: base.merge(FilledButton.styleFrom(
        backgroundColor: KwColors.blue,
        foregroundColor: Colors.white,
      )),
    ),
    // Secondary: Facebook's grey button.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: base.merge(ElevatedButton.styleFrom(
        backgroundColor: KwColors.secondaryButton,
        foregroundColor: KwColors.primaryText,
        shadowColor: Colors.transparent,
      )),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: base),
    textButtonTheme: TextButtonThemeData(
      style: base.merge(TextButton.styleFrom(foregroundColor: KwColors.secondaryText)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        iconSize: WidgetStatePropertyAll(24 * s),
        minimumSize: WidgetStatePropertyAll(Size.square(40 * s)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KwColors.card,
      // Text boxes are click targets too: taller with the button size.
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14 * s),
      labelStyle: const TextStyle(color: KwColors.secondaryText),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: KwColors.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: KwColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: KwColors.blue, width: 2),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? KwColors.blue : KwColors.secondaryButton),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? KwColors.blue : KwColors.secondaryText),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: KwColors.blue,
      inactiveTrackColor: KwColors.secondaryButton,
      thumbColor: KwColors.blue,
      activeTickMarkColor: Colors.white70,
      inactiveTickMarkColor: KwColors.divider,
      trackHeight: 6 * s,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10 * s),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 24 * s),
      showValueIndicator: ShowValueIndicator.never,
    ),
    // Extra tap area for checkboxes, radios and list tiles (max +4 = 16px).
    // Switches and radios are also drawn bigger with [ScaledControl].
    visualDensity: VisualDensity(
      horizontal: ((s - 1) * 4).clamp(0, 4).toDouble(),
      vertical: ((s - 1) * 4).clamp(0, 4).toDouble(),
    ),
  );
}

/// Draws a control that has no size setting of its own (Switch, Radio,
/// Checkbox) bigger by the user's button size, for people who find small
/// targets hard to hit. [normalSize] is roughly the control's usual size.
class ScaledControl extends StatelessWidget {
  const ScaledControl({super.key, required this.normalSize, required this.child});

  final Size normalSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context).accessibility.buttonScale;
    if (s == 1) return child;
    return SizedBox(
      width: normalSize.width * s,
      height: normalSize.height * s,
      child: FittedBox(child: child),
    );
  }
}
