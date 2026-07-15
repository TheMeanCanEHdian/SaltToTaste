import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/exceptions.dart';

/// Throws [MethodNotAllowedException] unless the request is a GET.
///
/// The error-handler middleware turns the exception into a 405 envelope with
/// an `Allow: GET` header, so read-only routes reduce to one call instead of
/// a hand-built guard each.
void requireGet(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    throw const MethodNotAllowedException('GET');
  }
}
