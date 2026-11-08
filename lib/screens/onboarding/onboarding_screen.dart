import 'package:flutter/material.dart';

import '../../settings/accessibility_settings.dart';
import '../../settings/accessibility_theme.dart';
import '../../settings/app_settings.dart';
import '../../settings/settings_scope.dart';
import '../../settings/support_contact.dart';

/// First-run setup, done by the user together with their support person.
/// Also reopened later from the app menu (Settings…, ⌘,).
///
/// Accessibility choices apply immediately (the whole app, including this
/// screen, changes as you move a slider) and are saved as they change.
/// Support people are saved when "Done" is pressed.
///
/// Styled after Facebook's settings pages (grey page, white cards) so it feels
/// like part of the same app.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.firstRun = true});

  /// True the first time (after the first Facebook login); false when opened
  /// from Settings. Only changes the wording.
  final bool firstRun;

  /// Pushes the screen over the Facebook window. Completes when it closes.
  static Future<void> show(BuildContext context, {bool firstRun = true}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        settings: const RouteSettings(name: routeName),
        builder: (_) => OnboardingScreen(firstRun: firstRun),
      ));

  static const String routeName = '/onboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final AppSettings _settings;
  final List<_ContactDraft> _contacts = [];

  @override
  void initState() {
    super.initState();
    // Not SettingsScope.of: initState can't depend on inherited widgets.
    _settings = context.findAncestorWidgetOfExactType<SettingsScope>()!.notifier!;
    for (final c in _settings.supportContacts) {
      _contacts.add(_ContactDraft.from(c));
    }
    if (_contacts.isEmpty) _contacts.add(_ContactDraft.empty());
  }

  @override
  void dispose() {
    for (final c in _contacts) {
      c.dispose();
    }
    super.dispose();
  }

  void _finish() {
    _settings.supportContacts = [for (final c in _contacts) c.toContact()];
    _settings.completeOnboarding();
    Navigator.of(context).pop();
  }

  void _update(AccessibilitySettings Function(AccessibilitySettings) f) =>
      _settings.updateAccessibility(f);

  @override
  Widget build(BuildContext context) {
    final a = SettingsScope.of(context).accessibility;
    final doneLabel = widget.firstRun ? 'Done, start using the app' : 'Done';

    return PopScope(
      // Leave only through "Done", so support people are never lost.
      canPop: false,
      child: Scaffold(
        body: Column(
          children: [
            _TopBar(
              title: widget.firstRun ? 'Set up your app' : 'Settings',
              action: FilledButton(onPressed: _finish, child: const Text('Done')),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                children: [
                  _Column(children: [
                    _IntroCard(firstRun: widget.firstRun),
                    _SectionCard(
                      title: 'Seeing and reading',
                      children: [
                        _SliderRow(
                          key: const Key('textScale'),
                          icon: Icons.format_size,
                          title: 'Text size',
                          subtitle: 'Make words bigger and easier to read.',
                          value: a.textScale,
                          min: AccessibilitySettings.minTextScale,
                          max: AccessibilitySettings.maxTextScale,
                          onChanged: (v) => _update((a) => a.copyWith(textScale: v)),
                          preview: const _TextPreview(),
                        ),
                        const Divider(),
                        _SwitchRow(
                          key: const Key('boldText'),
                          icon: Icons.format_bold,
                          title: 'Bold text',
                          subtitle: 'Make all words thicker and easier to see.',
                          value: a.boldText,
                          onChanged: (v) => _update((a) => a.copyWith(boldText: v)),
                        ),
                        const Divider(),
                        _SliderRow(
                          key: const Key('buttonScale'),
                          icon: Icons.touch_app_outlined,
                          title: 'Button size',
                          subtitle: 'Make buttons bigger and easier to click.',
                          value: a.buttonScale,
                          min: AccessibilitySettings.minButtonScale,
                          max: AccessibilitySettings.maxButtonScale,
                          onChanged: (v) => _update((a) => a.copyWith(buttonScale: v)),
                          preview: Wrap(spacing: 8, runSpacing: 8, children: [
                            FilledButton(onPressed: () {}, child: const Text('Like')),
                            ElevatedButton(onPressed: () {}, child: const Text('Comment')),
                          ]),
                        ),
                      ],
                    ),
                    _SectionCard(
                      title: 'Listening and speaking',
                      children: [
                        _SwitchRow(
                          key: const Key('readAloud'),
                          icon: Icons.volume_up_outlined,
                          title: 'Read text aloud',
                          subtitle: 'The app can read posts and messages out loud to you.',
                          value: a.readAloud,
                          onChanged: (v) => _update((a) => a.copyWith(readAloud: v)),
                        ),
                        const Divider(),
                        _SwitchRow(
                          key: const Key('talkToType'),
                          icon: Icons.mic_none,
                          title: 'Talk to type',
                          subtitle: 'Say what you want to write instead of typing it.',
                          value: a.talkToType,
                          onChanged: (v) => _update((a) => a.copyWith(talkToType: v)),
                        ),
                      ],
                    ),
                    _SectionCard(
                      title: 'Support people',
                      subtitle: 'The people who help you. The app will contact them if it looks like '
                          'someone online is trying to trick or hurt you.',
                      children: [
                        for (final (i, draft) in _contacts.indexed) ...[
                          if (i > 0) const Divider(),
                          _ContactEditor(
                            key: ObjectKey(draft),
                            index: i,
                            draft: draft,
                            onChanged: () => setState(() {}),
                            onRemove: () => setState(() {
                              _contacts.remove(draft);
                              draft.dispose();
                              if (_contacts.isEmpty) _contacts.add(_ContactDraft.empty());
                            }),
                          ),
                        ],
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              key: const Key('addContact'),
                              onPressed: () => setState(() => _contacts.add(_ContactDraft.empty())),
                              icon: const Icon(Icons.person_add_alt_1),
                              label: const Text('Add another person'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('finishOnboarding'),
                        onPressed: _finish,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        child: Text(doneLabel),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White bar across the top, like Facebook's header.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.action});

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KwColors.card,
      elevation: 1,
      shadowColor: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 20,
              backgroundColor: KwColors.blue,
              child: Icon(Icons.tune, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
            ),
            action,
          ],
        ),
      ),
    );
  }
}

/// Centres content in a Facebook-width column with gaps between cards.
class _Column extends StatelessWidget {
  const _Column({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 16), c],
            ],
          ),
        ),
      );
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.firstRun});

  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(firstRun ? 'Welcome! Let’s set up the app' : 'Your settings', style: text.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Go through this page together with your support person. '
              'Choose what makes the app easiest for you to see, hear and use.',
              style: text.bodyLarge?.copyWith(color: KwColors.secondaryText),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KwColors.blueTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, color: KwColors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Each change happens right away, so you can try it and see. '
                      'You can come back any time: in the menu bar, choose Settings… '
                      '(or press ⌘ and comma).',
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, this.subtitle, required this.children});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: text.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: text.bodyMedium?.copyWith(color: KwColors.secondaryText)),
            ],
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Grey circle with an icon, like the icons in Facebook's menus.
class _RowIcon extends StatelessWidget {
  const _RowIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 20,
        backgroundColor: KwColors.secondaryButton,
        child: Icon(icon, color: KwColors.primaryText, size: 22),
      );
}

