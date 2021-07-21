part of 'settings_bloc.dart';

abstract class SettingsState extends Equatable {
  const SettingsState();
}

class SettingsInitial extends SettingsState {
  @override
  List<Object> get props => [];
}

class SettingsInProgress extends SettingsState {
  @override
  List<Object> get props => [];
}

class SettingsSuccess extends SettingsState {
  final List<Setting> settingsList;

  SettingsSuccess({
    this.settingsList = const [],
  });

  @override
  List<Object> get props => [settingsList];
}

class SettingsFailure extends SettingsState {
  @override
  List<Object> get props => [];
}
