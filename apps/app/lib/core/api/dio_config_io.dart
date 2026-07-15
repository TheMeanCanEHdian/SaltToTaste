import 'package:dio/dio.dart';

/// Native platforms authenticate with bearer tokens (added per request by
/// the auth layer once native support lands); nothing to configure here.
void configurePlatform(Dio dio) {}