class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.title, required this.subtitle, this.trailing});

  final String title;
  final String subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: text.titleMedium)),
            if (trailing != null)
              Text(trailing!, style: text.titleMedium?.copyWith(color: KwColors.blue)),
          ],
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: text.bodyMedium?.copyWith(color: KwColors.secondaryText)),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              _RowIcon(icon),
              const SizedBox(width: 12),
              Expanded(child: _RowLabel(title: title, subtitle: subtitle)),
              const SizedBox(width: 12),
              ScaledControl(
                normalSize: const Size(60, 40),
                child: Switch(value: value, onChanged: onChanged),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.preview,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final percent = '${(value * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RowIcon(icon),
              const SizedBox(width: 12),
              Expanded(child: _RowLabel(title: title, subtitle: subtitle, trailing: percent)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('A', style: TextStyle(fontSize: 14, color: KwColors.secondaryText)),
              Expanded(
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  // 25% steps: 100%, 125%, … 200%.
                  divisions: ((max - min) / 0.25).round(),
                  semanticFormatterCallback: (_) => percent,
                  onChanged: onChanged,
                ),
              ),
              const Text('A', style: TextStyle(fontSize: 26, color: KwColors.secondaryText)),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KwColors.pageBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: preview,
          ),
        ],
      ),
    );
  }
}

