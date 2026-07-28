// A route authorization matrix that verifies its own completeness.
//
// Layer 1 (`route inventory`) walks the WHOLE `routes/` tree ON DISK at test
// time and fails until every route file appears in the declaration below —
// `/api/v1/**`, but also `/`, `/healthz` and the image server, which carry
// real auth postures of their own. It needs no corpus and no server, so CI
// runs it: a new endpoint cannot land without someone reading its handler and
// declaring its auth posture.
//
// Layer 2 (`enforcement`) drives every declared route through the REAL
// production middleware chain — `buildAppMiddleware`, the same function
// `routes/_middleware.dart` calls — over a real socket, and derives every
// expectation from the SAME declaration layer 1 checks. The list and the
// behavior therefore cannot disagree; a hand-maintained list can (and did:
// tags/[name]/style, /nutrition/search, /admin/logs/export and both admin
// report routes had no route-level auth test at all).
//
// Completeness is METHOD-grained, not just file-grained: every route is also
// driven with each HTTP method it does NOT declare, which must answer 405.
// Widening an already-declared route's method guard therefore fails here
// until the new method is declared and its posture proven. (An earlier
// version diffed file sets only, and a POST branch guarded by nothing but
// requireUser could be bolted onto any of the 43 existing files unnoticed.)
//
// The matrix is corpus-free end to end — no group in this file is skipped in
// CI. Every probe is refused by a guard or falls through to a 404 for an id
// that cannot exist; the one check that needs a recipe which really exists
// (note.dart's CSRF guard, see the SUSPECTED FINDING below) uses the real
// legacy-v0 recipe committed at test/fixtures/legacy-v0/, not a fabricated
// one. Review item T1: assertions that need no corpus must not sit behind a
// corpus gate.
//
// The credentials here are synthesized because auth inputs cannot come from a
// recipe corpus; no probe ever signs in with a password, so the stored hash is
// a placeholder that nothing verifies.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:salt_server/src/app_pipeline.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/auth_handlers.dart';
import 'package:salt_server/src/logging/log_store.dart';
import 'package:salt_server/src/middleware/auth.dart';
import 'package:salt_server/src/nutrition/provider.dart';
import 'package:salt_server/src/search/search_service.dart';
import 'package:salt_server/src/services/legacy_import.dart';
import 'package:test/test.dart';

import '../routes/api/v1/admin/logs.dart' as admin_logs;
import '../routes/api/v1/admin/logs/export.dart' as admin_logs_export;
import '../routes/api/v1/admin/nutrition_review.dart' as admin_nutrition;
import '../routes/api/v1/admin/recipe_review.dart' as admin_recipes;
import '../routes/api/v1/auth/change_password.dart' as auth_change_password;
import '../routes/api/v1/auth/login.dart' as auth_login;
import '../routes/api/v1/auth/logout.dart' as auth_logout;
import '../routes/api/v1/auth/me.dart' as auth_me;
import '../routes/api/v1/auth/recover.dart' as auth_recover;
import '../routes/api/v1/auth/setup.dart' as auth_setup;
import '../routes/api/v1/backups/[name].dart' as backup_name;
import '../routes/api/v1/backups/index.dart' as backups_index;
import '../routes/api/v1/import/candidates.dart' as import_candidates;
import '../routes/api/v1/import/index.dart' as import_index;
import '../routes/api/v1/import/jobs/[id].dart' as import_job;
import '../routes/api/v1/library/index.dart' as library_index;
import '../routes/api/v1/library/rescan.dart' as library_rescan;
import '../routes/api/v1/nutrition/bulk.dart' as nutrition_bulk;
import '../routes/api/v1/nutrition/jobs/[id].dart' as nutrition_job;
import '../routes/api/v1/nutrition/search.dart' as nutrition_search;
import '../routes/api/v1/recipes/[id]/favorite.dart' as recipe_favorite;
import '../routes/api/v1/recipes/[id]/images/from_url.dart' as image_from_url;
import '../routes/api/v1/recipes/[id]/images/index.dart' as recipe_images;
import '../routes/api/v1/recipes/[id]/images/store.dart' as image_store;
import '../routes/api/v1/recipes/[id]/images/store_from_url.dart'
    as image_store_from_url;
import '../routes/api/v1/recipes/[id]/index.dart' as recipe_detail;
import '../routes/api/v1/recipes/[id]/note.dart' as recipe_note;
import '../routes/api/v1/recipes/[id]/nutrition/compute.dart' as compute;
import '../routes/api/v1/recipes/[id]/nutrition/index.dart' as recipe_label;
import '../routes/api/v1/recipes/[id]/nutrition/matches/[pos].dart' as match;
import '../routes/api/v1/recipes/[id]/nutrition/matches/index.dart' as matches;
import '../routes/api/v1/recipes/[id]/yaml.dart' as recipe_yaml;
import '../routes/api/v1/recipes/index.dart' as recipes_index;
import '../routes/api/v1/sessions/[id].dart' as session_detail;
import '../routes/api/v1/sessions/index.dart' as sessions_index;
import '../routes/api/v1/settings/fdc_key.dart' as settings_fdc_key;
import '../routes/api/v1/tags/[name]/style.dart' as tag_style;
import '../routes/api/v1/tags/index.dart' as tags_index;
import '../routes/api/v1/tokens/[id].dart' as token_detail;
import '../routes/api/v1/tokens/index.dart' as tokens_index;
import '../routes/api/v1/users/[id]/index.dart' as user_detail;
import '../routes/api/v1/users/[id]/reset_password.dart' as user_reset;
import '../routes/api/v1/users/index.dart' as users_index;
import '../routes/healthz.dart' as healthz;
import '../routes/images/[source]/[file].dart' as library_image;
import '../routes/index.dart' as app_shell;

/// Directory the completeness check walks, relative to the package root
/// (`dart test` runs with the package root as cwd). The WHOLE tree, not just
/// `api/v1`: `/`, `/healthz` and `/images/<source>/<file>` are endpoints too,
/// and the last one requires auth and carries the path-containment invariant.
const String _routesDir = 'routes';

/// The one file under [_routesDir] that is middleware rather than a route.
/// It is excluded from the route inventory and pinned by its own test; a
/// `_middleware.dart` anywhere DEEPER stays unclassified on purpose, because
/// it changes the auth posture of everything beneath it.
const String _rootMiddlewareFile = '_middleware.dart';

