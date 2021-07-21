import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/entities/setting.dart';
import '../../domain/usecases/update_setting.dart';

part 'settings_update_event.dart';
part 'settings_update_state.dart';

class SettingsUpdateBloc
    extends Bloc<SettingsUpdateEvent, SettingsUpdateState> {
  final UpdateSetting updateSetting;

  SettingsUpdateBloc({
    required this.updateSetting,
  }) : super(SettingsUpdateInitial());

  @override
  Stream<SettingsUpdateState> mapEventToState(
    SettingsUpdateEvent event,
  ) async* {
    if (event is SettingsUpdateTrigger) {
      yield SettingsUpdateInProgress();

      for (String settingName in event.settingsMap.keys) {
        // Get existing setting and index
        final setting = event.currentSettings.firstWhere(
          (setting) => setting.name == settingName,
        );

        // If setting value has changed
        if (setting.value != event.settingsMap[settingName]) {
          final settingIndex = event.currentSettings.indexOf(setting);
          final newValue = event.settingsMap[settingName];

          final failureOrUpdateSetting = await updateSetting(
            section: setting.section,
            name: setting.name,
            value: newValue,
          );

          yield* failureOrUpdateSetting.fold(
            (failure) async* {
              yield SettingsUpdateFailure();
            },
            (result) async* {
              if (result) {
                print('update success');
                // Update settings cache with new data
                event.currentSettings[settingIndex] = setting.copyWith(
                  value: newValue,
                );
                yield SettingsUpdateSuccess();
              } else {
                yield SettingsUpdateFailure();
              }
            },
          );
        }

        yield SettingsUpdateSuccess();
      }
    }
  }
}
