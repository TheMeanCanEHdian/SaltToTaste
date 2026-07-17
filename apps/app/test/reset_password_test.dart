import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/features/settings/users_tab.dart';

/// What an admin is told a password reset did.
///
/// The reset revokes every one of the target's API tokens as well as their
/// sessions — deliberately, because a PAT is its own credential, so a reset
/// that only dropped sessions left an attacker's token frozen rather than
/// gone. The server has always reported `revoked_tokens`. The client parsed
/// the response and threw that field away, so the first anyone knew was an
/// integration going dark.
void main() {
  group('AuthRepository.resetPassword', () {
    Future<({String tempPassword, int revokedTokens})> resetWith(String body) {
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = _ResetAdapter(body);
      return AuthRepository(dio).resetPassword(7);
    }

    test('carries the revoked-token count out of the response', () async {
      final result = await resetWith(
        '{"temp_password":"horse-battery-9","revoked_tokens":3}',
      );
      expect(result.tempPassword, 'horse-battery-9');
      expect(
        result.revokedTokens,
        3,
        reason: 'the client used to drop this field entirely',
      );
    });

    test('treats a missing count as zero rather than throwing', () async {
      // docs/API.md promises the field, but a repository that dies on a
      // response shape would take the temp password down with it — and the
      // password is the part the admin cannot get back.
      final result = await resetWith('{"temp_password":"horse-battery-9"}');
      expect(result.revokedTokens, 0);
      expect(result.tempPassword, 'horse-battery-9');
    });
  });

  group('revokedTokensNote', () {
    test('says nothing when nothing was revoked', () {
      // The common path. "0 API tokens revoked" is noise.
      expect(revokedTokensNote(0), isEmpty);
      expect(revokedTokensNote(null), isEmpty);
    });

    test('reports the count, and says what it costs the admin', () {
      final note = revokedTokensNote(3);
      expect(note, contains('3 API tokens were revoked'));
      expect(
        note,
        contains('need a new one'),
        reason: 'the count alone does not tell an admin what to go fix',
      );
    });

    test('one token is singular', () {
      expect(revokedTokensNote(1), contains('1 API token was revoked'));
      expect(revokedTokensNote(1), isNot(contains('tokens were')));
    });
  });
}

/// Serves one fixed reset_password response.
class _ResetAdapter implements HttpClientAdapter {
  _ResetAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? _,
    Future<void>? __,
  ) async {
    if (options.path.contains('reset_password')) {
      return ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{}', 404);
  }

  @override
  void close({bool force = false}) {}
}
