import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/entities/setting.dart';
import '../../domain/usecases/get_settings.dart';

part 'settings_event.dart';
part 'settings_state.dart';

List<Setting> settingsCache = [];

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final GetSettings getSettings;

  SettingsBloc({
    required this.getSettings,
  }) : super(SettingsInitial());

  @override
  Stream<SettingsState> mapEventToState(
    SettingsEvent event,
  ) async* {
    if (event is SettingsFetch) {
      yield SettingsInProgress();

      final failureOrSettings = await getSettings();

      yield* failureOrSettings.fold(
        (failure) async* {
          yield SettingsFailure();
        },
        (settingsList) async* {
          settingsCache = [...settingsList];
          yield SettingsSuccess(settingsList: settingsList);
        },
      );
    }
  }
}