/// This file's own path, quoted back in failure messages.
const String _thisFile = 'test/route_auth_matrix_test.dart';

// Path-parameter values chosen so that a probe which is NOT refused falls
// through to a 404 instead of touching real state.
const String _missingRecipe = 'no-such-recipe-for-the-auth-probe';
const String _missingTag = 'no-such-tag-for-the-auth-probe';
const String _missingSession = 'no-such-session-for-the-auth-probe';
const String _missingNumericId = '999999';
const String _matchPosition = '0';
const String _missingImageSource = 'no-such-source-for-the-auth-probe';

/// A real image extension, so the probe gets past the content-type lookup and
/// is refused by auth (or by the missing file), not by the extension check.
const String _missingImageFile = 'no-such-image-for-the-auth-probe.jpg';

/// The real legacy-v0 recipe committed to this repo at the P8 cutover. It is
/// REAL data that needs no corpus, which is what lets the one check requiring
/// a recipe that actually exists run in CI.
const String _legacyFixtureDir = 'test/fixtures/legacy-v0';

/// Every method the enforcement group knows how to send. A route is driven
/// with each method it does NOT declare, which must answer 405 — that is what
/// makes completeness method-grained instead of file-grained.
const List<String> _allMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

/// Statuses that mean "the credential was accepted and the handler ran".
///
/// The negative arms below used to assert only `code isNot('forbidden')`,
/// which a 404, a 422, a 429, a 405 or even an unenveloped 500 satisfies —
/// so a route that started throwing, or quietly lost a method, passed them.
/// Anything outside this allow-list means the probe was refused (401/403),
/// method-blocked (405), throttled (429) or crashed (5xx).
///
/// MEASURED, not guessed: across the 70 non-refusal arms this suite drives,
/// the only statuses that actually occur are 200 (the call succeeded), 404
/// (the deliberately missing id) and 422 (an empty JSON body the handler
/// then rejects on its merits). Keeping the set that tight is the point — a
/// new status here is a behavior change somebody should have to look at, not
/// something a padded allow-list waves through.
const Set<int> _reachedHandler = {
  HttpStatus.ok,
  HttpStatus.notFound,
  HttpStatus.unprocessableEntity,
};

/// Shaped like a real archive name (the route validates the pattern before it
/// looks for the file), but no such backup is ever created here.
const String _backupName = 'salt-backup-20260101T000000-manual.tar.gz';

/// The credential class a route method demands, read off its handler.
enum _Access {
  /// Reachable with no credential at all: sign-in, first-boot setup, and
  /// admin recovery must work while everyone is locked out.
  public,

  /// Any authenticated principal — member or admin.
  authenticated,

  /// The `admin` role (`requireAdmin`, or `requireWrite` = admin ∩ full).
  admin,
}

/// One method's declared posture on a route.
final class _Probe {
  const _Probe(
    this.method, {
    required this.access,
    this.mutates = false,
    this.readPatForbidden = false,
    this.anyPatForbidden = false,
    this.csrfPrecededBy,
    this.publicRefusalCode,
  });

  /// HTTP method this posture describes.
  final String method;

  /// Credential class the handler demands.
  final _Access access;

  /// Whether a COOKIE session must carry the anti-CSRF header. PATs are
  /// exempt by design (a browser never sends one ambiently).
  final bool mutates;

  /// Whether an admin's `read`-scope PAT is refused with a 403 — i.e. the
  /// handler calls `requireFullScope`/`requireWrite`, or otherwise turns a
  /// PAT away.
  final bool readPatForbidden;

  /// Whether a FULL-scope PAT is refused too — i.e. the route is session-only
  /// and no token of any scope can drive it. Implies [readPatForbidden]; the
  /// inventory group checks that implication. True on exactly one route
  /// today (`auth/change_password`, whose handler rejects `via != 'session'`).
  final bool anyPatForbidden;

  /// Error code a PUBLIC route answers the anonymous probe with when it
  /// refuses for a DOMAIN reason rather than a credential one. Null (the
  /// normal case) means the anonymous call must reach the handler.
  ///
  /// Set on `auth/setup` alone: first-boot setup is single-use, and by the
  /// time this suite probes it the matrix's own admin already exists, so it
  /// answers 403 `forbidden`. That is state, not authorization — the point
  /// of the public declaration is that it never answers `unauthorized`,
  /// which is asserted separately and unconditionally.
  final String? publicRefusalCode;

  /// Error code the no-CSRF-header probe actually receives when the handler
  /// answers something else BEFORE it consults `requireCsrf`. Null (the
  /// normal case) means the strict expectation applies: 403 `csrf`.
  ///
  /// Set on exactly one route today; see the SUSPECTED FINDING note on
  /// `recipes/[id]/note.dart` below. It PINS current behavior — it does not
  /// bless it.
  final String? csrfPrecededBy;
}

/// A classified route: the file on disk, the concrete path used to reach it,
/// the handler bound to its path parameters, and its per-method postures.
final class _Route {
  const _Route(this.file, this.path, this.handler, this.probes);

  /// Path relative to [_routesDir]; the completeness check compares these
  /// against the filesystem.
  final String file;

  /// Concrete request path used by the enforcement probes.
  final String path;

  /// The route's `onRequest`, with any path parameters already bound.
  final FutureOr<Response> Function(RequestContext) handler;

  /// One entry per HTTP method the route accepts.
  final List<_Probe> probes;
}

