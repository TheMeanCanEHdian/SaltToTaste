part of 'settings_update_bloc.dart';

abstract class SettingsUpdateEvent extends Equatable {
  const SettingsUpdateEvent();
}

class SettingsUpdateTrigger extends SettingsUpdateEvent {
  final List<Setting> currentSettings;
  final Map<String, dynamic> settingsMap;

  SettingsUpdateTrigger({
    required this.currentSettings,
    required this.settingsMap,
  });

  @override
  List<Object?> get props => [currentSettings, settingsMap];
}
