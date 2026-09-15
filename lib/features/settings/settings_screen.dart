import 'package:flutter/material.dart';
import 'package:kite/design/kite_tokens.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.onOpenProfile,
    required this.onOpenAccounts,
    required this.onOpenGeneral,
    required this.onOpenNotifications,
    required this.onOpenPrivacySecurity,
    required this.onOpenSupport,
    this.accountLabel,
    super.key,
  });

  final VoidCallback onOpenProfile;
  final VoidCallback onOpenAccounts;
  final VoidCallback onOpenGeneral;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenPrivacySecurity;
  final VoidCallback onOpenSupport;
  final String? accountLabel;

  @override
  Widget build(BuildContext context) {
    final label = accountLabel?.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: ListView(
          key: const Key('settings-list'),
          padding: const EdgeInsets.only(bottom: KiteSpacing.xl),
          children: <Widget>[
            const _SectionTitle(label: 'Account'),
            _SettingsEntry(
              key: const Key('settings-profile'),
              icon: Icons.account_circle_outlined,
              title: 'Your profile',
              subtitle: label == null || label.isEmpty ? null : label,
              onTap: onOpenProfile,
            ),
            _SettingsEntry(
              key: const Key('settings-accounts'),
              icon: Icons.devices_other_outlined,
              title: 'Accounts & sessions',
              subtitle: 'Switch accounts and manage signed-in devices',
              onTap: onOpenAccounts,
            ),
            const Divider(height: 1),
            const _SectionTitle(label: 'Preferences'),
            _SettingsEntry(
              key: const Key('settings-general'),
              icon: Icons.tune_rounded,
              title: 'General',
              subtitle: 'Appearance and language',
              onTap: onOpenGeneral,
            ),
            _SettingsEntry(
              key: const Key('settings-notifications'),
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Messages, mentions, calls and sounds',
              onTap: onOpenNotifications,
            ),
            const Divider(height: 1),
            const _SectionTitle(label: 'Security'),
            _SettingsEntry(
              key: const Key('settings-privacy-security'),
              icon: Icons.shield_outlined,
              title: 'Privacy & security',
              subtitle: 'Verification, recovery, app lock and privacy',
              onTap: onOpenPrivacySecurity,
            ),
            const Divider(height: 1),
            const _SectionTitle(label: 'Support'),
            _SettingsEntry(
              key: const Key('settings-support'),
              icon: Icons.help_outline_rounded,
              title: 'Storage, support & about',
              subtitle: 'Cache, diagnostics, version and licenses',
              onTap: onOpenSupport,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsEntry extends StatelessWidget {
  const _SettingsEntry({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 72,
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KiteSpacing.md,
        KiteSpacing.lg,
        KiteSpacing.md,
        KiteSpacing.sm,
      ),
      child: Text(label, style: KiteTypography.title),
    );
  }
}
