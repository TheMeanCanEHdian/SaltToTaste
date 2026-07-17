import 'dart:io';

/// Container HEALTHCHECK helper: exits 0 when `GET /healthz` on the local
/// server answers 200, 1 otherwise. Compiled into the image so the slim
/// runtime needs no curl/wget.
Future<void> main() async {
  final port = Platform.environment['PORT'] ?? '8080';
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client
        .getUrl(Uri.parse('http://127.0.0.1:$port/healthz'))
        .timeout(const Duration(seconds: 3));
    final response = await request.close().timeout(const Duration(seconds: 3));
    await response.drain<void>();
    exit(response.statusCode == HttpStatus.ok ? 0 : 1);
  } on Object {
    exit(1);
  } finally {
    client.close(force: true);
  }
}
