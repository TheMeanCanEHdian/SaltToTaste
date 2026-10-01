import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

/// The codes are a wire contract (docs/API.md's catalog): the app matches on
/// these constants, so a renamed value would silently break its handling —
/// the reload on a 409 `line_moved` most of all (Run 051).
void main() {
  test('each error code keeps its wire value', () {
    expect(ApiErrorCodes.validation, 'validation');
    expect(ApiErrorCodes.notFound, 'not_found');
    expect(ApiErrorCodes.methodNotAllowed, 'method_not_allowed');
    expect(ApiErrorCodes.internal, 'internal');
    expect(ApiErrorCodes.unauthorized, 'unauthorized');
    expect(ApiErrorCodes.forbidden, 'forbidden');
    expect(ApiErrorCodes.csrf, 'csrf');
    expect(ApiErrorCodes.passwordChangeRequired, 'password_change_required');
    expect(ApiErrorCodes.locked, 'locked');
    expect(ApiErrorCodes.rateLimited, 'rate_limited');
    expect(ApiErrorCodes.conflict, 'conflict');
    expect(ApiErrorCodes.zeroRow, 'zero_row');
    expect(ApiErrorCodes.lineMoved, 'line_moved');
  });
}