/// A tiny Facebook-post lookalike, so text changes are easy to judge.
class _TextPreview extends StatelessWidget {
  const _TextPreview();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 18,
          backgroundColor: KwColors.secondaryButton,
          child: Icon(Icons.person, color: KwColors.secondaryText),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Alex', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text('This is how text will look.', style: text.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}

/// Editable copy of a [SupportContact] while the screen is open.
class _ContactDraft {
  _ContactDraft._(this.id, String name, String phone, String email, this.method)
      : name = TextEditingController(text: name),
        phone = TextEditingController(text: phone),
        email = TextEditingController(text: email);

  factory _ContactDraft.empty() => _ContactDraft._(SupportContact.newId(), '', '', '', null);

  factory _ContactDraft.from(SupportContact c) =>
      _ContactDraft._(c.id, c.name, c.phone, c.email, c.preferredMethod);

  final String id;
  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController email;
  ContactMethod? method;

  SupportContact toContact() => SupportContact(
        id: id,
        name: name.text.trim(),
        phone: phone.text.trim(),
        email: email.text.trim(),
        preferredMethod: method,
      );

  void dispose() {
    name.dispose();
    phone.dispose();
    email.dispose();
  }
}

class _ContactEditor extends StatelessWidget {
  const _ContactEditor({
    super.key,
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _ContactDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = draft.name.text.trim();

    Widget methodOption(ContactMethod m, IconData icon, String label) {
      final selected = draft.method == m;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            draft.method = m;
            onChanged();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? KwColors.blueTint : null,
              border: Border.all(color: selected ? KwColors.blue : KwColors.inputBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                ScaledControl(
                  normalSize: const Size(40, 40),
                  child: Radio<ContactMethod>(key: Key('contact$index-prefers-${m.name}'), value: m),
                ),
                Icon(icon, size: 20 * SettingsScope.of(context).accessibility.buttonScale,
                    color: selected ? KwColors.blue : KwColors.secondaryText),
                const SizedBox(width: 6),
                Text(label, style: text.bodyLarge),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: KwColors.blueTint,
                child: name.isEmpty
                    ? const Icon(Icons.person_outline, color: KwColors.blue)
                    : Text(name.characters.first.toUpperCase(),
                        style: const TextStyle(color: KwColors.blue, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(name.isEmpty ? 'Person ${index + 1}' : name, style: text.titleMedium),
              ),
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: Key('contact$index-name'),
            controller: draft.name,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            key: Key('contact$index-phone'),
            controller: draft.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          TextField(
            key: Key('contact$index-email'),
            controller: draft.email,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          Text('Best way to contact them', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          RadioGroup<ContactMethod>(
            groupValue: draft.method,
            onChanged: (m) {
              draft.method = m;
              onChanged();
            },
            child: Row(
              children: [
                methodOption(ContactMethod.phone, Icons.phone_outlined, 'Phone'),
                const SizedBox(width: 12),
                methodOption(ContactMethod.email, Icons.email_outlined, 'Email'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
