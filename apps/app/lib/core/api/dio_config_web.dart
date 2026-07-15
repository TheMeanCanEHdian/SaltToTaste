import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

/// On web the session cookie is the credential: send it with every request
/// (required for the cross-origin dev setup; a no-op same-origin).
void configurePlatform(Dio dio) {
  dio.httpClientAdapter = BrowserHttpClientAdapter(withCredentials: true);
}
