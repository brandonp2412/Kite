import 'package:flutter/material.dart';
import 'package:kite/features/auth/authentication_controller.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:signals/signals_flutter.dart';

class AuthenticationScreen extends StatefulWidget {
  const AuthenticationScreen({
    required this.gateway,
    this.onAuthenticated,
    super.key,
  });

  final AuthenticationGateway gateway;
  final ValueChanged<AuthenticatedSession>? onAuthenticated;

  @override
  State<AuthenticationScreen> createState() => _AuthenticationScreenState();
}

class _AuthenticationScreenState extends State<AuthenticationScreen> {
  late final AuthenticationController _controller;
  late final TextEditingController _homeserverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _controller = AuthenticationController(widget.gateway);
    _homeserverController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _homeserverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _controller.dispose();
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

  void _completeAuthenticationIfNeeded() {
    final authenticatedSession = _controller.session.value;
    if (authenticatedSession == null) return;
    _passwordController.clear();
    widget.onAuthenticated?.call(authenticatedSession);
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
                              Text(
                                'This homeserver also supports account registration.',
                                key: const Key('registration-available'),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
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
