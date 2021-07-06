import 'dart:convert';

import 'package:http/http.dart' as http;

abstract class CallSaltToTaste {
  Future call({
    required String endpoint,
  });
}

class CallSaltToTasteImpl implements CallSaltToTaste {
  @override
  Future call({
    required String endpoint,
  }) async {
    //TODO: Add the ability to use a custom set domain
    final Uri uri = Uri.http('127.0.0.1:5000', '/api/$endpoint');

    http.Response response;
    //TODO: Investigate support for self signed certs
    //TODO: dart:io web issues may complicate this

    // Call API
    try {
      response = await http.get(uri);
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
