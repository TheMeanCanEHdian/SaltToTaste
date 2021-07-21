import 'call_salt_to_taste.dart';

abstract class Settings {
  Future getSettings();
  Future updateSetting({
    required String section,
    required String name,
    required String value,
  });
}

class SettingsImpl implements Settings {
  final CallSaltToTaste callSaltToTaste;

  SettingsImpl({
    required this.callSaltToTaste,
  });

  @override
  Future getSettings() async {
    final responseJson = await callSaltToTaste(
      requestMethod: RequestMethod.get,
      endpoint: 'settings',
    );

    return responseJson;
  }

  @override
  Future updateSetting({
    required String section,
    required String name,
    required String value,
  }) async {
    final responseJson = await callSaltToTaste(
        requestMethod: RequestMethod.put,
        endpoint: 'settings',
        params: {
          'section': section,
          'setting': name,
          'value': value,
        });

    return responseJson;
  }
}
