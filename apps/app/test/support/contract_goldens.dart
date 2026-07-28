/// App-side access to the committed API contract goldens.
///
/// The goldens are real `/api/v1` response bodies captured from the real
/// server routes by `apps/server/test/contract_golden_test.dart`. They live
/// under `packages/salt_shared/` so neither side owns the contract, and are
/// reached here at the same relative path the server uses from its own
/// package root (the working directory of `flutter test`).
///
/// Reading them needs NO corpus, so anything built on this runs in CI. Any
/// app test that would otherwise hand-build a fake response body should
/// serve a golden instead — [goldenDio] wires one into a [Dio] so the
/// repository under test does its own URL building, decoding and casting.
///
/// Regenerate the files (only for a DELIBERATE server-side shape change):
///
/// ```sh
/// cd apps/server
/// SALT_CORPUS_DIR="<corpus root>" UPDATE_CONTRACT_GOLDENS=1 \
///   dart test test/contract_golden_test.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Directory holding the committed goldens, relative to this package root.
const String contractFixturesDir =
    '../../packages/salt_shared/test/fixtures/contract';

/// The raw JSON of golden [name] (without the `.json` suffix).
Map<String, dynamic> golden(String name) =>
    jsonDecode(File('$contractFixturesDir/$name.json').readAsStringSync())
        as Map<String, dynamic>;

/// Serves one prepared body for whatever the repository requests, so the
/// repository's own URL building, decoding, and error handling all run.
class GoldenAdapter implements HttpClientAdapter {
  GoldenAdapter(this.body, {this.statusCode = 200});

  /// The body to answer with (a golden, possibly mutated by a test).
  Object? body;

  /// The status to answer with — 200 unless a test wants an error path.
  int statusCode;

  /// Every request this adapter has answered, in order, so a test can assert
  /// on the URL and query the repository actually built.
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A [Dio] that answers every request with [body] — pass `golden('name')`.
///
/// The returned adapter is reachable as `dio.httpClientAdapter` for tests
/// that want to swap the body between calls or inspect [GoldenAdapter
/// .requests].
Dio goldenDio(Object? body, {int statusCode = 200}) =>
    Dio(BaseOptions(baseUrl: 'http://contract'))
      ..httpClientAdapter = GoldenAdapter(body, statusCode: statusCode);
