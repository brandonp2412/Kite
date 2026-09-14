import 'package:flutter/material.dart';
import 'package:kite/features/settings/settings_controller.dart';
import 'package:signals/signals_flutter.dart';

final class NotificationSoundOption {
  const NotificationSoundOption({required this.id, required this.label})
    : assert(id != '');

  final String id;
  final String label;
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    required this.controller,
    this.roomId,
    this.roomName,
    this.messageSounds = const <NotificationSoundOption>[],
    this.callRingtones = const <NotificationSoundOption>[],
    this.loadOnInit = true,
    super.key,
  });

  final SettingsController controller;
  final String? roomId;
  final String? roomName;
  final List<NotificationSoundOption> messageSounds;
  final List<NotificationSoundOption> callRingtones;
  final bool loadOnInit;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
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
      appBar: AppBar(title: const Text('Notifications')),
      body: SignalBuilder(
        builder: (context) {
          final settings = widget.controller.settings.value;
          final notifications = settings.notifications;
          final busy =
              widget.controller.isLoading.value ||
              widget.controller.isSaving.value;
          final error = widget.controller.errorMessage.value;

          return ListView(
            key: const Key('notification-settings-list'),
            padding: const EdgeInsets.only(bottom: 24),
            children: <Widget>[
              SwitchListTile.adaptive(
                key: const Key('notification-master'),
                value: notifications.masterEnabled,
                onChanged: busy
                    ? null
                    : widget.controller.setNotificationMaster,
                title: const Text('Notifications'),
                subtitle: const Text(
                  'Allow Kite to notify you about activity.',
                ),
              ),
              const Divider(height: 1),
              _SectionTitle(label: 'Notify me about'),
              for (final category in NotificationCategory.values)
                SwitchListTile.adaptive(
                  key: Key('notification-category-${category.name}'),
                  value: notifications.enabledCategories.contains(category),
                  onChanged: busy || !notifications.masterEnabled
                      ? null
                      : (enabled) => widget.controller.setNotificationCategory(
                          category,
                          enabled,
                        ),
                  title: Text(_categoryLabel(category)),
                ),
              if (widget.roomId case final roomId?) ...<Widget>[
                const Divider(height: 1),
                _SectionTitle(label: widget.roomName ?? 'This room'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<RoomNotificationMode>(
                    key: const Key('room-notification-mode'),
                    initialValue: notifications.roomMode(roomId),
                    decoration: const InputDecoration(
                      labelText: 'Room notifications',
                    ),
                    items: RoomNotificationMode.values
                        .map(
                          (mode) => DropdownMenuItem<RoomNotificationMode>(
                            value: mode,
                            child: Text(_roomModeLabel(mode)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: busy
                        ? null
                        : (mode) {
                            if (mode != null) {
                              widget.controller.setRoomNotificationMode(
                                roomId,
                                mode,
                              );
                            }
                          },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Divider(height: 1),
              const _SectionTitle(label: 'Sounds'),
              _SoundPicker(
                pickerKey: const Key('message-notification-sound'),
                label: 'Message sound',
                selectedId: notifications.messageSoundId,
                options: widget.messageSounds,
                enabled: !busy,
                onChanged: widget.controller.setMessageNotificationSound,
              ),
              _SoundPicker(
                pickerKey: const Key('call-notification-ringtone'),
                label: 'Call ringtone',
                selectedId: notifications.callRingtoneId,
                options: widget.callRingtones,
                enabled: !busy,
                onChanged: widget.controller.setCallRingtone,
              ),
              SizedBox(
                key: const Key('notification-settings-status'),
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

  static String _categoryLabel(NotificationCategory category) =>
      switch (category) {
        NotificationCategory.messages => 'Messages',
        NotificationCategory.mentions => 'Mentions',
        NotificationCategory.calls => 'Calls',
      };

  static String _roomModeLabel(RoomNotificationMode mode) => switch (mode) {
    RoomNotificationMode.inherit => 'Use account default',
    RoomNotificationMode.allMessages => 'All messages',
    RoomNotificationMode.mentionsOnly => 'Mentions only',
    RoomNotificationMode.mute => 'Mute',
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

class _SoundPicker extends StatelessWidget {
  const _SoundPicker({
    required this.pickerKey,
    required this.label,
    required this.selectedId,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  static const String _defaultSoundId = '__kite_default_sound__';

  final Key pickerKey;
  final String label;
  final String? selectedId;
  final List<NotificationSoundOption> options;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ids = options.map((option) => option.id).toSet();
    final currentId = selectedId != null && ids.contains(selectedId)
        ? selectedId!
        : _defaultSoundId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: DropdownButtonFormField<String>(
        key: pickerKey,
        initialValue: currentId,
        decoration: InputDecoration(labelText: label),
        items: <DropdownMenuItem<String>>[
          const DropdownMenuItem<String>(
            value: _defaultSoundId,
            child: Text('Default'),
          ),
          ...options.map(
            (option) => DropdownMenuItem<String>(
              value: option.id,
              child: Text(option.label),
            ),
          ),
        ],
        onChanged: enabled
            ? (value) => onChanged(
                value == null || value == _defaultSoundId ? null : value,
              )
            : null,
      ),
    );
  }
}
