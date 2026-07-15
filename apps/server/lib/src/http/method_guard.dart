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

/// Throws [MethodNotAllowedException] unless the request method is in
/// [allowed] (e.g. `{HttpMethod.get, HttpMethod.post}`).
void requireMethods(RequestContext context, Set<HttpMethod> allowed) {
  if (!allowed.contains(context.request.method)) {
    final names = [for (final method in allowed) method.value.toUpperCase()]
      ..sort();
    throw MethodNotAllowedException(names.join(', '));
  }
}
