import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/features/auth/account_registration_controller.dart';
import 'package:kite/features/auth/account_registration_screen.dart';
import 'package:kite/features/auth/authentication_controller.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:signals/signals_flutter.dart';

typedef AuthenticationQrScanner = Future<String?> Function();

class AuthenticationScreen extends StatefulWidget {
  const AuthenticationScreen({
    required this.gateway,
    this.controller,
    this.onAuthenticated,
    this.scanQrCode,
    this.onRegistrationRequested,
    this.registrationGateway,
    this.initialHomeserver,
    this.expectedUserId,
    this.lockHomeserver = false,
    super.key,
  });

  final AuthenticationGateway gateway;
  final AuthenticationController? controller;
  final ValueChanged<AuthenticatedSession>? onAuthenticated;
  final AuthenticationQrScanner? scanQrCode;
  final ValueChanged<HomeserverAddress>? onRegistrationRequested;
  final AccountRegistrationGateway? registrationGateway;
  final HomeserverAddress? initialHomeserver;
  final String? expectedUserId;
  final bool lockHomeserver;

  @override
  State<AuthenticationScreen> createState() => _AuthenticationScreenState();
}

class _AuthenticationScreenState extends State<AuthenticationScreen>
    with WidgetsBindingObserver {
  late final AuthenticationController _controller;
  late final bool _ownsController;
  late final TextEditingController _homeserverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final Listenable _passwordLoginInputs;
  bool _passwordVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? AuthenticationController(widget.gateway);
    _homeserverController = TextEditingController(
      text: widget.initialHomeserver?.uri.toString() ?? '',
    );
    _usernameController = TextEditingController(
      text: widget.expectedUserId ?? '',
    );
    _passwordController = TextEditingController();
    _passwordLoginInputs = Listenable.merge(<Listenable>[
      _usernameController,
      _passwordController,
    ]);
    final initialHomeserver = widget.initialHomeserver;
    if (initialHomeserver != null) {
      unawaited(_controller.discover(initialHomeserver.uri.toString()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _passwordController.clear();
    _homeserverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || !_passwordVisible || !mounted) {
      return;
    }
    setState(() {
      _passwordVisible = false;
    });
  }

  bool get _canDiscoverHomeserver {
    try {
      HomeserverAddress.parse(_homeserverController.text);
      return true;
    } on AuthenticationInputException {
      return false;
    }
  }

  bool get _canPasswordLogin =>
      _usernameController.text.isNotEmpty &&
      _passwordController.text.isNotEmpty;

  void _discoverHomeserver() {
    if (_controller.isBusy ||
        widget.lockHomeserver ||
        !_canDiscoverHomeserver) {
      return;
    }
    unawaited(_controller.discover(_homeserverController.text));
  }

  void _clearPassword() {
    _passwordVisible = false;
    _passwordController.clear();
  }

  void _togglePasswordVisibility() {
    setState(() {
      _passwordVisible = !_passwordVisible;
    });
  }

  Future<void> _passwordLogin() async {
    if (_controller.isBusy || !_canPasswordLogin) return;
    final password = _passwordController.text;
    _clearPassword();
    await _controller.loginWithPassword(
      username: _usernameController.text,
      password: password,
      expectedUserId: widget.expectedUserId,
    );
    _completeAuthenticationIfNeeded();
  }

  Future<void> _oidcLogin() async {
    _clearPassword();
    await _controller.loginWithOidc(expectedUserId: widget.expectedUserId);
    _completeAuthenticationIfNeeded();
  }

  Future<void> _ssoLogin() async {
    _clearPassword();
    await _controller.loginWithSso(expectedUserId: widget.expectedUserId);
    _completeAuthenticationIfNeeded();
  }

  Future<void> _qrLogin() async {
    final scanner = widget.scanQrCode;
    if (scanner == null || _controller.isBusy) return;
    final qrCodeData = await scanner();
    if (!mounted || qrCodeData == null) return;
    await _controller.loginWithQrCode(qrCodeData);
    _completeAuthenticationIfNeeded();
  }

  void _completeAuthenticationIfNeeded() {
    final authenticatedSession = _controller.session.value;
    if (authenticatedSession == null) return;
    _clearPassword();
    widget.onAuthenticated?.call(authenticatedSession);
  }

  void _changeHomeserver() {
    if (_controller.isBusy) return;
    _usernameController.clear();
    _clearPassword();
    _controller.changeHomeserver();
  }

  Future<void> _requestRegistration(HomeserverAddress homeserver) async {
    _clearPassword();
    final handoff = widget.onRegistrationRequested;
    if (handoff != null) {
      handoff(homeserver);
      return;
    }

    final registrationGateway = widget.registrationGateway;
    if (registrationGateway == null || !mounted) return;
    final registeredSession = await Navigator.of(context)
        .push<AuthenticatedSession>(
          MaterialPageRoute<AuthenticatedSession>(
            builder: (context) => AccountRegistrationScreen(
              homeserver: homeserver,
              gateway: registrationGateway,
              onAuthenticated: (session) => Navigator.of(context).pop(session),
            ),
          ),
        );
    if (!mounted || registeredSession == null) return;
    _clearPassword();
    widget.onAuthenticated?.call(registeredSession);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            key: const Key('authentication-scroll'),
            child: ConstrainedBox(
              key: const Key('authentication-panel'),
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SignalBuilder(
                  builder: (context) {
                    final progress = _controller.progress.value;
                    final methods = _controller.loginMethods.value;
                    final errorMessage = _controller.errorMessage.value;
                    final session = _controller.session.value;
                    final busy = progress != AuthenticationProgress.idle;

                    return AutofillGroup(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          PopScope<void>(
                            canPop: methods == null || widget.lockHomeserver,
                            onPopInvokedWithResult: (didPop, _) {
                              if (!didPop &&
                                  methods != null &&
                                  !widget.lockHomeserver) {
                                _changeHomeserver();
                              }
                            },
                            child: const SizedBox.shrink(),
                          ),
                          Text(
                            'Sign in to Kite',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            key: const Key('auth-subtitle'),
                            height: 48,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                methods == null
                                    ? widget.expectedUserId == null
                                          ? 'Choose the Matrix homeserver that hosts your account.'
                                          : 'Checking ${widget.initialHomeserver?.displayName ?? 'your homeserver'} for ${widget.expectedUserId}.'
                                    : widget.expectedUserId == null
                                    ? 'Continue with ${methods.homeserver.displayName}.'
                                    : 'Sign back in as ${widget.expectedUserId} on ${methods.homeserver.displayName}.',
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (session != null) ...<Widget>[
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                'Signed in as ${session.userId}',
                                key: const Key('authenticated-session'),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ] else if (methods == null) ...<Widget>[
                            TextField(
                              key: const Key('homeserver-field'),
                              controller: _homeserverController,
                              enabled: !busy && !widget.lockHomeserver,
                              autocorrect: false,
                              enableSuggestions: false,
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.done,
                              autofillHints: const <String>[AutofillHints.url],
                              decoration: const InputDecoration(
                                labelText: 'Homeserver',
                                hintText: 'matrix.example.org',
                              ),
                              onChanged: (_) => _controller.clearError(),
                              onSubmitted: busy || widget.lockHomeserver
                                  ? null
                                  : (_) => _discoverHomeserver(),
                            ),
                            const SizedBox(height: 16),
                            ListenableBuilder(
                              listenable: _homeserverController,
                              builder: (context, _) {
                                return FilledButton(
                                  key: const Key('discover-homeserver'),
                                  onPressed:
                                      busy ||
                                          widget.lockHomeserver ||
                                          !_canDiscoverHomeserver
                                      ? null
                                      : _discoverHomeserver,
                                  child: Text(
                                    progress ==
                                            AuthenticationProgress.discovering
                                        ? 'Checking…'
                                        : 'Continue',
                                  ),
                                );
                              },
                            ),
                            if (widget.scanQrCode != null &&
                                !widget.lockHomeserver) ...<Widget>[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                key: const Key('qr-device-login'),
                                onPressed: busy ? null : _qrLogin,
                                icon: const Icon(Icons.qr_code_scanner_rounded),
                                label: const Text('Sign in with QR code'),
                              ),
                            ],
                          ] else ...<Widget>[
                            if (!widget.lockHomeserver)
                              TextButton.icon(
                                key: const Key('change-homeserver'),
                                onPressed: busy ? null : _changeHomeserver,
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Use a different homeserver'),
                              ),
                            if (methods.supports(
                              AuthenticationMethod.password,
                            )) ...<Widget>[
                              const SizedBox(height: 8),
                              TextField(
                                key: const Key('username-field'),
                                controller: _usernameController,
                                enabled: !busy && widget.expectedUserId == null,
                                autofocus: widget.expectedUserId == null,
                                autocorrect: false,
                                textInputAction: TextInputAction.next,
                                autofillHints: const <String>[
                                  AutofillHints.username,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                ),
                                onChanged: (_) => _controller.clearError(),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                key: const Key('password-field'),
                                controller: _passwordController,
                                enabled: !busy,
                                autofocus: widget.expectedUserId != null,
                                obscureText: !_passwordVisible,
                                enableSuggestions: false,
                                autocorrect: false,
                                textInputAction: TextInputAction.done,
                                autofillHints: const <String>[
                                  AutofillHints.password,
                                ],
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  suffixIcon: IconButton(
                                    key: const Key(
                                      'password-visibility-toggle',
                                    ),
                                    tooltip: _passwordVisible
                                        ? 'Hide password'
                                        : 'Show password',
                                    onPressed: busy
                                        ? null
                                        : _togglePasswordVisibility,
                                    icon: Icon(
                                      _passwordVisible
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                ),
                                onChanged: (_) => _controller.clearError(),
                                onSubmitted: busy
                                    ? null
                                    : (_) => _passwordLogin(),
                              ),
                              const SizedBox(height: 16),
                              ListenableBuilder(
                                listenable: _passwordLoginInputs,
                                builder: (context, _) {
                                  return FilledButton(
                                    key: const Key('password-login'),
                                    onPressed: busy || !_canPasswordLogin
                                        ? null
                                        : _passwordLogin,
                                    child: Text(
                                      progress ==
                                              AuthenticationProgress.signingIn
                                          ? 'Signing in…'
                                          : 'Sign in',
                                    ),
                                  );
                                },
                              ),
                            ],
                            if (methods.supports(
                              AuthenticationMethod.oidc,
                            )) ...<Widget>[
                              const SizedBox(height: 12),
                              OutlinedButton(
                                key: const Key('oidc-login'),
                                onPressed: busy ? null : _oidcLogin,
                                child: const Text('Continue with OIDC'),
                              ),
                            ],
                            if (methods.supports(
                              AuthenticationMethod.sso,
                            )) ...<Widget>[
                              const SizedBox(height: 12),
                              OutlinedButton(
                                key: const Key('sso-login'),
                                onPressed: busy ? null : _ssoLogin,
                                child: const Text('Continue with SSO'),
                              ),
                            ],
                            if (methods.registrationAvailable &&
                                !widget.lockHomeserver) ...<Widget>[
                              const SizedBox(height: 12),
                              if (widget.onRegistrationRequested == null &&
                                  widget.registrationGateway == null)
                                Text(
                                  'This homeserver also supports account registration.',
                                  key: const Key('registration-available'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                )
                              else
                                TextButton.icon(
                                  key: const Key('registration-available'),
                                  onPressed: busy
                                      ? null
                                      : () => _requestRegistration(
                                          methods.homeserver,
                                        ),
                                  icon: const Icon(
                                    Icons.person_add_alt_1_outlined,
                                  ),
                                  label: const Text('Create an account'),
                                ),
                            ],
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 44,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  errorMessage ?? '',
                                  key: const Key('authentication-error'),
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
}
