part of 'settings_update_bloc.dart';

abstract class SettingsUpdateState extends Equatable {
  const SettingsUpdateState();
}

class SettingsUpdateInitial extends SettingsUpdateState {
  @override
  List<Object> get props => [];
}

class SettingsUpdateInProgress extends SettingsUpdateState {
  @override
  List<Object?> get props => [];
}

class SettingsUpdateSuccess extends SettingsUpdateState {
  @override
  List<Object?> get props => [];
}

class SettingsUpdateFailure extends SettingsUpdateState {
  @override
  List<Object?> get props => [];
}