/// The authorization matrix. Every posture below was read off the handler in
/// `routes/api/v1/<file>` — never inferred from the path.
///
/// Every route here IS exercised in-process by the enforcement group; none had
/// to be declared-but-unexercised.
final List<_Route> _routes = [
  // --- admin reports and the log viewer (all admin-only reads; a read-scope
  // PAT may read them, exactly like the other admin GETs).
  const _Route(
    'api/v1/admin/logs.dart',
    '/api/v1/admin/logs',
    admin_logs.onRequest,
    [_Probe('GET', access: _Access.admin)],
  ),
  const _Route(
    'api/v1/admin/logs/export.dart',
    '/api/v1/admin/logs/export',
    admin_logs_export.onRequest,
    [_Probe('GET', access: _Access.admin)],
  ),
  const _Route(
    'api/v1/admin/nutrition_review.dart',
    '/api/v1/admin/nutrition_review',
    admin_nutrition.onRequest,
    [_Probe('GET', access: _Access.admin)],
  ),
  const _Route(
    'api/v1/admin/recipe_review.dart',
    '/api/v1/admin/recipe_review',
    admin_recipes.onRequest,
    [_Probe('GET', access: _Access.admin)],
  ),

  // --- auth. login/setup/recover are unauthenticated by necessity; their
  // anti-CSRF guard is the `application/json` content-type demand in
  // readJsonBody, since there is no session to key requireCsrf on.
  const _Route(
    'api/v1/auth/change_password.dart',
    '/api/v1/auth/change_password',
    auth_change_password.onRequest,
    // No requireFullScope, but `changePassword` refuses ANY pat (full-scope
    // included): a token must never be able to take over the account.
    [
      _Probe(
        'POST',
        access: _Access.authenticated,
        mutates: true,
        readPatForbidden: true,
        anyPatForbidden: true,
      ),
    ],
  ),
  const _Route(
    'api/v1/auth/login.dart',
    '/api/v1/auth/login',
    auth_login.onRequest,
    [_Probe('POST', access: _Access.public)],
  ),
  const _Route(
    'api/v1/auth/logout.dart',
    '/api/v1/auth/logout',
    auth_logout.onRequest,
    // A PAT cannot log out, but that is a 422 ("revoke it instead"), not a
    // permission refusal.
    [
      _Probe('POST', access: _Access.authenticated, mutates: true),
    ],
  ),
  const _Route(
    'api/v1/auth/me.dart',
    '/api/v1/auth/me',
    auth_me.onRequest,
    [_Probe('GET', access: _Access.authenticated)],
  ),
  const _Route(
    'api/v1/auth/recover.dart',
    '/api/v1/auth/recover',
    auth_recover.onRequest,
    [_Probe('POST', access: _Access.public)],
  ),
  const _Route(
    'api/v1/auth/setup.dart',
    '/api/v1/auth/setup',
    auth_setup.onRequest,
    // Unauthenticated, but single-use: this suite's own admin already exists
    // by the time the probe runs, so the handler answers 403 `forbidden`.
    // Still never `unauthorized`, which is what "public" claims.
    [_Probe('POST', access: _Access.public, publicRefusalCode: 'forbidden')],
  ),

  // --- backups. The DOWNLOAD demands full scope even though it is a read:
  // the archive carries the DB snapshot (password/session/token hashes, every
  // user's private notes), so a leaked read PAT must not exfiltrate it.
  _Route(
    'api/v1/backups/[name].dart',
    '/api/v1/backups/$_backupName',
    (context) => backup_name.onRequest(context, _backupName),
    const [
      _Probe('GET', access: _Access.admin, readPatForbidden: true),
      _Probe(
        'DELETE',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  const _Route(
    'api/v1/backups/index.dart',
    '/api/v1/backups',
    backups_index.onRequest,
    [
      _Probe('GET', access: _Access.admin),
      _Probe(
        'POST',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),

  // --- import.
  const _Route(
    'api/v1/import/candidates.dart',
    '/api/v1/import/candidates',
    import_candidates.onRequest,
    [_Probe('GET', access: _Access.admin)],
  ),
  const _Route(
    'api/v1/import/index.dart',
    '/api/v1/import',
    import_index.onRequest,
    [
      _Probe(
        'POST',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  _Route(
    'api/v1/import/jobs/[id].dart',
    '/api/v1/import/jobs/$_missingNumericId',
    (context) => import_job.onRequest(context, _missingNumericId),
    const [_Probe('GET', access: _Access.admin)],
  ),

  // --- library.
  const _Route(
    'api/v1/library/index.dart',
    '/api/v1/library',
    library_index.onRequest,
    [_Probe('GET', access: _Access.admin)],
  ),
  const _Route(
    'api/v1/library/rescan.dart',
    '/api/v1/library/rescan',
    library_rescan.onRequest,
    [
      _Probe(
        'POST',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),

  // --- nutrition. The manual food SEARCH is admin + full scope on a GET: a
  // cache miss spends the deployment's FDC request budget.
  const _Route(
    'api/v1/nutrition/bulk.dart',
    '/api/v1/nutrition/bulk',
    nutrition_bulk.onRequest,
    [
      _Probe(
        'POST',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  _Route(
    'api/v1/nutrition/jobs/[id].dart',
    '/api/v1/nutrition/jobs/$_missingNumericId',
    (context) => nutrition_job.onRequest(context, _missingNumericId),
    const [_Probe('GET', access: _Access.admin)],
  ),
  const _Route(
    'api/v1/nutrition/search.dart',
    '/api/v1/nutrition/search',
    nutrition_search.onRequest,
    [_Probe('GET', access: _Access.admin, readPatForbidden: true)],
  ),

  // --- recipes. Favorites and notes are PERSONAL data: any member may write
  // them and (unlike shared state) so may a read-scope PAT.
  _Route(
    'api/v1/recipes/[id]/favorite.dart',
    '/api/v1/recipes/$_missingRecipe/favorite',
    (context) => recipe_favorite.onRequest(context, _missingRecipe),
    const [
      _Probe('PUT', access: _Access.authenticated, mutates: true),
      _Probe('DELETE', access: _Access.authenticated, mutates: true),
    ],
  ),
  _Route(
    'api/v1/recipes/[id]/images/from_url.dart',
    '/api/v1/recipes/$_missingRecipe/images/from_url',
    (context) => image_from_url.onRequest(context, _missingRecipe),
    const [
      _Probe(
        'POST',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  _Route(
    'api/v1/recipes/[id]/images/index.dart',
    '/api/v1/recipes/$_missingRecipe/images',
    (context) => recipe_images.onRequest(context, _missingRecipe),
    const [
      _Probe(
        'POST',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  _Route(
    'api/v1/recipes/[id]/images/store.dart',
    '/api/v1/recipes/$_missingRecipe/images/store',
    (context) => image_store.onRequest(context, _missingRecipe),
    const [
      _Probe(
        'POST',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  _Route(
    'api/v1/recipes/[id]/images/store_from_url.dart',
    '/api/v1/recipes/$_missingRecipe/images/store_from_url',
    (context) => image_store_from_url.onRequest(context, _missingRecipe),
    const [
      _Probe(
        'POST',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  _Route(
    'api/v1/recipes/[id]/index.dart',
    '/api/v1/recipes/$_missingRecipe',
    (context) => recipe_detail.onRequest(context, _missingRecipe),
    const [
      _Probe('GET', access: _Access.authenticated),
      _Probe(
        'PUT',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
      _Probe(
        'DELETE',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  // SUSPECTED FINDING (pinned, NOT fixed — see the report for this item):
  // note.dart is the only mutating route that runs its recipe-existence
  // lookup BEFORE `requireCsrf`, so a CSRF-less write against a recipe that
  // does not exist is answered 404 instead of 403 `csrf`. Its sibling
  // favorite.dart, and nutrition/index.dart's explicit "Permission before
  // existence" comment, order it the other way round. No state changes and
  // the 404/403 difference is not observable cross-origin, so this is an
  // ordering inconsistency in a security guard rather than a live hole — but
  // it is the kind of drift this matrix exists to surface. The corpus-backed
  // group below proves CSRF *is* enforced once the recipe exists.
  _Route(
    'api/v1/recipes/[id]/note.dart',
    '/api/v1/recipes/$_missingRecipe/note',
    (context) => recipe_note.onRequest(context, _missingRecipe),
    const [
      _Probe('GET', access: _Access.authenticated),
      _Probe(
        'PUT',
        access: _Access.authenticated,
        mutates: true,
        csrfPrecededBy: 'not_found',
      ),
      _Probe(
        'DELETE',
        access: _Access.authenticated,
        mutates: true,
        csrfPrecededBy: 'not_found',
      ),
    ],
  ),
  _Route(
    'api/v1/recipes/[id]/nutrition/compute.dart',
    '/api/v1/recipes/$_missingRecipe/nutrition/compute',
    (context) => compute.onRequest(context, _missingRecipe),
    const [
      _Probe(
        'POST',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  _Route(
    'api/v1/recipes/[id]/nutrition/index.dart',
    '/api/v1/recipes/$_missingRecipe/nutrition',
    (context) => recipe_label.onRequest(context, _missingRecipe),
    const [
      _Probe('GET', access: _Access.authenticated),
      _Probe(
        'PUT',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  _Route(
    'api/v1/recipes/[id]/nutrition/matches/[pos].dart',
    '/api/v1/recipes/$_missingRecipe/nutrition/matches/$_matchPosition',
    (context) => match.onRequest(context, _missingRecipe, _matchPosition),
    const [
      _Probe(
        'PUT',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  _Route(
    'api/v1/recipes/[id]/nutrition/matches/index.dart',
    '/api/v1/recipes/$_missingRecipe/nutrition/matches',
    (context) => matches.onRequest(context, _missingRecipe),
    const [_Probe('GET', access: _Access.authenticated)],
  ),
  _Route(
    'api/v1/recipes/[id]/yaml.dart',
    '/api/v1/recipes/$_missingRecipe/yaml',
    (context) => recipe_yaml.onRequest(context, _missingRecipe),
    const [_Probe('GET', access: _Access.authenticated)],
  ),
  const _Route(
    'api/v1/recipes/index.dart',
    '/api/v1/recipes',
    recipes_index.onRequest,
    [
      _Probe('GET', access: _Access.authenticated),
      _Probe(
        'POST',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),

  // --- the caller's own credentials. Any authenticated user manages their
  // own sessions and tokens, but only with a full-scope credential: a leaked
  // read PAT must not be able to mint another one or sign anyone out.
  _Route(
    'api/v1/sessions/[id].dart',
    '/api/v1/sessions/$_missingSession',
    (context) => session_detail.onRequest(context, _missingSession),
    const [
      _Probe(
        'DELETE',
        access: _Access.authenticated,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  const _Route(
    'api/v1/sessions/index.dart',
    '/api/v1/sessions',
    sessions_index.onRequest,
    [_Probe('GET', access: _Access.authenticated)],
  ),
  const _Route(
    'api/v1/settings/fdc_key.dart',
    '/api/v1/settings/fdc_key',
    settings_fdc_key.onRequest,
    [
      _Probe('GET', access: _Access.admin),
      _Probe(
        'PUT',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),

  // --- tags. Reading the vocabulary is open to any signed-in user; changing
  // a chip's style is shared state, so admin + CSRF + full scope.
  _Route(
    'api/v1/tags/[name]/style.dart',
    '/api/v1/tags/$_missingTag/style',
    (context) => tag_style.onRequest(context, _missingTag),
    const [
      _Probe(
        'PUT',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  const _Route(
    'api/v1/tags/index.dart',
    '/api/v1/tags',
    tags_index.onRequest,
    [_Probe('GET', access: _Access.authenticated)],
  ),
  _Route(
    'api/v1/tokens/[id].dart',
    '/api/v1/tokens/$_missingNumericId',
    (context) => token_detail.onRequest(context, _missingNumericId),
    const [
      _Probe(
        'DELETE',
        access: _Access.authenticated,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  const _Route(
    'api/v1/tokens/index.dart',
    '/api/v1/tokens',
    tokens_index.onRequest,
    [
      _Probe('GET', access: _Access.authenticated),
      _Probe(
        'POST',
        access: _Access.authenticated,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),

  // --- account administration.
  _Route(
    'api/v1/users/[id]/index.dart',
    '/api/v1/users/$_missingNumericId',
    (context) => user_detail.onRequest(context, _missingNumericId),
    const [
      _Probe(
        'PATCH',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
      _Probe(
        'DELETE',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  _Route(
    'api/v1/users/[id]/reset_password.dart',
    '/api/v1/users/$_missingNumericId/reset_password',
    (context) => user_reset.onRequest(context, _missingNumericId),
    const [
      _Probe(
        'POST',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),
  const _Route(
    'api/v1/users/index.dart',
    '/api/v1/users',
    users_index.onRequest,
    [
      _Probe('GET', access: _Access.admin),
      _Probe(
        'POST',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),

  // --- outside /api/v1. These three used to be invisible to this matrix even
  // though the file claimed to span every endpoint; the image server in
  // particular requires auth and carries the path-containment invariant on an
  // internet-facing deployment.
  const _Route(
    'healthz.dart',
    '/healthz',
    healthz.onRequest,
    // Deliberately unauthenticated: a liveness probe runs before anyone can
    // sign in, and it reveals only whether the instance has been claimed.
    [_Probe('GET', access: _Access.public)],
  ),
  const _Route(
    'index.dart',
    '/',
    app_shell.onRequest,
    // The web-app shell. Public by necessity — the sign-in screen is inside
    // the bundle it serves.
    [_Probe('GET', access: _Access.public)],
  ),
  _Route(
    'images/[source]/[file].dart',
    '/images/$_missingImageSource/$_missingImageFile',
    (context) => library_image.onRequest(
      context,
      _missingImageSource,
      _missingImageFile,
    ),
    // Recipe photos are behind the login like everything else; a read-scope
    // PAT may fetch them (reading is what `read` scope is for).
    const [_Probe('GET', access: _Access.authenticated)],
  ),
];

/// Guard calls that mean "this route demands a credential". A route declared
/// [_Access.public] must call none of them; every other route must call at
/// least one.
const List<String> _authGuards = [
  'requireUser(',
  'requireUserAllowingPasswordChange(',
  'requireAdmin(',
  'requireWrite(',
];

/// Methods whose probe carries a JSON body, so a route that reads one gets
/// past its content-type check and reaches the code after its guards.
const Set<String> _bodyMethods = {'POST', 'PUT', 'PATCH'};

/// A response reduced to what an authorization assertion cares about.
final class _Reply {
  _Reply(this.status, this.body);

  /// HTTP status code.
  final int status;

  /// Raw response body (may not be JSON — the log export is text/plain).
  final String body;

  /// The error envelope's `code`, or null when the body is not an envelope.
  String? get code {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          return error['code'] as String?;
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

/// A provider the matrix must never reach: every probe is refused by a guard
/// or 404s on a missing recipe first. Reaching FoodData Central would mean a
/// probe got further than its declared posture allows.
final class _UnreachableProvider implements NutritionProvider {
  @override
  Future<List<FdcCandidate>> search(String query) async =>
      throw StateError('a route auth probe reached FDC search("$query")');

  @override
  Future<FdcFood?> food(int fdcId) async =>
      throw StateError('a route auth probe reached FDC food($fdcId)');
}

/// Self-verifying authorization matrix for every `routes/` endpoint (review
/// item T4).
void main() {
  group('route inventory (no corpus, no server — CI runs this)', () {
    test('every route file under $_routesDir is classified', () {
      final dir = Directory(_routesDir);
      expect(
        dir.existsSync(),
        isTrue,
        reason:
            'run this suite from apps/server: "$_routesDir" is not there '
            'relative to ${Directory.current.path}',
      );
      final onDisk = <String>{
        for (final entity in dir.listSync(recursive: true))
          if (entity is File && entity.path.endsWith('.dart'))
            entity.path.substring(_routesDir.length + 1),
      };
      expect(onDisk, isNotEmpty, reason: 'the walk found no route files');
      expect(
        onDisk,
        contains(_rootMiddlewareFile),
        reason:
            "$_routesDir/$_rootMiddlewareFile is dart_frog's fixed entry "
            'point; if it is gone, nothing installs the production chain.',
      );
      final declared = {for (final route in _routes) route.file};

      final unclassified = onDisk.difference(declared).where((file) {
        // The ROOT middleware is not a route; it has its own pin below.
        // A _middleware.dart at any deeper path is NOT excused — it
        // rewrites the posture of every route beneath it.
        return file != _rootMiddlewareFile;
      }).toList()..sort();
      expect(
        unclassified,
        isEmpty,
        reason:
            'These $_routesDir files have no entry in the authorization '
            'matrix: $unclassified. Read each handler, add a _Route to '
            '_routes in $_thisFile declaring its real posture (access / '
            'mutates / readPatForbidden), and the enforcement group will '
            'prove that posture holds. A nested _middleware.dart also lands '
            'here on purpose: it changes the auth posture of everything '
            'beneath it.',
      );

      final vanished = declared.difference(onDisk).toList()..sort();
      expect(
        vanished,
        isEmpty,
        reason:
            'The matrix in $_thisFile classifies routes that no longer '
            'exist: $vanished. Delete their _Route entries.',
      );
    });

    test('each route is declared once, with a unique request path', () {
      final files = [for (final route in _routes) route.file];
      final paths = [for (final route in _routes) route.path];
      expect(
        files.toSet(),
        hasLength(files.length),
        reason: 'a route file is classified twice in $_thisFile',
      );
      expect(
        paths.toSet(),
        hasLength(paths.length),
        reason:
            'two routes share a request path, so the test dispatcher cannot '
            'tell them apart',
      );
      for (final route in _routes) {
        expect(
          route.probes,
          isNotEmpty,
          reason: '${route.file} declares no method to exercise',
        );
        final methods = [for (final probe in route.probes) probe.method];
        expect(
          methods.toSet(),
          hasLength(methods.length),
          reason: '${route.file} declares the same method twice',
        );
        for (final probe in route.probes) {
          expect(
            _allMethods,
            contains(probe.method),
            reason:
                '${route.file} declares ${probe.method}, which the '
                'undeclared-method sweep does not know how to send. Add it '
                'to _allMethods in $_thisFile.',
          );
          if (probe.anyPatForbidden) {
            expect(
              probe.readPatForbidden,
              isTrue,
              reason:
                  '${route.file} ${probe.method} refuses a FULL-scope PAT but '
                  'is declared to admit a read-scope one, which is a '
                  'contradiction (read ⊂ full).',
            );
          }
        }
      }
    });

    test('each declared request path is the one dart_frog derives', () {
      // Replaces an earlier "a public route must not 404" guard that could
      // never fire: the test dispatcher is keyed on route.path and send()
      // requests exactly route.path, so the lookup always hit. THIS is the
      // invariant that guard was reaching for — that the path a probe drives
      // is the URL dart_frog's file-based routing actually binds the handler
      // to, so a probe cannot exercise a posture at a URL nobody can reach.
      for (final route in _routes) {
        final fileSegments = route.file
            .substring(0, route.file.length - '.dart'.length)
            .split('/');
        if (fileSegments.last == 'index') {
          fileSegments.removeLast();
        }
        final pathSegments = route.path.split('/')..removeAt(0);
        if (pathSegments.length == 1 && pathSegments.single.isEmpty) {
          pathSegments.clear();
        }
        expect(
          pathSegments,
          hasLength(fileSegments.length),
          reason:
              '${route.file} maps to a ${fileSegments.length}-segment URL, '
              'but its declared path "${route.path}" has '
              '${pathSegments.length}.',
        );
        for (var i = 0; i < fileSegments.length; i++) {
          final expected = fileSegments[i];
          final actual = pathSegments[i];
          if (expected.startsWith('[') && expected.endsWith(']')) {
            // A dynamic segment: any non-empty value binds it.
            expect(
              actual,
              isNotEmpty,
              reason:
                  '${route.file} leaves the $expected segment of '
                  '"${route.path}" empty.',
            );
          } else {
            expect(
              actual,
              expected,
              reason:
                  '${route.file} is served at segment $i "$expected", but '
                  'the declared path "${route.path}" says "$actual".',
            );
          }
        }
      }
    });

    test('$_rootMiddlewareFile still installs the production chain', () {
      // A source tripwire, not a proof — dart_frog generates its entry point
      // at build time, so nothing here executes routes/_middleware.dart. But
      // gutting that file is exactly how the enforcement group below could go
      // on driving buildAppMiddleware while production served no middleware
      // at all, and this catches that.
      final source = File(
        '$_routesDir/$_rootMiddlewareFile',
      ).readAsStringSync();
      expect(
        source,
        contains('Handler middleware(Handler handler)'),
        reason:
            "$_routesDir/$_rootMiddlewareFile must export dart_frog's "
            'middleware entry point.',
      );
      expect(
        source,
        contains('buildAppMiddleware('),
        reason:
            '$_routesDir/$_rootMiddlewareFile no longer calls '
            'buildAppMiddleware, so production does not run the chain this '
            'file drives in $_thisFile: auth, CSRF, error envelopes and the '
            'security headers would all be absent in the real server while '
            'every test here stayed green.',
      );
    });

    test('non-public routes call an auth guard; public routes do not', () {
      // HONEST LIMIT: this is a substring scan of the handler source, so it
      // is a TRIPWIRE, not a proof. A guard name inside a comment, a string
      // literal or an unreachable branch satisfies it, and a guard applied to
      // only one of several methods satisfies it too. What actually proves
      // the posture is the enforcement group, which sends real requests for
      // every declared method AND every undeclared one. The scan earns its
      // keep by failing loudly and cheaply the moment a guard call
      // disappears from a file altogether.
      for (final route in _routes) {
        final source = File('$_routesDir/${route.file}').readAsStringSync();
        final guards = [
          for (final guard in _authGuards)
            if (source.contains(guard)) guard,
        ];
        final isPublic = route.probes.every(
          (probe) => probe.access == _Access.public,
        );
        if (isPublic) {
          expect(
            guards,
            isEmpty,
            reason:
                '${route.file} is declared public but calls $guards. Either '
                'it gained a credential requirement (reclassify it) or the '
                'guard is a mistake.',
          );
        } else {
          expect(
            guards,
            isNotEmpty,
            reason:
                '${route.file} is declared to need a credential but calls '
                'none of $_authGuards — it may now be reachable '
                'unauthenticated.',
          );
        }
      }
    });

    test('mutating postures and requireCsrf agree, in both directions', () {
      // Both directions matter. Missing requireCsrf on a declared mutation is
      // the hole; a route that calls requireCsrf while declaring no mutation
      // means the declaration stopped exercising the CSRF probe, which is how
      // this check would otherwise be quietly switched off.
      //
      // HONEST LIMIT: like the guard scan above, `contains('requireCsrf(')`
      // is a substring tripwire. It cannot see WHICH method the call guards,
      // so a route that calls requireCsrf on its PUT but not its DELETE
      // passes here. The real proof is the no-CSRF-header probe in the
      // enforcement group, which is run per declared mutating method.
      for (final route in _routes) {
        final declaresMutation = route.probes.any((probe) => probe.mutates);
        final source = File('$_routesDir/${route.file}').readAsStringSync();
        final callsCsrf = source.contains('requireCsrf(');
        if (declaresMutation) {
          expect(
            callsCsrf,
            isTrue,
            reason:
                '${route.file} has a mutating method but never calls '
                'requireCsrf: a cross-site page could drive it with the '
                "victim's session cookie.",
          );
        } else {
          expect(
            callsCsrf,
            isFalse,
            reason:
                '${route.file} calls requireCsrf but declares no mutating '
                'method, so the no-CSRF-header probe never runs against it. '
                'Mark the mutating method `mutates: true` in $_thisFile.',
          );
        }
      }
    });
  });

  group('enforcement (every declared posture, over the real chain)', () {
    late Directory tempDir;
    late ServerConfig config;
    late SaltDatabase db;
    late HttpServer server;
    late Uri baseUri;
    late int adminId;
    late int memberId;
    late String adminReadPat;
    late String memberFullPat;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('salt_route_auth_');
      config = ServerConfig.fromEnvironment(
        environment: {'DATA_DIR': tempDir.path, 'LOG_LEVEL': 'ERROR'},
      );
      configureLogging(config);
      db = SaltDatabase.open(config.dbPath);

      // The production chain, built by the same function
      // routes/_middleware.dart calls — so a reorder that breaks a
      // security property fails here instead of staying green behind a
      // parallel hand-rolled pipeline.
      final pipeline = buildAppMiddleware(
        _dispatch,
        config: config,
        database: db,
        authRuntime: AuthRuntime(),
        nutritionProvider: _UnreachableProvider(),
        // maxRequests: 0 disables the search limiter; the listing probe is
        // a plain page fetch and must not be throttled into a 429 that
        // masks an authorization result.
        searchRateLimiter: RequestRateLimiter(maxRequests: 0),
        searchService: () => InlineSearchService(db),
        logStore: LogStore(directory: config.logDir),
      );
      server = await serve(pipeline, InternetAddress.loopbackIPv4, 0);
      baseUri = Uri.parse('http://127.0.0.1:${server.port}');

      // Passwords are never used: every credential below is minted straight
      // into the DB, so nothing verifies this placeholder hash.
      const placeholderHash = 'not-a-hash; no probe signs in with a password';
      adminId = db.createUser(
        username: 'matrix-admin',
        passwordHash: placeholderHash,
        role: 'admin',
      );
      memberId = db.createUser(
        username: 'matrix-member',
        passwordHash: placeholderHash,
        role: 'member',
      );

      // Two of the four cells of the role x credential matrix. The admin's
      // read PAT tests role ∩ scope narrowing on the SCOPE axis; the
      // member's full PAT tests it on the ROLE axis (a token whose scope is
      // unrestricted must still not exceed its owner's role).
      final readPat = generatePat();
      db.createApiToken(
        userId: adminId,
        name: 'admin read pat',
        prefix: readPat.prefix,
        tokenHash: hashToken(readPat.token),
        scope: 'read',
      );
      adminReadPat = readPat.token;

      final fullPat = generatePat();
      db.createApiToken(
        userId: memberId,
        name: 'member full pat',
        prefix: fullPat.prefix,
        tokenHash: hashToken(fullPat.token),
        scope: 'full',
      );
      memberFullPat = fullPat.token;
    });

    tearDownAll(() async {
      await server.close(force: true);
      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    /// A fresh cookie header for [userId].
    ///
    /// Fresh per probe on purpose: POST /auth/logout deletes the session it
    /// authenticated with, so a shared token would silently invalidate every
    /// later probe and turn real 403s into meaningless 401s.
    Map<String, String> cookieFor(int userId) {
      final token = generateOpaqueToken();
      db.createSession(
        tokenHash: hashToken(token),
        userId: userId,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        remember: false,
      );
      return {'Cookie': '$sessionCookieName=$token'};
    }

    Future<_Reply> send(
      String method,
      String path, {
      Map<String, String> headers = const {},
      Object? jsonBody,
    }) async {
      final client = HttpClient();
      try {
        final request = await client.openUrl(method, baseUri.resolve(path));
        headers.forEach(request.headers.set);
        if (_bodyMethods.contains(method)) {
          request.headers.contentType = ContentType.json;
          request.write(jsonBody == null ? '{}' : jsonEncode(jsonBody));
        }
        final response = await request.close();
        final body = await utf8.decoder.bind(response).join();
        return _Reply(response.statusCode, body);
      } finally {
        client.close();
      }
    }

    /// Asserts [reply] shows the credential was ACCEPTED and the handler ran.
    ///
    /// An allow-list, not `code isNot('forbidden')`: that older form was also
    /// satisfied by a 429 from a rate limiter, by an unenveloped 5xx, and by
    /// a 401, so a route that started throwing passed both negative arms.
    void expectReachedHandler(_Reply reply, String label, String why) {
      expect(
        reply.status,
        isIn(_reachedHandler),
        reason: '$label $why — got ${reply.status}: ${reply.body}',
      );
    }

    /// Drives one declared posture and asserts it actually holds. Every
    /// expectation is derived from [probe] — the same declaration the
    /// completeness group checks — so the list and the behavior cannot drift
    /// apart.
    Future<void> exercise(_Route route, _Probe probe) async {
      final label = '${probe.method} ${route.path} [${route.file}]';

      // 1. No credential at all.
      final anonymous = await send(probe.method, route.path);
      if (probe.access == _Access.public) {
        expect(
          anonymous.status,
          isNot(HttpStatus.unauthorized),
          reason:
              '$label is declared public — it has to answer with no '
              'credential: ${anonymous.body}',
        );
        expect(
          anonymous.code,
          isNot('unauthorized'),
          reason:
              '$label is declared public but demanded a credential: '
              '${anonymous.body}',
        );
        final refusal = probe.publicRefusalCode;
        if (refusal == null) {
          expectReachedHandler(
            anonymous,
            label,
            'is declared public, so an anonymous call must reach the handler',
          );
        } else {
          expect(
            anonymous.code,
            refusal,
            reason:
                '$label pins a public route that refuses for a DOMAIN reason '
                "('$refusal'). If that stopped being true, drop "
                'publicRefusalCode from its _Probe: ${anonymous.body}',
          );
        }
        // Re-running an unauthenticated endpoint under a credential only
        // exercises its sign-in rate limiter; there is no role axis here.
        return;
      }
      expect(
        anonymous.status,
        HttpStatus.unauthorized,
        reason: '$label must 401 without a credential: ${anonymous.body}',
      );
      expect(anonymous.code, 'unauthorized', reason: label);

      // 2. A member session, WITH the anti-CSRF header, so a CSRF rejection
      //    can never be mistaken for a role rejection.
      final member = await send(
        probe.method,
        route.path,
        headers: {
          ...cookieFor(memberId),
          csrfHeaderName: csrfHeaderValue,
        },
      );
      if (probe.access == _Access.admin) {
        expect(
          member.status,
          HttpStatus.forbidden,
          reason: '$label is admin-only; a member must 403: ${member.body}',
        );
        expect(member.code, 'forbidden', reason: label);
      } else {
        expectReachedHandler(
          member,
          label,
          'is declared open to any authenticated user, but a member session '
          'did not get through',
        );
      }

      // 3. A cookie session on a mutating route with no anti-CSRF header —
      //    the shape a cross-site page can produce. Driven with BOTH roles
      //    where both are allowed: CSRF is orthogonal to role, and probing
      //    only the admin left the anti-CSRF guard on the 19 member-reachable
      //    postures untested.
      if (probe.mutates) {
        final sessions = <String, Map<String, String>>{
          'admin': cookieFor(adminId),
          if (probe.access != _Access.admin) 'member': cookieFor(memberId),
        };
        for (final entry in sessions.entries) {
          final noCsrf = await send(
            probe.method,
            route.path,
            headers: entry.value,
          );
          final who = '$label (${entry.key} cookie)';
          final precededBy = probe.csrfPrecededBy;
          if (precededBy == null) {
            expect(
              noCsrf.status,
              HttpStatus.forbidden,
              reason:
                  '$who must reject a cookie session that omits '
                  '$csrfHeaderName: ${noCsrf.body}',
            );
            expect(noCsrf.code, 'csrf', reason: who);
          } else {
            expect(
              noCsrf.code,
              precededBy,
              reason:
                  '$who pins a DEVIATION: its CSRF check runs after another '
                  "guard, so this probe gets '$precededBy'. If the handler "
                  'was reordered so requireCsrf comes first, drop '
                  'csrfPrecededBy from its _Probe: ${noCsrf.body}',
            );
          }
        }
      }

      // 4. An ADMIN's read-scope PAT: effective permission = role ∩ scope,
      //    narrowed on the SCOPE axis.
      final readPat = await send(
        probe.method,
        route.path,
        headers: {'Authorization': 'Bearer $adminReadPat'},
      );
      if (probe.readPatForbidden) {
        expect(
          readPat.status,
          HttpStatus.forbidden,
          reason: '$label must refuse a read-scope PAT: ${readPat.body}',
        );
        expect(readPat.code, 'forbidden', reason: label);
      } else {
        expectReachedHandler(
          readPat,
          label,
          'is declared reachable with a read-scope PAT, but it was refused',
        );
      }

      // 5. A MEMBER's full-scope PAT: the same product narrowed on the ROLE
      //    axis. Without this, nothing proved that an unrestricted token
      //    still cannot exceed its owner's role, and nothing exercised a PAT
      //    on the routes that demand full scope but not admin.
      final fullPat = await send(
        probe.method,
        route.path,
        headers: {'Authorization': 'Bearer $memberFullPat'},
      );
      if (probe.access == _Access.admin || probe.anyPatForbidden) {
        expect(
          fullPat.status,
          HttpStatus.forbidden,
          reason:
              '$label must refuse a member full-scope PAT '
              '(${probe.anyPatForbidden ? 'session-only route' : 'admin-only '
                        'route'}): ${fullPat.body}',
        );
        expect(fullPat.code, 'forbidden', reason: label);
      } else {
        expectReachedHandler(
          fullPat,
          label,
          'is open to any authenticated principal and takes PATs, so a '
          "member's full-scope token must get through",
        );
      }
    }

    /// Drives every method the route does NOT declare and demands a 405.
    ///
    /// This is what makes completeness method-grained. Layer 1 diffs FILE
    /// sets, so widening an already-declared route's method guard — say
    /// adding a POST branch to tags/index.dart behind nothing but
    /// `requireUser` — used to produce no declaration pressure at all: the
    /// file was already listed, still contained no `requireCsrf(`, and still
    /// declared no mutating method, so every layer agreed with itself and
    /// the matrix stayed green. Now the undeclared method answers something
    /// other than 405 and this fails until someone declares its posture.
    ///
    /// Sent with an admin cookie AND the anti-CSRF header on purpose: the
    /// 405 must come from the route's own method guard, not from a
    /// credential check that happens to run first.
    Future<void> sweepUndeclaredMethods(_Route route) async {
      final declared = {for (final probe in route.probes) probe.method};
      for (final method in _allMethods) {
        if (declared.contains(method)) {
          continue;
        }
        final reply = await send(
          method,
          route.path,
          headers: {...cookieFor(adminId), csrfHeaderName: csrfHeaderValue},
        );
        final label = '$method ${route.path} [${route.file}]';
        expect(
          reply.status,
          HttpStatus.methodNotAllowed,
          reason:
              '$label is not declared in $_thisFile, so the route must '
              'refuse it with 405. It answered ${reply.status} instead, '
              'which means the handler accepts a method whose auth posture '
              'nobody has declared or proven: ${reply.body}',
        );
        expect(reply.code, 'method_not_allowed', reason: label);
      }
    }

    for (final route in _routes) {
      test(route.file, () async {
        for (final probe in route.probes) {
          await exercise(route, probe);
        }
        await sweepUndeclaredMethods(route);
      });
    }

    // The one place the matrix has to reach past a missing id: note.dart's
    // CSRF guard sits behind its existence check (the SUSPECTED FINDING
    // above), so the declared probe against a nonexistent recipe pins
    // `not_found` — an assertion that holds whether or not requireCsrf is
    // still there. Under a mutation that narrowed the shared CSRF guard to
    // POST, ten other routes failed and note.dart stayed green.
    //
    // This group is the check that actually bites, and it needs a recipe
    // that EXISTS. It used to be corpus-gated, which meant CI — the one
    // place a regression would ship from — never ran it. The precondition is
    // now established corpus-free from the real legacy-v0 recipe committed
    // at test/fixtures/legacy-v0/ (real data preserved at the P8 cutover,
    // not a fabricated fixture), so the guard is proven wherever this runs.
    group('note.dart CSRF, verified on a real recipe', () {
      late String notePath;

      setUpAll(() async {
        final summary = importLegacyRoot(
          sourceRootPath: _legacyFixtureDir,
          db: db,
          config: config,
        );
        expect(
          summary.imported,
          1,
          reason: 'the committed legacy-v0 fixture must import cleanly',
        );
        // Derive the slug from the API rather than hard-coding it, so a
        // change to the slugifier cannot silently point this at nothing.
        final listing = await send(
          'GET',
          '/api/v1/recipes',
          headers: cookieFor(adminId),
        );
        expect(listing.status, HttpStatus.ok, reason: listing.body);
        final items =
            (jsonDecode(listing.body) as Map<String, dynamic>)['items']
                as List<dynamic>;
        final card = items.single as Map<String, dynamic>;
        final slug = card['slug'] as String;
        notePath = '/api/v1/recipes/$slug/note';
        // The declared matrix only knows the missing-recipe path; register
        // the real one so the dispatcher can reach the same handler.
        _extraHandlers[notePath] = (context) =>
            recipe_note.onRequest(context, slug);
        addTearDown(() => _extraHandlers.remove(notePath));
      });

      test('a cookie session without the header cannot write a note', () async {
        for (final method in ['PUT', 'DELETE']) {
          final reply = await send(
            method,
            notePath,
            headers: cookieFor(memberId),
          );
          expect(
            reply.status,
            HttpStatus.forbidden,
            reason: '$method $notePath: ${reply.body}',
          );
          expect(reply.code, 'csrf', reason: '$method $notePath');
        }
      });

      test('the same writes succeed once the header is present', () async {
        // Without this the test above would pass even if note writes were
        // broken for every caller.
        final written = await send(
          'PUT',
          notePath,
          headers: {...cookieFor(memberId), csrfHeaderName: csrfHeaderValue},
          jsonBody: {'note': 'CSRF control: this write must go through.'},
        );
        expect(written.status, HttpStatus.ok, reason: written.body);
      });
    });
  });
}

/// Test-side router: maps the declared request path back to the declared
/// handler. Built from [_routes], so a route can only be reachable here if it
/// is classified there.
final Map<String, FutureOr<Response> Function(RequestContext)> _handlers = {
  for (final route in _routes) route.path: route.handler,
};

/// Extra paths registered at runtime for the one check that needs a recipe
/// which really exists. Never consulted by the completeness group or the
/// undeclared-method sweep, both of which read [_routes] alone.
final Map<String, FutureOr<Response> Function(RequestContext)> _extraHandlers =
    {};

FutureOr<Response> _dispatch(RequestContext context) {
  final path = context.request.uri.path;
  final handler = _handlers[path] ?? _extraHandlers[path];
  if (handler == null) {
    return Response(statusCode: HttpStatus.notFound, body: 'no route');
  }
  return handler(context);
}
