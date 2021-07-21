import 'dart:convert';

import 'package:http/http.dart' as http;

enum RequestMethod {
  get,
  put,
}

abstract class CallSaltToTaste {
  Future call({
    required RequestMethod requestMethod,
    required String endpoint,
    Map<String, String> params = const {},
  });
}

class CallSaltToTasteImpl implements CallSaltToTaste {
  @override
  Future call({
    required RequestMethod requestMethod,
    required String endpoint,
    Map<String, String> params = const {},
  }) async {
    //TODO: Add the ability to use a custom set domain
    final Uri uri = Uri.http('127.0.0.1:5000', '/api/$endpoint', params);

    http.Response response;
    //TODO: Investigate support for self signed certs
    //TODO: dart:io web issues may complicate this

    // Call API
    try {
      switch (requestMethod) {
        case RequestMethod.get:
          response = await http.get(uri);
          break;
        case RequestMethod.put:
          response = await http.put(uri);
          break;
      }
    } catch (exception) {
      //TODO: Add catch for a valid certificate failure
      rethrow;
    }

    // Parse response into JSON
    Map<String, dynamic> responseJson;
    try {
      responseJson = json.decode(response.body);
    } catch (_) {
      //TODO: Throw a specific JSON error
      rethrow;
    }

    return responseJson;
  }
}
