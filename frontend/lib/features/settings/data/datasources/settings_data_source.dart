import '../../../../core/api/salt_to_taste_api.dart' as api;
import '../../domain/entities/setting.dart';
import '../models/setting_model.dart';

abstract class SettingsDataSource {
  Future<List<Setting>> getSettings();
  Future<bool> updateSetting({
    required String section,
    required String name,
    required String value,
  });
}

class SettingsDataSourceImpl implements SettingsDataSource {
  final api.Settings settings;

  SettingsDataSourceImpl({
    required this.settings,
  });

  @override
  Future<List<Setting>> getSettings() async {
    final settingsJson = await settings.getSettings();

    final settingsSections = settingsJson.keys;

    List<Setting> settingsList = [];

    for (String section in settingsSections) {
      final settingsNames = settingsJson[section].keys;
      for (String name in settingsNames) {
        settingsList.add(
          SettingModel.fromJson(section, name, settingsJson[section][name]),
        );
      }
    }

    return settingsList;
  }

  @override
  Future<bool> updateSetting({
    required String section,
    required String name,
    required String value,
  }) async {
    final resultJson = await settings.updateSetting(
      section: section,
      name: name,
      value: value,
    );

    if (resultJson['result'] == 'success') {
      return true;
    } else {
      return false;
    }
  }
}
