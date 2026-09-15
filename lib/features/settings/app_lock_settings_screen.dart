import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:signals/signals_flutter.dart';

class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({
    required this.controller,
    this.loadOnInit = true,
    super.key,
  });

  final AppLockController controller;
  final bool loadOnInit;

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _hideNotificationContents = true;

  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) {
      widget.controller.load();
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App lock')),
      body: SignalBuilder(
        builder: (context) {
          final settings = widget.controller.settings.value;
          final busy = widget.controller.isBusy.value;
          final error = widget.controller.errorMessage.value;

          return ListView(
            key: const Key('app-lock-settings-list'),
            padding: const EdgeInsets.only(bottom: 24),
            children: <Widget>[
              if (!settings.enabled) ...<Widget>[
                const _SectionTitle(label: 'Set up app lock'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    key: const Key('app-lock-pin'),
                    controller: _pinController,
                    enabled: !busy,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(64),
                    ],
                    autofillHints: const <String>[],
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      helperText: 'Use 4 to 64 digits.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    key: const Key('app-lock-pin-confirm'),
                    controller: _confirmPinController,
                    enabled: !busy,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(64),
                    ],
                    autofillHints: const <String>[],
                    decoration: const InputDecoration(labelText: 'Confirm PIN'),
                  ),
                ),
                SwitchListTile(
                  key: const Key('app-lock-setup-hide-notifications'),
                  value: _hideNotificationContents,
                  onChanged: busy
                      ? null
                      : (value) {
                          setState(() => _hideNotificationContents = value);
                        },
                  title: const Text('Hide notification contents while locked'),
                  subtitle: const Text(
                    'Notifications can still arrive without exposing message text.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: FilledButton(
                    key: const Key('enable-app-lock'),
                    onPressed: busy ? null : _enableAppLock,
                    child: const Text('Enable app lock'),
                  ),
                ),
              ] else ...<Widget>[
                const _SectionTitle(label: 'Unlock'),
                SwitchListTile(
                  key: const Key('app-lock-biometrics'),
                  value: settings.biometricsEnabled,
                  onChanged: busy
                      ? null
                      : widget.controller.setBiometricsEnabled,
                  title: const Text('Biometric unlock'),
                  subtitle: const Text(
                    'Use the device biometric prompt after app lock is enabled.',
                  ),
                ),
                const Divider(height: 1),
                const _SectionTitle(label: 'Privacy'),
                SwitchListTile(
                  key: const Key('app-lock-hide-notifications'),
                  value: settings.hideNotificationContents,
                  onChanged: busy
                      ? null
                      : widget.controller.setHideNotificationContents,
                  title: const Text('Hide notification contents while locked'),
                  subtitle: const Text(
                    'Kite can show a generic notification until the app is unlocked.',
                  ),
                ),
                const Divider(height: 1),
                const _SectionTitle(label: 'Disable app lock'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    key: const Key('disable-app-lock-pin'),
                    controller: _pinController,
                    enabled: !busy,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(64),
                    ],
                    autofillHints: const <String>[],
                    decoration: const InputDecoration(labelText: 'Current PIN'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: OutlinedButton(
                    key: const Key('disable-app-lock'),
                    onPressed: busy ? null : _disableAppLock,
                    child: const Text('Disable app lock'),
                  ),
                ),
              ],
              SizedBox(
                key: const Key('app-lock-settings-status'),
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

  Future<void> _enableAppLock() async {
    final pin = _pinController.text;
    final confirmation = _confirmPinController.text;
    if (pin != confirmation) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('PINs do not match.')));
      return;
    }

    _pinController.clear();
    _confirmPinController.clear();
    await widget.controller.enableWithPin(
      pin: pin,
      hideNotificationContents: _hideNotificationContents,
    );
  }

  Future<void> _disableAppLock() async {
    final pin = _pinController.text;
    _pinController.clear();
    _confirmPinController.clear();
    await widget.controller.disable(pin);
  }
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
