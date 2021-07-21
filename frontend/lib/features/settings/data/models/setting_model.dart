import '../../domain/entities/setting.dart';

class SettingModel extends Setting {
  SettingModel({
    required String section,
    required String name,
    required String value,
  }) : super(
          section: section,
          name: name,
          value: value,
        );

  factory SettingModel.fromJson(String section, String name, String value) {
    return SettingModel(
      section: section,
      name: name,
      value: value,
    );
  }
}
