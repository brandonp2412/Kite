import 'package:flutter/material.dart';
import 'package:kite/features/settings/settings_controller.dart';
import 'package:kite/features/settings/settings_layout.dart';
import 'package:signals/signals_flutter.dart';

final class KiteLanguageOption {
  const KiteLanguageOption({required this.tag, required this.label})
    : assert(tag != ''),
      assert(label != '');

  final String tag;
  final String label;
}

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({
    required this.controller,
    this.languages = const <KiteLanguageOption>[
      KiteLanguageOption(tag: 'en', label: 'English'),
      KiteLanguageOption(tag: 'en-NZ', label: 'English (New Zealand)'),
    ],
    this.loadOnInit = true,
    super.key,
  });

  final SettingsController controller;
  final List<KiteLanguageOption> languages;
  final bool loadOnInit;

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  static const String _systemLanguage = '__kite_system_language__';

  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) {
      widget.controller.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('General')),
      body: SignalBuilder(
        builder: (context) {
          final settings = widget.controller.settings.value;
          final busy =
              widget.controller.isLoading.value ||
              widget.controller.isSaving.value;
          final error = widget.controller.errorMessage.value;
          final languageTag = settings.languageTag;
          final supportedLanguageTags = widget.languages
              .map((option) => option.tag)
              .toSet();
          final selectedLanguage =
              languageTag != null && supportedLanguageTags.contains(languageTag)
              ? languageTag
              : _systemLanguage;

          return ListView(
            key: const Key('general-settings-list'),
            padding: SettingsLayout.listPadding(context),
            children: <Widget>[
              const _SectionTitle(label: 'Appearance'),
              RadioGroup<KiteAppearanceMode>(
                groupValue: settings.appearanceMode,
                onChanged: (selected) {
                  if (!busy && selected != null) {
                    widget.controller.setAppearance(selected);
                  }
                },
                child: Column(
                  children: <Widget>[
                    for (final mode in KiteAppearanceMode.values)
                      RadioListTile<KiteAppearanceMode>(
                        key: Key('appearance-${mode.name}'),
                        value: mode,
                        enabled: !busy,
                        title: Text(_appearanceLabel(mode)),
                        subtitle: mode == KiteAppearanceMode.black
                            ? const Text(
                                'Use a true-black background where supported.',
                              )
                            : null,
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const _SectionTitle(label: 'Language'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'App language'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const Key('language-picker'),
                      value: selectedLanguage,
                      isExpanded: true,
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem<String>(
                          value: _systemLanguage,
                          child: Text('Use system language'),
                        ),
                        ...widget.languages.map(
                          (option) => DropdownMenuItem<String>(
                            value: option.tag,
                            child: Text(option.label),
                          ),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (selected) {
                              if (selected == null) return;
                              widget.controller.setLanguage(
                                selected == _systemLanguage ? null : selected,
                              );
                            },
                    ),
                  ),
                ),
              ),
              SizedBox(
                key: const Key('general-settings-status'),
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error ?? '',
                        style: TextStyle(
                          color: error == null
                              ? null
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _appearanceLabel(KiteAppearanceMode mode) => switch (mode) {
    KiteAppearanceMode.system => 'System',
    KiteAppearanceMode.light => 'Light',
    KiteAppearanceMode.dark => 'Dark',
    KiteAppearanceMode.black => 'Black',
  };
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
