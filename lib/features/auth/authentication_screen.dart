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
    super.key,
  });

  final AuthenticationGateway gateway;
  final AuthenticationController? controller;
  final ValueChanged<AuthenticatedSession>? onAuthenticated;
  final AuthenticationQrScanner? scanQrCode;
  final ValueChanged<HomeserverAddress>? onRegistrationRequested;
  final AccountRegistrationGateway? registrationGateway;

  @override
  State<AuthenticationScreen> createState() => _AuthenticationScreenState();
}

class _AuthenticationScreenState extends State<AuthenticationScreen> {
  late final AuthenticationController _controller;
  late final bool _ownsController;
  late final TextEditingController _homeserverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? AuthenticationController(widget.gateway);
    _homeserverController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _homeserverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _passwordLogin() async {
    await _controller.loginWithPassword(
      username: _usernameController.text,
      password: _passwordController.text,
    );
    _completeAuthenticationIfNeeded();
  }

  Future<void> _oidcLogin() async {
    await _controller.loginWithOidc();
    _completeAuthenticationIfNeeded();
  }

  Future<void> _ssoLogin() async {
    await _controller.loginWithSso();
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
    _passwordController.clear();
    widget.onAuthenticated?.call(authenticatedSession);
  }

  Future<void> _requestRegistration(HomeserverAddress homeserver) async {
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
    _passwordController.clear();
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
                                    ? 'Choose the Matrix homeserver that hosts your account.'
                                    : 'Continue with ${methods.homeserver.displayName}.',
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (methods == null) ...<Widget>[
                            TextField(
                              key: const Key('homeserver-field'),
                              controller: _homeserverController,
                              enabled: !busy,
                              autocorrect: false,
                              enableSuggestions: false,
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.done,
                              autofillHints: const <String>[AutofillHints.url],
                              decoration: const InputDecoration(
                                labelText: 'Homeserver',
                                hintText: 'matrix.example.org',
                              ),
                              onSubmitted: busy ? null : _controller.discover,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              key: const Key('discover-homeserver'),
                              onPressed: busy
                                  ? null
                                  : () => _controller.discover(
                                      _homeserverController.text,
                                    ),
                              child: Text(
                                progress == AuthenticationProgress.discovering
                                    ? 'Checking…'
                                    : 'Continue',
                              ),
                            ),
                            if (widget.scanQrCode != null) ...<Widget>[
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                key: const Key('qr-device-login'),
                                onPressed: busy ? null : _qrLogin,
                                icon: const Icon(Icons.qr_code_scanner_rounded),
                                label: const Text('Sign in with QR code'),
                              ),
                            ],
                          ] else if (session == null) ...<Widget>[
                            TextButton.icon(
                              key: const Key('change-homeserver'),
                              onPressed: busy
                                  ? null
                                  : _controller.changeHomeserver,
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
                                enabled: !busy,
                                autocorrect: false,
                                textInputAction: TextInputAction.next,
                                autofillHints: const <String>[
                                  AutofillHints.username,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                key: const Key('password-field'),
                                controller: _passwordController,
                                enabled: !busy,
                                obscureText: true,
                                enableSuggestions: false,
                                autocorrect: false,
                                textInputAction: TextInputAction.done,
                                autofillHints: const <String>[
                                  AutofillHints.password,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                ),
                                onSubmitted: busy
                                    ? null
                                    : (_) => _passwordLogin(),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                key: const Key('password-login'),
                                onPressed: busy ? null : _passwordLogin,
                                child: Text(
                                  progress == AuthenticationProgress.signingIn
                                      ? 'Signing in…'
                                      : 'Sign in',
                                ),
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
                            if (methods.registrationAvailable) ...<Widget>[
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
                          ] else ...<Widget>[
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                'Signed in as ${session.userId}',
                                key: const Key('authenticated-session'),
                                textAlign: TextAlign.center,
                              ),
                            ),
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
