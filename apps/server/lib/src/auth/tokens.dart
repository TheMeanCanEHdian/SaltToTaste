import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Name of the session cookie set on web logins.
const String sessionCookieName = 'stt_session';

/// Marker prefix that distinguishes personal access tokens from session
/// tokens in a bearer header.
const String patMarker = 'stt_pat_';

/// Number of body characters (after [patMarker]) stored as the displayable
/// PAT prefix.
const int _patPrefixLength = 12;

final Random _secureRandom = Random.secure();

final RegExp _patBodyPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// Generates an opaque session token: 32 CSPRNG bytes, base64url without
/// padding (43 characters). Store only its [hashToken] digest.
String generateOpaqueToken() {
  final bytes = List<int>.generate(32, (_) => _secureRandom.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// Generates a personal access token.
///
/// `token` is `stt_pat_` + 43 base64url characters and is shown to the user
/// exactly once. `prefix` is the first 12 characters after the marker,
/// safe to store and display for identification.
({String token, String prefix}) generatePat() {
  final body = generateOpaqueToken();
  return (
    token: '$patMarker$body',
    prefix: body.substring(0, _patPrefixLength),
  );
}

/// SHA-256 hex digest of [token] — the only form ever persisted or compared
/// at rest. Never log the input.
String hashToken(String token) => sha256.convert(utf8.encode(token)).toString();

/// Whether [bearer] is shaped like a personal access token (marker plus a
/// well-formed 43-character base64url body), as opposed to a session token.
bool looksLikePat(String bearer) =>
    bearer.startsWith(patMarker) &&
    _patBodyPattern.hasMatch(bearer.substring(patMarker.length));
