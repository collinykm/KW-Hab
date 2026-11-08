import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kw_hab/monitoring/staff_notifier.dart';
import 'package:kw_hab/screens/onboarding/onboarding_screen.dart';
import 'package:kw_hab/settings/accessibility_settings.dart';
import 'package:kw_hab/settings/accessibility_theme.dart';
import 'package:kw_hab/settings/app_settings.dart';
import 'package:kw_hab/settings/page_settings_bridge.dart';
import 'package:kw_hab/settings/settings_scope.dart';
import 'package:kw_hab/settings/settings_storage.dart';
import 'package:kw_hab/settings/support_contact.dart';

const sam = SupportContact(
  id: 'a',
  name: 'Sam',
  phone: '519-555-0100',
  email: 'sam@example.org',
  preferredMethod: ContactMethod.email,
);

void main() {
  group('AccessibilitySettings', () {
    test('round-trips through JSON', () {
      const a = AccessibilitySettings(
          textScale: 1.5, boldText: true, buttonScale: 1.25, readAloud: true, talkToType: true);
      expect(AccessibilitySettings.fromJson(a.toJson()), a);
    });

    test('falls back to defaults on bad input and clamps scales', () {
      expect(AccessibilitySettings.fromJson('nope'), const AccessibilitySettings());
      final a = AccessibilitySettings.fromJson({'textScale': 9, 'buttonScale': 'big', 'boldText': 1});
      expect(a.textScale, AccessibilitySettings.maxTextScale);
      expect(a.buttonScale, 1.0);
      expect(a.boldText, isFalse);
    });
  });

  group('SupportContact', () {
    test('round-trips through JSON', () {
      expect(SupportContact.fromJson(sam.toJson()), sam);
    });

    test('contactMethod falls back when the preferred details are blank', () {
      const c = SupportContact(id: 'b', phone: '123', preferredMethod: ContactMethod.email);
      expect(c.contactMethod, ContactMethod.phone);
      expect(sam.contactMethod, ContactMethod.email);
      expect(const SupportContact(id: 'c', name: 'No details').contactMethod, isNull);
    });

    test('reads the older multi-choice format', () {
      final c = SupportContact.fromJson({'id': 'd', 'email': 'x@y.z', 'preferredMethods': ['email']});
      expect(c!.preferredMethod, ContactMethod.email);
    });

    test('alertRecipients: one delivery per reachable person', () {
      final r = alertRecipients([sam, const SupportContact(id: 'empty', name: 'Jo')]);
      expect(r.map((x) => (x.contact.name, x.method, x.address)),
          [('Sam', ContactMethod.email, 'sam@example.org')]);
    });
  });

  group('AppSettings', () {
    test('saves changes and loads them back', () async {
      final storage = MemorySettingsStorage();
      final s = AppSettings(storage: storage);
      s.updateAccessibility((a) => a.copyWith(textScale: 1.75, boldText: true));
      s.supportContacts = [sam, const SupportContact(id: 'blank')];
      s.completeOnboarding();
      await s.flush();

      final loaded = AppSettings(storage: storage);
      await loaded.load();
      expect(loaded.accessibility.textScale, 1.75);
      expect(loaded.accessibility.boldText, isTrue);
      expect(loaded.supportContacts, [sam], reason: 'blank contacts are dropped');
      expect(loaded.onboardingComplete, isTrue);
    });

    test('starts with defaults and onboarding not done', () async {
      final s = AppSettings(storage: MemorySettingsStorage());
      await s.load();
      expect(s.onboardingComplete, isFalse);
      expect(s.accessibility, const AccessibilitySettings());
    });

    test('coalesces rapid changes into few writes', () async {
      final storage = MemorySettingsStorage();
      final s = AppSettings(storage: storage);
      for (var i = 1; i <= 20; i++) {
        s.updateAccessibility((a) => a.copyWith(textScale: 1 + i / 20));
      }
      await s.flush();
      expect(storage.writes, lessThanOrEqualTo(2));
      expect((storage.saved!['accessibility'] as Map)['textScale'], 2.0);
    });

    test('notifies listeners only on real changes', () {
      final s = AppSettings(storage: MemorySettingsStorage());
      var n = 0;
      s.addListener(() => n++);
      s.updateAccessibility((a) => a);
      s.updateAccessibility((a) => a.copyWith(readAloud: true));
      expect(n, 1);
    });
  });

  group('FileSettingsStorage', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('kw_settings'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes and reads JSON; corrupt file reads as nothing', () async {
      final file = File('${dir.path}/settings.json');
      final storage = FileSettingsStorage(file);
      expect(await storage.read(), isNull);
      await storage.write({'onboardingComplete': true});
      expect(await storage.read(), {'onboardingComplete': true});

      file.writeAsStringSync('{not json');
      expect(await FileSettingsStorage(file).read(), isNull);
      expect(File('${file.path}.corrupt').existsSync(), isTrue);
    });
  });

  test('page script carries accessibility settings but no contacts', () {
    final s = AppSettings(storage: MemorySettingsStorage())..supportContacts = [sam];
    final script = PageSettingsBridge.scriptFor(s.accessibility.toPageJson());
    expect(script, contains('"textScale":1.0'));
    expect(script, contains('window.__kwHabSettings'));
    expect(script, isNot(contains('Sam')));
  });

  testWidgets('onboarding applies settings live and saves contacts on Done', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettings(storage: MemorySettingsStorage());
    await tester.pumpWidget(SettingsScope(
      settings: settings,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          theme: buildAppTheme(settings.accessibility),
          builder: (context, child) =>
              applyAccessibilityMediaQuery(context, settings.accessibility, child!),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => OnboardingScreen.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('boldText')));
    await tester.pump();
    expect(settings.accessibility.boldText, isTrue);
    final context = tester.element(find.text('This is how text will look.'));
    expect(MediaQuery.boldTextOf(context), isTrue);

    // Drag the text-size slider all the way right.
    final slider = find.descendant(of: find.byKey(const Key('textScale')), matching: find.byType(Slider));
    await tester.drag(slider, const Offset(2000, 0));
    await tester.pump();
    expect(settings.accessibility.textScale, AccessibilitySettings.maxTextScale);
    expect(MediaQuery.textScalerOf(context).scale(10), 20);

    await tester.ensureVisible(find.byKey(const Key('contact0-name')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('contact0-name')), 'Sam');
    await tester.ensureVisible(find.byKey(const Key('contact0-phone')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('contact0-phone')), '519-555-0100');
    await tester.ensureVisible(find.byKey(const Key('contact0-prefers-phone')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('contact0-prefers-phone')));
    await tester.ensureVisible(find.byKey(const Key('addContact')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('addContact')));
    await tester.pump();
    expect(find.byKey(const Key('contact1-name')), findsOneWidget);
    expect(settings.supportContacts, isEmpty, reason: 'contacts save on Done');

    await tester.ensureVisible(find.byKey(const Key('finishOnboarding')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('finishOnboarding')));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(settings.onboardingComplete, isTrue);
    expect(settings.supportContacts, hasLength(1));
    final saved = settings.supportContacts.single;
    expect((saved.name, saved.phone), ('Sam', '519-555-0100'));
    expect(saved.preferredMethod, ContactMethod.phone);
  });

  testWidgets('settings screen fits at the largest text and button sizes', (tester) async {
    final settings = AppSettings(storage: MemorySettingsStorage())
      ..updateAccessibility((a) => a.copyWith(
            textScale: AccessibilitySettings.maxTextScale,
            buttonScale: AccessibilitySettings.maxButtonScale,
            boldText: true,
          ))
      ..supportContacts = [
        const SupportContact(
          id: 'long',
          name: 'Samantha Richardson-Montgomery',
          phone: '519-555-0100',
          email: 'samantha.richardson@example.org',
          preferredMethod: ContactMethod.email,
        ),
      ];
    // A wide and a narrow window, each tall enough to lay out every card.
    for (final width in [1342.0, 600.0]) {
      tester.view.physicalSize = Size(width, 6000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(SettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: buildAppTheme(settings.accessibility),
          builder: (context, child) =>
              applyAccessibilityMediaQuery(context, settings.accessibility, child!),
          home: const OnboardingScreen(firstRun: true),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px wide');
      expect(find.byKey(const Key('finishOnboarding')).hitTestable(), findsOneWidget);
    }
    tester.view.reset();
  });
}
