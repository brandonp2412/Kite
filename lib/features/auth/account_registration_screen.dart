import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/features/auth/account_registration_controller.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:signals/signals_flutter.dart';

class AccountRegistrationScreen extends StatefulWidget {
  const AccountRegistrationScreen({
    required this.homeserver,
    required this.gateway,
    this.controller,
    this.onAuthenticated,
    super.key,
  });

  final HomeserverAddress homeserver;
  final AccountRegistrationGateway gateway;
  final AccountRegistrationController? controller;
  final ValueChanged<AuthenticatedSession>? onAuthenticated;

  @override
  State<AccountRegistrationScreen> createState() =>
      _AccountRegistrationScreenState();
}

class _AccountRegistrationScreenState extends State<AccountRegistrationScreen> {
  late final AccountRegistrationController _controller;
  late final bool _ownsController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        AccountRegistrationController(
          homeserver: widget.homeserver,
          gateway: widget.gateway,
        );
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    if (_controller.step.value == null) {
      unawaited(_begin());
    }
  }

  Future<void> _begin() async {
    await _controller.begin();
    _completeIfNeeded();
  }

  Future<void> _submitCredentials() async {
    final password = _passwordController.text;
    _passwordController.clear();
    final succeeded = await _controller.submitCredentials(
      username: _usernameController.text,
      password: password,
    );
    if (succeeded) _completeIfNeeded();
  }

  Future<void> _continueInteractive() async {
    final succeeded = await _controller.continueInteractiveAuthentication();
    if (succeeded) _completeIfNeeded();
  }

  void _completeIfNeeded() {
    if (!mounted) return;
    final current = _controller.step.value;
    if (current case RegistrationCompleteStep(:final session)) {
      widget.onAuthenticated?.call(session);
    }
  }

  @override
  void dispose() {
    _passwordController.clear();
    _usernameController.dispose();
    _passwordController.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SignalBuilder(
                  builder: (context) {
                    final current = _controller.step.value;
                    final busy = _controller.isBusy.value;
                    final error = _controller.errorMessage.value;

                    return AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            'Join ${widget.homeserver.displayName}',
                            key: const Key('registration-heading'),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            key: const Key('registration-status-slot'),
                            height: 56,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(_statusText(current, busy)),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            key: const Key('registration-action-slot'),
                            height: 192,
                            child: _RegistrationAction(
                              step: current,
                              busy: busy,
                              usernameController: _usernameController,
                              passwordController: _passwordController,
                              onSubmitCredentials: _submitCredentials,
                              onContinueInteractive: _continueInteractive,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 44,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  error ?? '',
                                  key: const Key('registration-error'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _statusText(AccountRegistrationStep? current, bool busy) {
    if (current == null) {
      return busy
          ? 'Checking registration options…'
          : 'Preparing registration…';
    }
    return switch (current) {
      RegistrationCredentialsStep() =>
        'Choose the username and password for your Matrix account.',
      RegistrationInteractiveStep(:final publicInstructions) =>
        publicInstructions,
      RegistrationCompleteStep(:final session) =>
        'Account created as ${session.userId}.',
    };
  }
}

class _RegistrationAction extends StatelessWidget {
  const _RegistrationAction({
    required this.step,
    required this.busy,
    required this.usernameController,
    required this.passwordController,
    required this.onSubmitCredentials,
    required this.onContinueInteractive,
  });

  final AccountRegistrationStep? step;
  final bool busy;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final VoidCallback onSubmitCredentials;
  final VoidCallback onContinueInteractive;

  @override
  Widget build(BuildContext context) {
    return switch (step) {
      null => const Center(child: CircularProgressIndicator()),
      RegistrationCredentialsStep() => Column(
        children: <Widget>[
          TextField(
            key: const Key('registration-username'),
            controller: usernameController,
            enabled: !busy,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[AutofillHints.newUsername],
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('registration-password'),
            controller: passwordController,
            enabled: !busy,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.newPassword],
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: busy ? null : (_) => onSubmitCredentials(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('registration-submit-credentials'),
            onPressed: busy ? null : onSubmitCredentials,
            child: Text(busy ? 'Creating…' : 'Create account'),
          ),
        ],
      ),
      RegistrationInteractiveStep() => Align(
        alignment: Alignment.topCenter,
        child: FilledButton.icon(
          key: const Key('registration-continue-interactive'),
          onPressed: busy ? null : onContinueInteractive,
          icon: const Icon(Icons.verified_user_outlined),
          label: Text(busy ? 'Continuing…' : 'Continue registration'),
        ),
      ),
      RegistrationCompleteStep(:final session) => Semantics(
        liveRegion: true,
        child: Center(
          child: Text(
            'Signed in as ${session.userId}',
            key: const Key('registration-complete'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    };
  }
}
