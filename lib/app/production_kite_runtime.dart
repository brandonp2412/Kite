import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kite/app/kite_runtime.dart';
import 'package:kite/app/platform_matrix_bootstrap_gateway.dart';
import 'package:kite/features/auth/authentication_gateway.dart';
import 'package:kite/features/home/matrix_home_presentation.dart';
import 'package:kite/matrix/io_matrix_well_known_client.dart';
import 'package:kite/matrix/matrix_homeserver_discovery.dart';
import 'package:kite/matrix/matrix_production_runtime.dart';
import 'package:kite/matrix/matrix_rust_auth_session_api.dart';
import 'package:kite/matrix/matrix_rust_native_bridge.dart';
import 'package:kite/matrix/native_matrix_account_sdk_boundary.dart';
import 'package:kite/matrix/presentation_cache.dart';

final class ProductionKiteRuntime extends StatefulWidget {
  const ProductionKiteRuntime._({
    required this.accountBoundary,
    required this.matrixRuntime,
  });

  static Future<ProductionKiteRuntime> create({
    PlatformMatrixBootstrapGateway gateway =
        const PlatformMatrixBootstrapGateway(),
  }) async {
    final root = await gateway.dataRoot();
    await root.create(recursive: true);
    late final MatrixProductionRuntime matrixRuntime;
    final nativeBridge = MatrixRustNativeBridge(
      libraryPath: matrixRustNativeLibraryPath(),
    );
    matrixRuntime = MatrixProductionRuntime(
      rootDirectory: root,
      resolveStoreSecret: gateway.resolveStoreSecret,
      encryptionKeyIdForAccount: (_) =>
          MatrixRustAuthSessionApi.encryptionKeyId,
      nativeBridge: nativeBridge,
    );
    final authApi = MatrixRustAuthSessionApi(
      homeserverDiscovery: const MatrixHomeserverDiscovery(
        IoMatrixWellKnownClient(),
      ),
      nativeBridge: nativeBridge,
      rootDirectory: root,
      resolveStoreSecret: gateway.resolveStoreSecret,
      storeConfigurationForAccount:
          matrixRuntime.accounts.storeRegistry.forAccount,
    );
    return ProductionKiteRuntime._(
      accountBoundary: NativeMatrixAccountSdkBoundary(authApi),
      matrixRuntime: matrixRuntime,
    );
  }

  final NativeMatrixAccountSdkBoundary accountBoundary;
  final MatrixProductionRuntime matrixRuntime;

  @override
  State<ProductionKiteRuntime> createState() => _ProductionKiteRuntimeState();
}

final class _ProductionKiteRuntimeState extends State<ProductionKiteRuntime> {
  @override
  void dispose() {
    unawaited(widget.matrixRuntime.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KiteRuntime(
      accountSdkBoundary: widget.accountBoundary,
      authenticatedHomeBuilder: (context, session) => _AuthenticatedMatrixHome(
        runtime: widget.matrixRuntime,
        session: session,
      ),
    );
  }
}

final class _AuthenticatedMatrixHome extends StatefulWidget {
  const _AuthenticatedMatrixHome({
    required this.runtime,
    required this.session,
  });

  final MatrixProductionRuntime runtime;
  final AuthenticatedSession session;

  @override
  State<_AuthenticatedMatrixHome> createState() =>
      _AuthenticatedMatrixHomeState();
}

final class _AuthenticatedMatrixHomeState
    extends State<_AuthenticatedMatrixHome> {
  late Future<MatrixPresentationCache> _activation;

  @override
  void initState() {
    super.initState();
    _activation = _activate();
  }

  @override
  void didUpdateWidget(_AuthenticatedMatrixHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.userId == widget.session.userId &&
        oldWidget.session.homeserver.uri == widget.session.homeserver.uri &&
        identical(oldWidget.runtime, widget.runtime)) {
      return;
    }
    _activation = _activate();
  }

  Future<MatrixPresentationCache> _activate() async {
    widget.runtime.registerAuthenticatedAccount(
      accountId: widget.session.userId,
      homeserver: widget.session.homeserver.uri,
    );
    return widget.runtime.activate(widget.session.userId);
  }

  void _retry() {
    setState(() {
      _activation = _activate();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MatrixPresentationCache>(
      future: _activation,
      builder: (context, snapshot) {
        final cache = snapshot.data;
        if (cache != null) {
          return MatrixHomeScreen(
            cache: cache,
            currentUserId: widget.session.userId,
            sendPort: MatrixTimelineSendPort(({
              required roomId,
              required transactionId,
              required body,
            }) async {
              await widget.runtime.sendTextMessage(
                accountId: widget.session.userId,
                roomId: roomId,
                transactionId: transactionId,
                body: body,
              );
            }),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('Could not start Matrix sync.'),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _retry, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
