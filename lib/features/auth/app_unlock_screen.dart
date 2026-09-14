import 'package:flutter/material.dart';
import 'package:kite/features/auth/app_lock_controller.dart';
import 'package:signals/signals_flutter.dart';

class AppUnlockScreen extends StatefulWidget {
  const AppUnlockScreen({required this.controller, this.onUnlocked, super.key});

  final AppLockController controller;
  final VoidCallback? onUnlocked;

  @override
  State<AppUnlockScreen> createState() => _AppUnlockScreenState();
}

class _AppUnlockScreenState extends State<AppUnlockScreen> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SignalBuilder(
                builder: (context) {
                  final settings = widget.controller.settings.value;
                  final busy = widget.controller.isBusy.value;
                  final error = widget.controller.errorMessage.value;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Unlock Kite',
                        key: const Key('app-unlock-heading'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter your app lock PIN to continue.',
                        key: Key('app-unlock-subtitle'),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        key: const Key('app-unlock-pin'),
                        controller: _pinController,
                        enabled: !busy,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const <String>[],
                        onSubmitted: busy ? null : (_) => _unlockWithPin(),
                        decoration: const InputDecoration(labelText: 'PIN'),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const Key('app-unlock-pin-submit'),
                        onPressed: busy ? null : _unlockWithPin,
                        child: const Text('Unlock'),
                      ),
                      if (settings.biometricsEnabled) ...<Widget>[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          key: const Key('app-unlock-biometrics'),
                          onPressed: busy ? null : _unlockWithBiometrics,
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('Use biometrics'),
                        ),
                      ],
                      SizedBox(
                        key: const Key('app-unlock-status'),
                        height: 56,
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
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _unlockWithPin() async {
    if (!await widget.controller.unlockWithPin(_pinController.text) ||
        !mounted) {
      return;
    }
    _pinController.clear();
    widget.onUnlocked?.call();
  }

  Future<void> _unlockWithBiometrics() async {
    if (!await widget.controller.unlockWithBiometrics() || !mounted) return;
    _pinController.clear();
    widget.onUnlocked?.call();
  }
}
