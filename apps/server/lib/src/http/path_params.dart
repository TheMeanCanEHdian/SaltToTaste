import 'package:salt_server/src/exceptions.dart';

/// Syntactically bad percent escape: a `%` not followed by two hex digits.
final RegExp _malformedEscape = RegExp('%(?![0-9A-Fa-f]{2})');

/// Decodes a dart_frog route capture.
///
/// The router matches the percent-ENCODED request path and hands captures to
/// `onRequest` undecoded, so a tag named `main course` arrives as
/// `main%20course` and a lookup on the raw capture 404s forever (review B8).
/// Every route whose parameter can carry a human-authored value (tag names,
/// recipe ids/slugs — hand-edited slugs are a supported case) must decode at
/// the boundary. Purely server-generated parameters (image file names, which
/// are sanitized to URL-safe characters at store time and validated raw)
/// deliberately stay undecoded so their containment checks see the wire form.
///
/// A malformed escape (`%G1`, `%FF`) is a client error, not a 500. The regex
/// pre-check exists because Uri.decodeComponent reports bad escape syntax as
/// an ArgumentError, which is not for catching; invalid UTF-8 surfaces as a
/// FormatException, which is.
String decodePathParam(String raw) {
  if (_malformedEscape.hasMatch(raw)) {
    throw const ValidationException('Malformed percent-encoding in URL path.');
  }
  try {
    return Uri.decodeComponent(raw);
  } on FormatException {
    throw const ValidationException('Malformed percent-encoding in URL path.');
  }
}
