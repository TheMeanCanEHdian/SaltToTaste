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
// (note.dart's CSRF guard, below) uses the real legacy-v0 recipe committed at
// test/fixtures/legacy-v0/, not a fabricated one. Review item T1: assertions
// that need no corpus must not sit behind a corpus gate.
//
// The credentials here are synthesized because auth inputs cannot come from a
// recipe corpus; no probe ever signs in with a password, so the stored hash is
// a placeholder that nothing verifies.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:logging/logging.dart';
import 'package:salt_server/src/app_pipeline.dart';
import 'package:salt_server/src/auth/rate_limiter.dart';
import 'package:salt_server/src/auth/tokens.dart';
import 'package:salt_server/src/bootstrap.dart' show fdcApiKeySetting;
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
/// MEASURED, not guessed: across the non-refusal arms this suite drives, the
/// only statuses that actually occur are 200 (the call succeeded), 201
/// (`POST /api/v1/backups`, the one probed mutation that runs to completion
/// rather than falling through to a missing id), 404 (the deliberately
/// missing id) and 422 (an empty JSON body the handler then rejects on its
/// merits). Keeping the set that tight is the point — a new status here is a
/// behavior change somebody should have to look at, not something a padded
/// allow-list waves through.
const Set<int> _reachedHandler = {
  HttpStatus.ok,
  HttpStatus.created,
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
    this.sideEffect,
    this.readPatForbidden = false,
    this.anyPatForbidden = false,
    this.publicRefusalCode,
  });

  /// HTTP method this posture describes.
  final String method;

  /// Credential class the handler demands.
  final _Access access;

  /// Whether a COOKIE session must carry the anti-CSRF header. PATs are
  /// exempt by design (a browser never sends one ambiently).
  final bool mutates;

  /// Whether this NON-mutating method must also refuse a cross-site drive.
  ///
  /// `requireCsrf` gates mutating methods only, and the session cookie is
  /// `SameSite=Lax`, which a browser does send on a cross-site top-level
  /// navigation. A GET that spends real resources — an outbound FDC call, an
  /// isolate spawn, a synchronous whole-history log parse, a synchronous
  /// directory walk, a whole-database file stream — is therefore drivable
  /// from an attacker's page unless it demands proof the request is not
  /// cross-site (finding S12).
  ///
  /// NULL on a GET means UNDECLARED, and the inventory group fails until a
  /// human writes `true` or `false`. That is the difference between a drift
  /// lock and a coverage check: `sideEffect` used to default to false, so a
  /// new side-effectful GET with no guard agreed with its own declaration
  /// and landed silently — which is exactly how `backups/[name].dart` and
  /// `import/candidates.dart` sat unguarded next to the three routes S12
  /// named. Non-GET methods may leave it null: `requireCsrf` covers them.
  final bool? sideEffect;

  /// [sideEffect] with the undeclared case resolved to "no guard expected".
  /// Only ever reached after the inventory group has proven no GET is
  /// undeclared.
  bool get refusesCrossSite => sideEffect ?? false;

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
  // --- admin reports and the log viewer. The two LOG routes demand full
  // scope even though they are reads, like the backup download and for the
  // same reason: the log is secret material no other endpoint returns (client
  // IPs, recovery lines, backup names, every request path), so a leaked
  // read-scope PAT must not exfiltrate it (finding S14). Both are also
  // side-effectful enough to refuse a cross-site drive (S12): `?scan=full`
  // spawns an isolate, and the export parses the whole history synchronously.
  const _Route(
    'api/v1/admin/logs.dart',
    '/api/v1/admin/logs',
    admin_logs.onRequest,
    [
      _Probe(
        'GET',
        access: _Access.admin,
        sideEffect: true,
        readPatForbidden: true,
      ),
    ],
  ),
  const _Route(
    'api/v1/admin/logs/export.dart',
    '/api/v1/admin/logs/export',
    admin_logs_export.onRequest,
    [
      _Probe(
        'GET',
        access: _Access.admin,
        sideEffect: true,
        readPatForbidden: true,
      ),
    ],
  ),
  const _Route(
    'api/v1/admin/nutrition_review.dart',
    '/api/v1/admin/nutrition_review',
    admin_nutrition.onRequest,
    [_Probe('GET', access: _Access.admin, sideEffect: false)],
  ),
  const _Route(
    'api/v1/admin/recipe_review.dart',
    '/api/v1/admin/recipe_review',
    admin_recipes.onRequest,
    [_Probe('GET', access: _Access.admin, sideEffect: false)],
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
    [_Probe('GET', access: _Access.authenticated, sideEffect: false)],
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
      // sideEffect on the DOWNLOAD (S12's class, closed here rather than on
      // the three URLs the finding happened to name): it streams the whole
      // database snapshot off disk, and the app opens it with `launchUrl`,
      // which is precisely the cross-site-navigable shape.
      _Probe(
        'GET',
        access: _Access.admin,
        sideEffect: true,
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
  const _Route(
    'api/v1/backups/index.dart',
    '/api/v1/backups',
    backups_index.onRequest,
    [
      _Probe('GET', access: _Access.admin, sideEffect: false),
      _Probe(
        'POST',
        access: _Access.admin,
        mutates: true,
        readPatForbidden: true,
      ),
    ],
  ),

  // --- import. `candidates` walks the import directory and every direct
  // child SYNCHRONOUSLY, counting every YAML file in each (~1,200 dirents
  // for a real corpus root), so it is side-effectful in S12's sense too.
  const _Route(
    'api/v1/import/candidates.dart',
    '/api/v1/import/candidates',
    import_candidates.onRequest,
    [_Probe('GET', access: _Access.admin, sideEffect: true)],
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
    const [_Probe('GET', access: _Access.admin, sideEffect: false)],
  ),

  // --- library.
  const _Route(
    'api/v1/library/index.dart',
    '/api/v1/library',
    library_index.onRequest,
    [_Probe('GET', access: _Access.admin, sideEffect: false)],
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
    const [_Probe('GET', access: _Access.admin, sideEffect: false)],
  ),
  const _Route(
    'api/v1/nutrition/search.dart',
    '/api/v1/nutrition/search',
    nutrition_search.onRequest,
    [
      _Probe(
        'GET',
        access: _Access.admin,
        sideEffect: true,
        readPatForbidden: true,
      ),
    ],
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
      _Probe('GET', access: _Access.authenticated, sideEffect: false),
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
  // note.dart used to run its recipe-existence lookup BEFORE `requireCsrf`,
  // so a CSRF-less write against a recipe that does not exist answered 404
  // instead of 403 `csrf` — an existence oracle for an unauthenticated
  // cross-origin probe, and the only mutating route that ordered its guards
  // that way. This declaration pinned the deviation via `csrfPrecededBy`; the
  // handler now calls requireCsrf first, like favorite.dart and like
  // nutrition/index.dart's "Permission before existence" comment, so the
  // strict expectation applies and the escape hatch is gone. These probes
  // need no corpus, so a reordering regression fails in CI too.
  _Route(
    'api/v1/recipes/[id]/note.dart',
    '/api/v1/recipes/$_missingRecipe/note',
    (context) => recipe_note.onRequest(context, _missingRecipe),
    const [
      _Probe('GET', access: _Access.authenticated, sideEffect: false),
      _Probe('PUT', access: _Access.authenticated, mutates: true),
      _Probe('DELETE', access: _Access.authenticated, mutates: true),
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
      _Probe('GET', access: _Access.authenticated, sideEffect: false),
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
    const [_Probe('GET', access: _Access.authenticated, sideEffect: false)],
  ),
  _Route(
    'api/v1/recipes/[id]/yaml.dart',
    '/api/v1/recipes/$_missingRecipe/yaml',
    (context) => recipe_yaml.onRequest(context, _missingRecipe),
    const [_Probe('GET', access: _Access.authenticated, sideEffect: false)],
  ),
  const _Route(
    'api/v1/recipes/index.dart',
    '/api/v1/recipes',
    recipes_index.onRequest,
    [
      _Probe('GET', access: _Access.authenticated, sideEffect: false),
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
    [_Probe('GET', access: _Access.authenticated, sideEffect: false)],
  ),
  const _Route(
    'api/v1/settings/fdc_key.dart',
    '/api/v1/settings/fdc_key',
    settings_fdc_key.onRequest,
    [
      _Probe('GET', access: _Access.admin, sideEffect: false),
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
    [_Probe('GET', access: _Access.authenticated, sideEffect: false)],
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
      _Probe('GET', access: _Access.authenticated, sideEffect: false),
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
      _Probe('GET', access: _Access.admin, sideEffect: false),
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
    [_Probe('GET', access: _Access.public, sideEffect: false)],
  ),
  const _Route(
    'index.dart',
    '/',
    app_shell.onRequest,
    // The web-app shell. Public by necessity — the sign-in screen is inside
    // the bundle it serves.
    [_Probe('GET', access: _Access.public, sideEffect: false)],
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
    const [_Probe('GET', access: _Access.authenticated, sideEffect: false)],
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

/// The ONE shared cross-site guard (`middleware/auth.dart`). Every
/// side-effectful GET calls it; nothing re-derives it. It used to be copied
/// into five handlers, each with its own `startsWith('bearer ')` test, and the
/// copies drifted from the authenticator's parse — a malformed
/// `Authorization: Bearer <vertical tab>` exempted a request the ambient
/// cookie then authenticated (200 where the same request with no
/// `Authorization` was 403).
const String _crossSiteGuard = 'requireNotCrossSite';

/// For each route that declares `sideEffect: true`, the first expensive call
/// in its handler — the thing the cross-site guard exists to keep an
/// attacker's page from spending. [_crossSiteGuard] must appear ABOVE it.
///
/// Placement is the whole point and NO status assertion can see it: with the
/// guard moved BELOW `importCandidates(config)`, the ~1,200-dirent walk runs
/// and the refusal is thrown afterwards, so every enforcement probe below
/// still reads 403 and stays green. Measured — that exact edit passed this
/// suite until this check existed.
///
/// A substring order check, so it is a TRIPWIRE like the guard scans above,
/// not a proof; the runtime witnesses in "a refused cross-site drive does no
/// work" are the other half.
const Map<String, String> _guardedWork = {
  'api/v1/admin/logs.dart': 'logsHandler(',
  'api/v1/admin/logs/export.dart': 'logsExportHandler(',
  'api/v1/backups/[name].dart': 'file.openRead()',
  'api/v1/import/candidates.dart': 'importCandidates(',
  'api/v1/nutrition/search.dart': 'foodSearchBody(',
};

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

/// A provider the declared probes must never reach: each is refused by a
/// guard or 404s on a missing recipe first. Reaching FoodData Central would
/// mean a probe got further than its declared posture allows.
///
/// It COUNTS the reaches as well as throwing, because "the guard refused it"
/// and "the guard refused it before spending anything" are different claims
/// and only the second is what the guard is for. The work-skipped group reads
/// [calls] as its witness, and deliberately drives one reach of its own as
/// the positive control — a counter that can only ever read zero would pin
/// nothing.
final class _UnreachableProvider implements NutritionProvider {
  /// How many times a request has actually reached FoodData Central.
  int calls = 0;

  @override
  Future<List<FdcCandidate>> search(String query) async {
    calls++;
    throw StateError('a route auth probe reached FDC search("$query")');
  }

  @override
  Future<FdcFood?> food(int fdcId) async {
    calls++;
    throw StateError('a route auth probe reached FDC food($fdcId)');
  }
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

    test('every GET declares whether it is side-effectful', () {
      // THE COVERAGE CHECK, as opposed to the drift lock below.
      //
      // `sideEffect` used to default to false, so the agreement test that
      // follows was satisfied TRIVIALLY by a route with neither the
      // declaration nor the guard — which is how `backups/[name].dart` (a
      // whole-database stream opened by `launchUrl`) and
      // `import/candidates.dart` (a synchronous ~1,200-dirent walk) sat
      // unguarded right next to the three routes finding S12 named, and how
      // the NEXT one would have landed too.
      //
      // Now the field is nullable with no default, and a GET may not leave
      // it null: adding a route forces a human to answer "does this GET
      // spend anything?" in writing, the same way `access` forces an answer
      // about credentials. It is the same fail-until-classified shape as the
      // file inventory above — a decision cannot be reached by omission.
      for (final route in _routes) {
        for (final probe in route.probes) {
          if (probe.method != 'GET') {
            continue;
          }
          expect(
            probe.sideEffect,
            isNotNull,
            reason:
                '${route.file} declares a GET without saying whether it is '
                'side-effectful. The session cookie is SameSite=Lax, so a '
                'cross-site top-level navigation carries it and any GET '
                'that '
                'SPENDS something (an outbound API call, an isolate spawn, a '
                'synchronous whole-file or whole-directory scan, a large '
                'stream off disk) is drivable from an attacker page — '
                'requireCsrf will not catch it, because it gates mutating '
                'METHODS only. Read the handler and set `sideEffect: true` '
                '(and add the Sec-Fetch-Site guard) or `sideEffect: false` '
                'in $_thisFile. There is deliberately no default.',
          );
        }
      }
    });

    test('side-effect postures and the cross-site guard agree', () {
      // The same both-directions tripwire, for the guard that covers GETs
      // requireCsrf does not: a handler that consults `Sec-Fetch-Site` is
      // refusing cross-site drives and must declare `sideEffect: true` so the
      // probe runs, and a route that declares it must actually have the
      // guard. Substring-level, like the checks above — the proof is the
      // enforcement probe. A route with NEITHER no longer passes this
      // trivially: the check above rejects an undeclared GET first.
      for (final route in _routes) {
        final declaresSideEffect = route.probes.any(
          (probe) => probe.refusesCrossSite,
        );
        final source = File('$_routesDir/${route.file}').readAsStringSync();
        final guardsCrossSite = source.contains('$_crossSiteGuard(');
        expect(
          guardsCrossSite,
          declaresSideEffect,
          reason: declaresSideEffect
              ? '${route.file} is declared to refuse a cross-site drive but '
                    'never calls $_crossSiteGuard: a cross-site top-level '
                    'navigation carries the SameSite=Lax session cookie, so '
                    'the side effect is reachable from an attacker page.'
              : '${route.file} guards against a cross-site drive but declares '
                    'no `sideEffect: true` method, so the probe never runs '
                    'against it. Declare it in $_thisFile.',
        );
      }
    });

    test('the cross-site guard sits ABOVE the work it protects', () {
      final guarded = <String>{};
      for (final route in _routes) {
        if (!route.probes.any((probe) => probe.refusesCrossSite)) {
          continue;
        }
        guarded.add(route.file);
        final work = _guardedWork[route.file];
        expect(
          work,
          isNotNull,
          reason:
              '${route.file} refuses a cross-site drive but names no '
              'expensive call in _guardedWork ($_thisFile). Read the handler '
              'and record the first thing the guard is there to stop paying '
              'for, so a guard moved below it fails here — a refusal thrown '
              'after the work has run costs exactly as much as no guard.',
        );
        final source = File('$_routesDir/${route.file}').readAsStringSync();
        final workAt = source.indexOf(work!);
        expect(
          workAt,
          isNonNegative,
          reason:
              '${route.file} no longer contains "$work", so the ordering '
              'check below proves nothing. Update _guardedWork in $_thisFile '
              'to name the call that is expensive now.',
        );
        final guardAt = source.indexOf('$_crossSiteGuard(');
        expect(
          guardAt,
          isNonNegative,
          reason: '${route.file} never calls $_crossSiteGuard.',
        );
        expect(
          guardAt,
          lessThan(workAt),
          reason:
              '${route.file} calls $_crossSiteGuard AFTER "$work". The '
              'refusal status is unchanged, which is why no probe in the '
              'enforcement group can see this — but the expensive work ran '
              'first, so a cross-site page still spends it.',
        );
      }
      expect(
        _guardedWork.keys.toSet().difference(guarded),
        isEmpty,
        reason:
            '_guardedWork in $_thisFile names routes that no longer declare a '
            'cross-site-guarded GET. Drop their entries.',
      );
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
    late String adminFullPat;
    late String memberFullPat;
    late _UnreachableProvider fdcProvider;

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
      fdcProvider = _UnreachableProvider();
      final pipeline = buildAppMiddleware(
        _dispatch,
        config: config,
        database: db,
        authRuntime: AuthRuntime(),
        nutritionProvider: fdcProvider,
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

      // The third cell: an admin's FULL-scope PAT — the strongest bearer
      // credential there is, and the only one that reaches the far side of
      // `requireAdmin` + `requireFullScope`. Nothing else in this suite gets
      // that far with a token, which is why the cross-site guard's PAT
      // exemption had no probe at all until the arm below.
      final adminPat = generatePat();
      db.createApiToken(
        userId: adminId,
        name: 'admin full pat',
        prefix: adminPat.prefix,
        tokenHash: hashToken(adminPat.token),
        scope: 'full',
      );
      adminFullPat = adminPat.token;

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

    /// Sends a request over a RAW socket and returns `(status, wire text)`.
    ///
    /// Only for header values `HttpClient` refuses to write. It rejects
    /// `Authorization: Bearer <U+000B>` with a FormatException — but Dart's
    /// `HttpServer` ACCEPTS it inbound (measured), and so does an attacker's
    /// socket, so a guard that treats it as a bearer credential is reachable
    /// in production and unreachable from `send`. The body is returned as raw
    /// wire text (chunk framing and all): these probes assert a status and
    /// look for the error code as a substring, which survives it.
    Future<(int, String)> sendRaw(
      String method,
      String path,
      Map<String, String> headers,
    ) async {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      try {
        final request = StringBuffer()
          ..write('$method $path HTTP/1.1\r\n')
          ..write('Host: 127.0.0.1:${server.port}\r\n')
          ..write('Connection: close\r\n');
        headers.forEach((name, value) => request.write('$name: $value\r\n'));
        request.write('\r\n');
        socket.write(request);
        await socket.flush();
        final wire = await utf8.decoder.bind(socket).join();
        return (int.parse(wire.split(' ')[1]), wire);
      } finally {
        socket.destroy();
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
          expect(
            noCsrf.status,
            HttpStatus.forbidden,
            reason:
                '$who must reject a cookie session that omits '
                '$csrfHeaderName: ${noCsrf.body}',
          );
          expect(
            noCsrf.code,
            'csrf',
            reason:
                '$who answered something other than the CSRF refusal. A '
                'handler that runs an existence lookup (or any other check) '
                'BEFORE requireCsrf lands here: the probe drives an id that '
                'does not exist, so a 404 means the guard order leaks '
                'existence to an unauthenticated cross-origin probe. Move '
                'requireCsrf above it — permission before existence.',
          );
        }
        // The SAME predicate, other direction: a bearer credential is never
        // ambient, so a mutation carrying one needs no anti-CSRF header —
        // which is what docs/API.md has always said. The guard keyed on
        // `user.via` instead, and a SESSION token presented as a bearer is
        // `via == 'session'`: exactly the token the login response hands
        // "non-browser clients", 403'd on all 27 mutating postures. Nothing
        // saw it, because no probe ever sent a session token as a bearer on a
        // mutation (the read PAT is refused earlier on most of these, and
        // change_password refuses every PAT).
        final asBearer = generateOpaqueToken();
        db.createSession(
          tokenHash: hashToken(asBearer),
          userId: probe.access == _Access.admin ? adminId : memberId,
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          remember: false,
        );
        final bearerMutation = await send(
          probe.method,
          route.path,
          headers: {'Authorization': 'Bearer $asBearer'},
        );
        expectReachedHandler(
          bearerMutation,
          '$label (session token as bearer, no $csrfHeaderName)',
          'refuses a mutation from the documented non-browser client. A '
              'curl/script caller sends no custom header and a browser cannot '
              'attach an Authorization header ambiently, so the anti-CSRF '
              'header must not be demanded of it',
        );
      }

      // 3b. A side-effectful GET driven the way a cross-site page drives one:
      //     a session cookie (SameSite=Lax rides a top-level navigation), no
      //     anti-CSRF header, and the Sec-Fetch-Site a browser stamps on a
      //     cross-site request — plus the bare case where neither header is
      //     present at all, which must fail CLOSED.
      if (probe.refusesCrossSite) {
        for (final extra in <Map<String, String>>[
          {},
          {'Sec-Fetch-Site': 'cross-site'},
          {'Sec-Fetch-Site': 'same-site'},
        ]) {
          final driven = await send(
            probe.method,
            route.path,
            headers: {...cookieFor(adminId), ...extra},
          );
          final who = '$label (admin cookie, $extra)';
          expect(
            driven.status,
            HttpStatus.forbidden,
            reason:
                '$who is a GET with real side effects, so a cross-site '
                'top-level navigation carrying the session cookie must be '
                'refused: ${driven.body}',
          );
          expect(driven.code, 'csrf', reason: who);
          // The refusal an operator debugging with curl actually reads must
          // describe the rule it hit. CsrfException used to say only that
          // "a mutating session request" needs X-Requested-With, which
          // names neither the method (this is a GET) nor the second proof
          // (a same-origin request is accepted here).
          expect(
            driven.body,
            contains('cross-site'),
            reason:
                '$who was refused with a message that does not mention the '
                'cross-site rule it enforces. On these GETs the header is '
                'not the only accepted proof and the method is not a '
                'mutation, so a message naming only X-Requested-With on a '
                'mutation sends the reader looking for the wrong bug.',
          );
        }
        // A MALFORMED Authorization must not exempt anything.
        //
        // HTTP strips OWS at the field edges, so a trailing SPACE never
        // survives the wire and "Bearer " alone is caught. U+000B is not OWS,
        // so it does survive — and it used to split the two readers apart:
        // the guard's own `startsWith('bearer ')` said "bearer request,
        // exempt" while the authenticator's `.trim()` emptied the token, fell
        // through to the ambient cookie, and served the request. MEASURED 200
        // against the production chain, where the same request with no
        // Authorization at all was 403. One shared parser now, so the guard
        // sees a plain cross-site cookie request and refuses it.
        //
        // Raw socket because HttpClient refuses to WRITE that value
        // (FormatException) while HttpServer accepts it inbound — the gap an
        // attacker's socket lives in, and the reason `send` cannot reach it.
        final vtab = String.fromCharCode(0x0b);
        final (malformedStatus, malformedWire) = await sendRaw(
          probe.method,
          route.path,
          {
            ...cookieFor(adminId),
            'Sec-Fetch-Site': 'cross-site',
            'Authorization': 'Bearer $vtab',
          },
        );
        final malformed = '$label (admin cookie, malformed bearer)';
        expect(
          malformedStatus,
          HttpStatus.forbidden,
          reason:
              '$malformed was EXEMPTED by an Authorization header that '
              'carries no usable token. The cookie then authenticated it, so '
              'the guard waved through exactly the request it exists to '
              'refuse: $malformedWire',
        );
        expect(
          malformedWire,
          contains('csrf'),
          reason: '$malformed was refused for some other reason',
        );
        // The two shapes the app itself produces must still get through: dio
        // sets the anti-CSRF header on every request, and the log export is
        // opened with launchUrl — a same-origin top-level navigation, which
        // cannot carry a custom header.
        for (final extra in <Map<String, String>>[
          {csrfHeaderName: csrfHeaderValue},
          {'Sec-Fetch-Site': 'same-origin'},
        ]) {
          final allowed = await send(
            probe.method,
            route.path,
            headers: {...cookieFor(adminId), ...extra},
          );
          expectReachedHandler(
            allowed,
            '$label (admin cookie, $extra)',
            'refuses a call the app really makes; the cross-site guard is '
                'too strict',
          );
        }
        // The OTHER half of the guard's contract: it is scoped to cookie
        // sessions (`user.via == 'session'`). A browser never attaches a PAT
        // ambiently, so a bearer request cannot be the cross-site drive this
        // guard exists to stop — and CLAUDE.md's "bearer elsewhere" clients
        // (curl, scripts, the CLI) send neither header. Drive the route with
        // an admin FULL-scope PAT wearing exactly the headers that refuse a
        // cookie session; it must still get through.
        //
        // Nothing pinned this before: the read PAT is refused at
        // requireFullScope and the member's full PAT at requireAdmin, so no
        // probe ever reached the guard carrying a token, and deleting
        // `user.via == 'session' &&` — which breaks every documented bearer
        // client — left the whole suite green.
        // Both bearer credentials, because the guard must key on whether the
        // browser attached the credential AMBIENTLY, not on its kind. A
        // SESSION token sent as `Authorization: Bearer` is `via == 'session'`
        // (auth.dart authenticates it through the same path as the cookie)
        // yet is not ambient at all — docs/API.md returns exactly that token
        // "for non-browser clients". A guard keyed on `via == 'session'`
        // alone 403s it, which is what corpus-gated tests in
        // p5_edit_http_test.dart caught after this suite went green.
        final sessionAsBearer = generateOpaqueToken();
        db.createSession(
          tokenHash: hashToken(sessionAsBearer),
          userId: adminId,
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          remember: false,
        );
        for (final token in <String>[adminFullPat, sessionAsBearer]) {
          final kind = token == adminFullPat
              ? 'admin full-scope PAT'
              : 'session token as bearer';
          for (final extra in <Map<String, String>>[
            {},
            {'Sec-Fetch-Site': 'cross-site'},
          ]) {
            final bearer = await send(
              probe.method,
              route.path,
              headers: {'Authorization': 'Bearer $token', ...extra},
            );
            expectReachedHandler(
              bearer,
              '$label ($kind, $extra)',
              'refuses a bearer credential the cross-site guard is supposed '
                  'to exempt — a browser cannot attach an Authorization '
                  'header ambiently, so this only breaks the documented '
                  'non-browser clients',
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

    // The declared probe above drives note.dart with a recipe id that does
    // not exist, which is exactly what proves the guard ORDER: requireCsrf
    // now runs before the existence lookup, so that probe gets 403 `csrf`
    // rather than the 404 it used to.
    //
    // This group is the other half — the same guard on a recipe that really
    // EXISTS, so a reordering cannot satisfy one arm by breaking the route
    // for every caller. It needs a real recipe and it used to be
    // corpus-gated, which meant CI — the one place a regression would ship
    // from — never ran it. The precondition is now established corpus-free
    // from the real legacy-v0 recipe committed at test/fixtures/legacy-v0/
    // (real data preserved at the P8 cutover, not a fabricated fixture), so
    // the guard is proven wherever this runs.
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

    // Every probe above asserts the REFUSAL STATUS — which a guard placed
    // BELOW the work satisfies exactly as well: the directory walk, the
    // whole-history parse, the outbound FDC call all run, and THEN the guard
    // throws 403. Measured: moving the guard under `importCandidates(config)`
    // left the entire enforcement group green at +56.
    //
    // These guards exist for the COST, so status alone cannot see a placement
    // regression. The inventory group's source-order tripwire is the static
    // half; this is the runtime half — after a refused drive, the work left
    // no trace. Each witness has a positive control in the same test, so
    // "no trace" can never pass because the witness itself died.
    //
    // `import/candidates` has no runtime witness here: its walk is a pure
    // read that leaves nothing behind to observe. The source-order pin covers
    // it, which is why that pin names every guarded route rather than only
    // the ones with a witness.
    group('a refused cross-site drive does no work', () {
      /// `auth` messages emitted while [action] runs.
      ///
      /// Deliberately does NOT open the `auth` logger: this suite boots the
      /// root logger at `LOG_LEVEL=ERROR`, so these expectations hold only
      /// because `auditLog` pins its own level.
      Future<List<String>> capture(Future<void> Function() action) async {
        final records = <LogRecord>[];
        final subscription = auditLog.onRecord.listen(records.add);
        try {
          await action();
          await Future<void>.delayed(Duration.zero);
        } finally {
          await subscription.cancel();
        }
        return [for (final record in records) record.message];
      }

      test('GET /api/v1/admin/logs reads nothing when refused', () async {
        // Its own admin: the read audit is throttled per actor, so a read by
        // the shared admin could suppress the control below and leave the
        // negative arm proving nothing.
        final readerId = db.createUser(
          username: 'matrix-log-reader',
          passwordHash: 'not-a-hash; no probe signs in with a password',
          role: 'admin',
        );
        final refused = await capture(() async {
          final reply = await send(
            'GET',
            '/api/v1/admin/logs',
            headers: {
              ...cookieFor(readerId),
              'Sec-Fetch-Site': 'cross-site',
            },
          );
          expect(reply.status, HttpStatus.forbidden, reason: reply.body);
          expect(reply.code, 'csrf');
        });
        expect(
          refused,
          isEmpty,
          reason:
              'a refused cross-site drive of the log viewer still reached '
              'the read: $refused. The guard has to sit ABOVE the work, not '
              'merely somewhere in the handler.',
        );
        final allowed = await capture(() async {
          final reply = await send(
            'GET',
            '/api/v1/admin/logs',
            headers: {
              ...cookieFor(readerId),
              'Sec-Fetch-Site': 'same-origin',
            },
          );
          expect(reply.status, HttpStatus.ok, reason: reply.body);
        });
        expect(
          allowed,
          contains(
            allOf(
              contains('Server log read'),
              contains('matrix-log-reader'),
              contains('id $readerId'),
            ),
          ),
          reason:
              'reading the server log records no actor, so the arm above is '
              'watching a witness that does not exist. The access line says '
              'only "GET /api/v1/admin/logs -> 200".',
        );
      });

      test(
        'GET /api/v1/admin/logs/export exports nothing when refused',
        () async {
          final refused = await capture(() async {
            final reply = await send(
              'GET',
              '/api/v1/admin/logs/export',
              headers: {...cookieFor(adminId), 'Sec-Fetch-Site': 'cross-site'},
            );
            expect(reply.status, HttpStatus.forbidden, reason: reply.body);
            expect(reply.code, 'csrf');
          });
          expect(
            refused,
            isEmpty,
            reason:
                'a refused cross-site drive of the export still ran the '
                'synchronous whole-history parse: $refused',
          );
          final allowed = await capture(() async {
            final reply = await send(
              'GET',
              '/api/v1/admin/logs/export',
              headers: {...cookieFor(adminId), 'Sec-Fetch-Site': 'same-origin'},
            );
            expect(reply.status, HttpStatus.ok, reason: reply.body);
          });
          expect(
            allowed,
            contains(
              allOf(contains('Server log exported'), contains('matrix-admin')),
            ),
            reason:
                'the whole persisted log left the box and the audit trail '
                'names nobody — so the arm above watches nothing.',
          );
        },
      );

      test('backups: create and download are recorded, and a refusal is '
          'neither', () async {
        final refusedCreate = await capture(() async {
          // No anti-CSRF header: the shape a cross-site page produces.
          final reply = await send(
            'POST',
            '/api/v1/backups',
            headers: cookieFor(adminId),
          );
          expect(reply.status, HttpStatus.forbidden, reason: reply.body);
          expect(reply.code, 'csrf');
        });
        expect(
          refusedCreate,
          isEmpty,
          reason: 'a refused create still made an archive: $refusedCreate',
        );

        String? name;
        final created = await capture(() async {
          final reply = await send(
            'POST',
            '/api/v1/backups',
            headers: {
              ...cookieFor(adminId),
              csrfHeaderName: csrfHeaderValue,
            },
          );
          expect(reply.status, HttpStatus.created, reason: reply.body);
          final backup =
              (jsonDecode(reply.body) as Map<String, dynamic>)['backup']
                  as Map<String, dynamic>;
          name = backup['name'] as String;
        });
        expect(
          created,
          contains(
            allOf(
              contains('Backup created: ${name!}'),
              contains('matrix-admin'),
            ),
          ),
          reason:
              'create -> download -> delete was only half-recorded: the two '
              'siblings name their actor and the archive, and the one that '
              'brings the archive into existence named nobody.',
        );

        // The download of an archive that REALLY exists, so the refusal is
        // measured against work that would otherwise happen. The declared
        // matrix only knows the missing-archive path; register the real one
        // so the test dispatcher reaches the same handler.
        final downloadPath = '/api/v1/backups/${name!}';
        _extraHandlers[downloadPath] = (context) =>
            backup_name.onRequest(context, name!);
        addTearDown(() => _extraHandlers.remove(downloadPath));
        final refusedDownload = await capture(() async {
          final reply = await send(
            'GET',
            downloadPath,
            headers: {
              ...cookieFor(adminId),
              'Sec-Fetch-Site': 'cross-site',
            },
          );
          expect(reply.status, HttpStatus.forbidden, reason: reply.body);
          expect(reply.code, 'csrf');
        });
        expect(
          refusedDownload,
          isEmpty,
          reason:
              'a refused cross-site drive still streamed the snapshot: '
              '$refusedDownload',
        );
      });

      test(
        'GET /api/v1/nutrition/search spends no FDC call when refused',
        () async {
          // A key has to be configured or the route 422s before the provider is
          // reachable at all — and then "FDC was never called" would hold with
          // the guard DELETED. Synthesized (an API key cannot come from a
          // recipe corpus) and never used: the provider throws first.
          db.setSetting(fdcApiKeySetting, 'matrix-placeholder-not-a-real-key');
          addTearDown(() => db.setSetting(fdcApiKeySetting, ''));
          final before = fdcProvider.calls;
          final refused = await send(
            'GET',
            '/api/v1/nutrition/search?q=butter',
            headers: {...cookieFor(adminId), 'Sec-Fetch-Site': 'cross-site'},
          );
          expect(refused.status, HttpStatus.forbidden, reason: refused.body);
          expect(refused.code, 'csrf');
          expect(
            fdcProvider.calls,
            before,
            reason:
                'the refused cross-site drive still spent the FDC request '
                'budget. A 403 thrown after the outbound call is what the '
                'guard exists to prevent, and the status alone cannot tell '
                'the two apart.',
          );
          // Positive control: the request the app makes DOES reach FDC, so
          // the counter above is watching something live. The provider throws
          // on purpose (nothing here may talk to FoodData Central), which
          // surfaces as a 500 — the call count is the assertion, not status.
          await send(
            'GET',
            '/api/v1/nutrition/search?q=butter',
            headers: {...cookieFor(adminId), csrfHeaderName: csrfHeaderValue},
          );
          expect(
            fdcProvider.calls,
            before + 1,
            reason:
                'an accepted search never reached the provider, so the arm '
                'above proves nothing about the guard.',
          );
        },
      );
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
