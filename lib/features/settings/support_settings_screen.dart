import 'package:flutter/material.dart';
import 'package:kite/features/settings/settings_layout.dart';
import 'package:kite/features/settings/support_settings_controller.dart';
import 'package:signals/signals_flutter.dart';

class SupportSettingsScreen extends StatefulWidget {
  const SupportSettingsScreen({
    required this.controller,
    this.loadOnInit = true,
    super.key,
  });

  final SupportSettingsController controller;
  final bool loadOnInit;

  @override
  State<SupportSettingsScreen> createState() => _SupportSettingsScreenState();
}

class _SupportSettingsScreenState extends State<SupportSettingsScreen> {
  final _reportController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) {
      widget.controller.load();
    }
  }

  @override
  void dispose() {
    _reportController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Storage & support')),
      body: SignalBuilder(
        builder: (context) {
          final storage = widget.controller.storage.value;
          final about = widget.controller.about.value;
          final busy = widget.controller.isBusy.value;
          final error = widget.controller.errorMessage.value;
          final reportSubmitted = widget.controller.reportSubmitted.value;

          return ListView(
            key: const Key('support-settings-list'),
            padding: SettingsLayout.listPadding(context),
            children: <Widget>[
              const _SectionTitle(label: 'Storage'),
              _UsageTile(
                key: const Key('media-cache-usage'),
                label: 'Media cache',
                bytes: storage?.mediaCacheBytes,
              ),
              _UsageTile(
                key: const Key('presentation-cache-usage'),
                label: 'Local presentation cache',
                bytes: storage?.presentationCacheBytes,
              ),
              _UsageTile(
                key: const Key('diagnostic-log-usage'),
                label: 'Diagnostic logs',
                bytes: storage?.diagnosticLogBytes,
                subtitle: 'Preserved when cached content is cleared.',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: FilledButton.tonal(
                  key: const Key('clear-cached-content'),
                  onPressed: busy || storage == null
                      ? null
                      : widget.controller.clearClearableCaches,
                  child: const Text('Clear cached content'),
                ),
              ),
              const Divider(height: 1),
              const _SectionTitle(label: 'Report a problem'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  key: const Key('problem-description'),
                  controller: _reportController,
                  enabled: !busy,
                  minLines: 3,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'What happened?',
                    alignLabelWithHint: true,
                    helperText: 'Only sanitized diagnostic metadata is attached. Tokens, recovery secrets and message contents are excluded.',
                    helperMaxLines: 3,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: FilledButton(
                  key: const Key('submit-problem-report'),
                  onPressed: busy
                      ? null
                      : () => widget.controller.submitProblemReport(
                          _reportController.text,
                        ),
                  child: const Text('Send report'),
                ),
              ),
              const Divider(height: 1),
              const _SectionTitle(label: 'About'),
              ConstrainedBox(
                key: const Key('about-info'),
                constraints: const BoxConstraints(minHeight: 132),
                child: about == null
                    ? const Center(child: Text('App information unavailable'))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          ListTile(
                            dense: true,
                            title: const Text('Kite'),
                            subtitle: Text(
                              'Version ${about.version} (${about.buildNumber})',
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              key: const Key('open-licenses'),
                              onPressed: () => showLicensePage(
                                context: context,
                                applicationName: 'Kite',
                                applicationVersion:
                                    '${about.version} (${about.buildNumber})',
                              ),
                              child: Text(
                                'Open source licenses (${about.licenseCount})',
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              ConstrainedBox(
                key: const Key('support-settings-status'),
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error ??
                            (reportSubmitted ? 'Problem report sent.' : ''),
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
}

class _UsageTile extends StatelessWidget {
  const _UsageTile({
    required this.label,
    required this.bytes,
    this.subtitle,
    super.key,
  });

  final String label;
  final int? bytes;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: SizedBox(
        width: 92,
        child: Text(
          bytes == null ? '—' : _formatBytes(bytes!),
          textAlign: TextAlign.end,
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kib = bytes / 1024;
    if (kib < 1024) return '${kib.toStringAsFixed(1)} KiB';
    final mib = kib / 1024;
    if (mib < 1024) return '${mib.toStringAsFixed(1)} MiB';
    return '${(mib / 1024).toStringAsFixed(1)} GiB';
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
