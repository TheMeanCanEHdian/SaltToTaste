import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:salt_shared/salt_shared.dart';

import 'package:salt_app/core/api/nutrition_repository.dart' show RecipeRef;

/// A favorite mark the caller changed: the recipe id or slug they acted on,
/// and where it landed. Carries whichever identifier the caller used, so a
/// listener must match on both (a grid holds ids; a detail page routes on
/// slugs).
typedef FavoriteChange = ({String idOrSlug, bool favorite});

/// What happened to a recipe through this repository.
enum RecipeChangeKind { created, updated, deleted }

/// A recipe this session created, edited, or deleted — announced on
/// [RecipeRepository.recipeChanges] so a page that is KEPT across the
/// navigation (a deep-linked detail page under the editor, the home grid
/// under a pushed recipe) reloads instead of showing what it had.
typedef RecipeChange = ({String idOrSlug, RecipeChangeKind kind});

/// Base URL of the SaltToTaste API.
///
/// Defaults to empty (same-origin) so a production web build served by the
/// API server Just Works. Development, where the Flutter dev server and the
/// API run on different ports, must override it:
/// `--dart-define=SALT_API_BASE=http://localhost:8080`.
const String apiBaseUrl = String.fromEnvironment('SALT_API_BASE');

/// Resolves a server-relative path (e.g. `/images/<src>/<file>.jpg`) to a URL
/// for use in `Image.network` — absolute in dev, origin-relative in
/// production (which the browser resolves against the page origin).
String apiUrl(String path) => '$apiBaseUrl$path';

/// An absolute URL for [path], suitable for `launchUrl` (which needs a scheme
/// even when [apiBaseUrl] is empty).
Uri absoluteApiUrl(String path) => Uri.base.resolve(apiUrl(path));

/// A user-presentable failure from the API layer.
///
/// The message is written for end users (never a raw server string or stack
/// trace); [requestId] (when present) lets the user quote a server log
/// reference in a bug report.
class RepositoryException implements Exception {
  const RepositoryException(this.message, {this.code, this.requestId});

  final String message;

  /// The server's stable error code (`validation`, `locked`, ...) when the
  /// failure carried an envelope; null for transport/shape failures.
  final String? code;
  final String? requestId;

  @override
  String toString() => message;
}

/// Runs [action], mapping every failure — Dio transport errors, envelope
/// errors, and decode/shape surprises alike — to a [RepositoryException].
/// The decoded `{error: {code, message, request_id}}` envelope of a failed
/// response body, or null when the body carries none (a transport failure or
/// a non-API response). ONE wire-format rule, consumed by both [apiGuard]
/// and AuthRepository's `_call` — the field reads were once written twice,
/// so an envelope change applied to one would silently miss the other's
/// error paths (review S6). Message POLICY (which codes surface their text
/// verbatim) deliberately stays at each caller.
({String? code, String? message, String? requestId})? decodeErrorEnvelope(
  Object? body,
) {
  if (body is! Map || body['error'] is! Map) {
    return null;
  }
  final error = (body['error'] as Map).cast<String, dynamic>();
  return (
    code: error['code'] is String ? error['code'] as String : null,
    message: error['message'] is String ? error['message'] as String : null,
    requestId: error['request_id'] is String
        ? error['request_id'] as String
        : null,
  );
}

/// The single error funnel shared by all repositories.
Future<T> apiGuard<T>(
  Future<T> Function() action, {
  String notFoundMessage = 'Not found.',
}) async {
  try {
    return await action();
  } on RepositoryException {
    rethrow;
  } on DioException catch (exception) {
    final envelope = decodeErrorEnvelope(exception.response?.data);
    if (envelope != null) {
      final message = switch (envelope.code) {
        ApiErrorCodes.notFound => notFoundMessage,
        ApiErrorCodes.validation when envelope.message != null =>
          envelope.message!,
        ApiErrorCodes.forbidden when envelope.message != null =>
          envelope.message!,
        ApiErrorCodes.conflict when envelope.message != null =>
          envelope.message!,
        ApiErrorCodes.lineMoved =>
          'This line moved since the list was loaded (the recipe was '
              'edited). The list is refreshed: check the line and try again.',
        _ => 'Something went wrong on the server. Please try again.',
      };
      throw RepositoryException(
        message,
        code: envelope.code,
        requestId: envelope.requestId,
      );
    }
    // No envelope: a transport failure, or a non-API response (proxy/HTML).
    final message = switch (exception.type) {
      DioExceptionType.connectionError || DioExceptionType.connectionTimeout =>
        "Couldn't reach the Salt to Taste server. Check that it's running, "
            'then retry.',
      DioExceptionType.receiveTimeout || DioExceptionType.sendTimeout =>
        'The server took too long to respond. Please try again.',
      _ => 'Something went wrong talking to the server. Please try again.',
    };
    throw RepositoryException(message);
  } catch (_) {
    throw const RepositoryException(
      'The server returned an unexpected response. Please try again.',
    );
  }
}

/// A full recipe document plus its serving context and the caller's
/// personal data (favorite flag, private note).
class RecipeDetail {
  const RecipeDetail({
    required this.recipe,
    required this.sourceSlug,
    this.heroImageUrl,
    this.favorite = false,
    this.note,
    this.baseHash,
  });

  final Recipe recipe;
  final String sourceSlug;

  /// The stored content hash this detail was loaded at. The editor echoes it
  /// on `PUT` as `base_hash` so a concurrent save is a 409 `conflict`, not a
  /// silent overwrite (review B11).
  final String? baseHash;

  /// Server-relative hero URL (`/images/...`) or null.
  final String? heroImageUrl;

  /// Whether the signed-in user has favorited this recipe.
  final bool favorite;

  /// The signed-in user's private note, or null.
  final String? note;

  /// Copy with changed personal data. Omitting [note] PRESERVES it (so a
  /// favorite toggle can't wipe the note from view); pass [clearNote] to
  /// actually remove it.
  RecipeDetail copyWith({
    bool? favorite,
    String? note,
    bool clearNote = false,
  }) => RecipeDetail(
    recipe: recipe,
    sourceSlug: sourceSlug,
    heroImageUrl: heroImageUrl,
    favorite: favorite ?? this.favorite,
    note: clearNote ? null : (note ?? this.note),
    baseHash: baseHash,
  );
}

/// One page of the cross-recipe nutrition-match review queue
/// (`GET /api/v1/admin/nutrition_review`) — the small client mirror of the
/// server body. Deliberately plain (no `salt_shared` DTO): the row's stored
/// match is only for display, and the fix panel's candidates are fetched
/// lazily from that recipe's `…/nutrition/matches` when a row is opened.
class NutritionReviewReport {
  const NutritionReviewReport({
    required this.total,
    required this.groups,
    required this.buckets,
    required this.items,
    required this.page,
    required this.limit,
    this.finishable = 0,
    this.openRecipes = 0,
  });

  factory NutritionReviewReport.fromJson(Map<String, dynamic> json) =>
      NutritionReviewReport(
        total: (json['total'] as num?)?.toInt() ?? 0,
        groups: (json['groups'] as num?)?.toInt() ?? 0,
        finishable: (json['finishable'] as num?)?.toInt() ?? 0,
        openRecipes: (json['open_recipes'] as num?)?.toInt() ?? 0,
        buckets: [
          if (json['buckets'] is List)
            for (final b in json['buckets'] as List<dynamic>)
              NutritionReviewBucket.fromJson(b as Map<String, dynamic>),
        ],
        items: [
          if (json['items'] is List)
            for (final i in json['items'] as List<dynamic>)
              NutritionReviewLine.fromJson(i as Map<String, dynamic>),
        ],
        page: (json['page'] as num?)?.toInt() ?? 1,
        limit: (json['limit'] as num?)?.toInt() ?? 0,
      );

  /// Whole-library count of flagged lines (stable across the bucket filter;
  /// excludes `skipped`).
  final int total;

  /// The same lines counted as distinct ingredient groups — what the grouped
  /// view lists and pages over. Reported in both modes.
  final int groups;

  /// Every triage bucket with its whole-library count, in display order.
  final List<NutritionReviewBucket> buckets;

  /// The grouped queue's payoff (whole-library, 0 in the line mode): the
  /// recipes one group decision completes, of the [openRecipes] that wait
  /// on at least one open line.
  final int finishable;
  final int openRecipes;

  /// The flagged lines on this page (narrowed by the `bucket` filter), in
  /// the requested `sort` order.
  final List<NutritionReviewLine> items;

  /// 1-based page index over [items].
  final int page;
  final int limit;
}

/// A triage bucket and how many flagged lines it holds library-wide.
class NutritionReviewBucket {
  const NutritionReviewBucket({
    required this.id,
    required this.label,
    required this.count,
    required this.groups,
  });

  factory NutritionReviewBucket.fromJson(Map<String, dynamic> json) =>
      NutritionReviewBucket(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        groups: (json['groups'] as num?)?.toInt() ?? 0,
      );

  /// Machine id (`no_match` | `no_grams` | `check` | `skipped`); also the
  /// `bucket` filter value.
  final String id;
  final String label;

  /// Flagged LINES in this bucket — what the chips and the tab badge count,
  /// in both views.
  final int count;

  /// The same lines as distinct ingredient groups.
  final int groups;
}

/// One flagged ingredient line, with the recipe it belongs to.
class NutritionReviewLine {
  const NutritionReviewLine({
    required this.recipe,
    required this.position,
    required this.raw,
    required this.bucket,
    this.section,
    this.match,
    this.itemKey,
    this.item,
    this.lines = 1,
    this.recipes = 1,
    this.decided = false,
    this.gramsMin,
    this.gramsMax,
    this.gramsMissing = 0,
    this.finishes = 0,
    this.finishesRecipes = const [],
    this.lastOpen = 0,
  });

  factory NutritionReviewLine.fromJson(Map<String, dynamic> json) {
    final rawMatch = json['match'];
    final grams = (json['grams'] as Map?)?.cast<String, dynamic>();
    return NutritionReviewLine(
      recipe: NutritionReviewRecipe.fromJson(
        (json['recipe'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      position: (json['position'] as num?)?.toInt() ?? 0,
      raw: json['raw'] as String? ?? '',
      bucket: json['bucket'] as String? ?? '',
      section: json['section'] as String?,
      match: rawMatch is Map<String, dynamic>
          ? NutritionReviewMatch.fromJson(rawMatch)
          : null,
      itemKey: json['item_key'] as String?,
      item: json['item'] as String?,
      lines: (json['lines'] as num?)?.toInt() ?? 1,
      recipes: (json['recipes'] as num?)?.toInt() ?? 1,
      decided: json['decided'] as bool? ?? false,
      gramsMin: (grams?['min'] as num?)?.toDouble(),
      gramsMax: (grams?['max'] as num?)?.toDouble(),
      gramsMissing: (grams?['missing'] as num?)?.toInt() ?? 0,
      finishes: (json['finishes'] as num?)?.toInt() ?? 0,
      finishesRecipes: [
        if (json['finishes_recipes'] is List)
          for (final r in json['finishes_recipes'] as List<dynamic>)
            (
              id: (r as Map<String, dynamic>)['id'] as String? ?? '',
              title: r['title'] as String? ?? '',
            ),
      ],
      lastOpen: (json['last_open'] as num?)?.toInt() ?? 0,
    );
  }

  /// The recipe — a section line's HOST (v44).
  final NutritionReviewRecipe recipe;

  /// The section the line belongs to (v44): its title, null on a recipe's
  /// own line. Its reads and writes carry `?section=`.
  final String? section;

  /// The recipe slot of the row: "{host title} · {section title}" on a
  /// section's line (v44), else the recipe's title.
  String get recipeLabel =>
      section == null ? recipe.title : '${recipe.title} · $section';

  /// The line's index within the recipe — the key for the fix write
  /// (`PUT …/nutrition/matches/{position}`).
  final int position;
  final String raw;

  /// Which triage bucket this line is in (`no_match` | `no_grams` | `check` |
  /// `skipped`).
  final String bucket;

  /// The stored match for the row display, or null for a no-match line.
  final NutritionReviewMatch? match;

  // ── Grouped mode (`group=item`) only. On a line item these carry their
  // single-line defaults, so both views render from the same row widget.

  /// The ingredient key this group is joined on (`ingredient_matches
  /// .item_key`), null on a line item.
  final String? itemKey;

  /// The example line's parsed ingredient item, verbatim — the row label,
  /// once `itemLabel()` has tidied it. Null when the line has none.
  final String? item;

  /// Members of this group inside the current filter, and the distinct
  /// recipes among them (1 / 1 for a line item).
  final int lines;
  final int recipes;

  /// `ingredient_decisions` already holds this key — the group was decided
  /// and is waiting for its members' next compute.
  final bool decided;

  /// The members' gram range and how many of them have no amount.
  final double? gramsMin;
  final double? gramsMax;
  final int gramsMissing;

  /// How many recipes one decision on this group completes (the server's
  /// `finishes`), 0 for a group that finishes none. On a line item, 1 when
  /// confirming it finishes its recipe: the recipe's last open line, with
  /// grams or a No grams line (whose confirm carries the amount); else 0.
  /// Read from the stored rows: an upper bound for a recipe edited since.
  final int finishes;

  /// The recipes [finishes] counts, by title.
  final List<({String id, String title})> finishesRecipes;

  /// Recipes whose open lines all sit in this group, grams or not: a No
  /// grams group holds their last open line, each needing its own amount.
  final int lastOpen;

  /// A stable id for selection (a recipe slug + line position is unique).
  /// In grouped mode this is the group's EXAMPLE line, which is what the fix
  /// pane opens on.
  /// A section's line carries its title: the host's own line at the same
  /// position is another line (v44).
  String get key =>
      '${recipe.slug}#$position${section == null ? '' : '#$section'}';
}

/// The recipe a flagged line belongs to (just enough to label it and open the
/// per-recipe fix flow).
class NutritionReviewRecipe {
  const NutritionReviewRecipe({
    required this.id,
    required this.slug,
    required this.title,
  });

  factory NutritionReviewRecipe.fromJson(Map<String, dynamic> json) =>
      NutritionReviewRecipe(
        id: json['id'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        title: json['title'] as String? ?? '',
      );

  final String id;
  final String slug;
  final String title;
}

/// The stored match on a flagged line, for the queue row (a subset of the
/// per-recipe match — no candidates or gram basis, which the fix panel fetches).
class NutritionReviewMatch {
  const NutritionReviewMatch({
    required this.fdcId,
    required this.confidence,
    required this.status,
    this.description,
    this.dataType,
    this.grams,
    this.gramSource,
    this.hold,
    this.child,
  });

  factory NutritionReviewMatch.fromJson(Map<String, dynamic> json) =>
      NutritionReviewMatch(
        fdcId: (json['fdc_id'] as num?)?.toInt() ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? 'unmatched',
        description: json['description'] as String?,
        dataType: json['data_type'] as String?,
        grams: (json['grams'] as num?)?.toDouble(),
        gramSource: json['gram_source'] as String?,
        hold: json['hold'] as String?,
        child: json['child'] is Map<String, dynamic>
            ? RecipeRef.fromJson(json['child'] as Map<String, dynamic>)
            : null,
      );

  final int fdcId;
  final double confidence;
  final String status;
  final String? description;
  final String? dataType;
  final double? grams;
  final String? gramSource;

  /// Why the engine holds the line (`discarded_medium`, `in_shell`, …):
  /// the queue row says a line hold is decided one line at a time.
  final String? hold;

  /// A reference line's SLIM child (v41): state, reason, name, slug, title,
  /// share text, default, why — never candidates.
  final RecipeRef? child;
}

/// Read access to the recipe API.
class RecipeRepository {
  RecipeRepository({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: apiBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  final Dio _dio;

  final StreamController<FavoriteChange> _favoriteChanges =
      StreamController<FavoriteChange>.broadcast();
  final StreamController<RecipeChange> _recipeChanges =
      StreamController<RecipeChange>.broadcast();

  /// Recipes the caller created, edited, or deleted this session, announced
  /// once the server has accepted each change. See [RecipeChange].
  Stream<RecipeChange> get recipeChanges => _recipeChanges.stream;

  /// Favourite marks the caller has changed this session, announced as they
  /// are accepted by the server.
  ///
  /// [setFavorite] is the one place a favorite can change, which makes it the
  /// one place worth listening to: a grid left alive under a pushed detail
  /// page reconciles itself from this instead of reloading (which would lose
  /// its scroll position and paging) or going stale (which it did).
  Stream<FavoriteChange> get favoriteChanges => _favoriteChanges.stream;

  /// Releases [favoriteChanges]. The repository is an app-lifetime singleton,
  /// so this only matters to tests.
  Future<void> dispose() =>
      Future.wait([_favoriteChanges.close(), _recipeChanges.close()]);

  /// One page of recipe cards plus the total count; [query] runs the
  /// search DSL server-side, [favoritesOnly] narrows to the caller's
  /// favorites.
  Future<({List<RecipeCard> items, int total})> listRecipes({
    required int page,
    int limit = 48,
    String? query,
    bool favoritesOnly = false,
  }) {
    return _request('recipes', () async {
      final data = await _getMap(
        '/api/v1/recipes',
        query: {
          'page': '$page',
          'limit': '$limit',
          if (query != null && query.trim().isNotEmpty) 'q': query,
          if (favoritesOnly) 'favorites': 'true',
        },
      );
      final items = [
        for (final item in data['items']! as List<dynamic>)
          RecipeCardMapper.fromMap(item as Map<String, dynamic>),
      ];
      return (items: items, total: (data['total']! as num).toInt());
    });
  }

  /// The admin recipe data-quality report (`GET /api/v1/admin/recipe_review`).
  /// [issue] narrows to one category; [page]/[limit] page the flagged list.
  Future<RecipeReviewReport> getRecipeReview({
    required int page,
    int limit = 50,
    String? issue,
  }) {
    return _request('recipe-review', () async {
      final data = await _getMap(
        '/api/v1/admin/recipe_review',
        query: {
          'page': '$page',
          'limit': '$limit',
          if (issue != null && issue.isNotEmpty) 'issue': issue,
        },
      );
      RecipeReviewReportMapper.ensureInitialized();
      return RecipeReviewReportMapper.fromMap(data);
    });
  }

  /// The cross-recipe nutrition-match review queue
  /// (`GET /api/v1/admin/nutrition_review`). [bucket] narrows the item list
  /// (and its pagination) to one triage bucket; [page]/[limit] page it. The
  /// bucket counts and [NutritionReviewReport.total] stay whole-library.
  /// [sort] orders the groups, or the lines when not [grouped].
  Future<NutritionReviewReport> getNutritionReview({
    required int page,
    int limit = 50,
    String? bucket,
    bool grouped = false,
    String? sort,
  }) {
    return _request('nutrition-review', () async {
      final data = await _getMap(
        '/api/v1/admin/nutrition_review',
        query: {
          'page': '$page',
          'limit': '$limit',
          if (bucket != null && bucket.isNotEmpty) 'bucket': bucket,
          // Grouped mode pages over ingredient groups, not lines.
          if (grouped) 'group': 'item',
          // The order (`finishes` | `worst`), of groups or of lines; the
          // server defaults to finishes.
          if (sort != null) 'sort': sort,
        },
      );
      return NutritionReviewReport.fromJson(data);
    });
  }

  Future<int>? _reviewCountFuture;

  /// The number of recipes needing review, memoized for the session so the
  /// nav-bar badge costs one fetch. A failure resets the memo so it can retry.
  Future<int> reviewCount() {
    return _reviewCountFuture ??= getRecipeReview(page: 1, limit: 1)
        .then((report) => report.total)
        .catchError((Object _) {
          _reviewCountFuture = null;
          return 0;
        });
  }

  /// Drops the memoized [reviewCount] so the next read refetches (e.g. after a
  /// recipe edit that could change the tally).
  void invalidateReviewCount() => _reviewCountFuture = null;

  /// The full recipe matched by [idOrSlug].
  Future<RecipeDetail> getRecipe(String idOrSlug) {
    return _request('recipe', () async {
      final data = await _getMap('/api/v1/recipes/${_seg(idOrSlug)}');
      return _detailFrom(data);
    });
  }

  /// The download URL for a recipe's canonical YAML export.
  Uri yamlUrl(String idOrSlug) =>
      absoluteApiUrl('/api/v1/recipes/${_seg(idOrSlug)}/yaml');

  /// The recipe's canonical YAML export as text — for the admin View-YAML
  /// modal (the download uses [yamlUrl] directly).
  Future<String> recipeYamlText(String idOrSlug) {
    return apiGuard(() async {
      final response = await _dio.get<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}/yaml',
        options: Options(responseType: ResponseType.plain),
      );
      return response.data as String? ?? '';
    }, notFoundMessage: 'Recipe not found.');
  }

  // ------------------------------------------------------------------
  // Editing (admin + full scope on the server side).
  // ------------------------------------------------------------------

  /// Creates a recipe from the editor's field map and returns the stored
  /// detail (the server generates id and slug).
  Future<RecipeDetail> createRecipe(Map<String, Object?> fields) {
    return _request('create', () async {
      final response = await _dio.post<dynamic>(
        '/api/v1/recipes',
        data: {'recipe': fields},
      );
      final detail = _detailFrom(_asMap(response.data));
      _recipeChanges.add((
        idOrSlug: detail.recipe.slug,
        kind: RecipeChangeKind.created,
      ));
      return detail;
    });
  }

  /// Applies the editor's field map to an existing recipe (merge semantics:
  /// only the keys present are changed).
  Future<RecipeDetail> updateRecipe(
    String idOrSlug,
    Map<String, Object?> fields, {
    String? baseHash,
  }) {
    return _request('update', () async {
      final response = await _dio.put<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}',
        data: {
          'recipe': fields,
          // Concurrency precondition: mismatch is a 409 (review B11).
          if (baseHash != null) 'base_hash': baseHash,
        },
      );
      final detail = _detailFrom(_asMap(response.data));
      _recipeChanges.add((
        idOrSlug: detail.recipe.slug,
        kind: RecipeChangeKind.updated,
      ));
      return detail;
    });
  }

  /// Deletes the recipe (the server takes a backup first).
  Future<void> deleteRecipe(String idOrSlug) {
    return _request('delete', () async {
      await _dio.delete<dynamic>('/api/v1/recipes/${_seg(idOrSlug)}');
      _recipeChanges.add((idOrSlug: idOrSlug, kind: RecipeChangeKind.deleted));
    });
  }

  /// Uploads photo [bytes] as the recipe's hero image or a gallery entry.
  Future<RecipeDetail> uploadImage(
    String idOrSlug,
    Uint8List bytes, {
    String role = 'hero',
  }) {
    return _request('upload', () async {
      final response = await _dio.post<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}/images',
        queryParameters: {'role': role},
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {Headers.contentLengthHeader: bytes.length},
          contentType: 'application/octet-stream',
          // A 25 MB photo on a slow uplink outlives the default timeouts.
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      return _detailFrom(_asMap(response.data));
    });
  }

  /// Asks the server to download a photo from [url] (SSRF-guarded there).
  Future<RecipeDetail> imageFromUrl(
    String idOrSlug,
    String url, {
    String role = 'hero',
  }) {
    return _request('image-from-url', () async {
      final response = await _dio.post<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}/images/from_url',
        data: {'url': url, 'role': role},
        // The server-side download has its own ~30s budget.
        options: Options(receiveTimeout: const Duration(minutes: 1)),
      );
      return _detailFrom(_asMap(response.data));
    });
  }

  /// Stores photo [bytes] in the library and returns the `images/<file>`
  /// reference WITHOUT attaching it to the recipe — for a technique step image,
  /// which the recipe's own save then persists.
  Future<String> storeImage(String idOrSlug, Uint8List bytes) {
    return _request('store-image', () async {
      final response = await _dio.post<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}/images/store',
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {Headers.contentLengthHeader: bytes.length},
          contentType: 'application/octet-stream',
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      return _asMap(response.data)['reference'] as String;
    });
  }

  /// Downloads a photo from [url] (SSRF-guarded server-side) into the library
  /// and returns its reference without attaching it.
  Future<String> storeImageFromUrl(String idOrSlug, String url) {
    return _request('store-image-from-url', () async {
      final response = await _dio.post<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}/images/store_from_url',
        data: {'url': url},
        options: Options(receiveTimeout: const Duration(minutes: 1)),
      );
      return _asMap(response.data)['reference'] as String;
    });
  }

  // ------------------------------------------------------------------
  // Personal data (any role; read-scope PATs allowed server-side).
  // ------------------------------------------------------------------

  /// Marks or unmarks the recipe as one of the caller's favorites.
  ///
  /// Announces the change on [favoriteChanges] once the server has accepted
  /// it, so an open grid can reconcile itself.
  Future<void> setFavorite(String idOrSlug, {required bool favorite}) {
    return _request('favorite', () async {
      final path = '/api/v1/recipes/${_seg(idOrSlug)}/favorite';
      if (favorite) {
        await _dio.put<dynamic>(path);
      } else {
        await _dio.delete<dynamic>(path);
      }
      _favoriteChanges.add((idOrSlug: idOrSlug, favorite: favorite));
    });
  }

  /// Saves the caller's private note (empty [note] deletes it). Returns the
  /// stored note, or null when cleared.
  Future<String?> setNote(String idOrSlug, String note) {
    return _request('note', () async {
      final response = await _dio.put<dynamic>(
        '/api/v1/recipes/${_seg(idOrSlug)}/note',
        data: {'note': note},
      );
      return _asMap(response.data)['note'] as String?;
    });
  }

  RecipeDetail _detailFrom(Map<String, dynamic> data) => RecipeDetail(
    recipe: RecipeMapper.fromMap(data['recipe']! as Map<String, dynamic>),
    sourceSlug: data['source_slug']! as String,
    heroImageUrl: data['hero_image_url'] as String?,
    favorite: data['favorite'] == true,
    note: data['note'] as String?,
    baseHash: data['base_hash'] as String?,
  );

  static String _seg(String idOrSlug) => Uri.encodeComponent(idOrSlug);

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is! Map<String, dynamic>) {
      throw const RepositoryException(
        'The server returned an unexpected response. Please try again.',
      );
    }
    return data;
  }

  /// [apiGuard] with this repository's not-found wording.
  Future<T> _request<T>(String what, Future<T> Function() action) =>
      apiGuard(action, notFoundMessage: 'Recipe not found.');

  Future<Map<String, dynamic>> _getMap(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _dio.get<dynamic>(path, queryParameters: query);
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const RepositoryException(
        'The server returned an unexpected response. Please try again.',
      );
    }
    return data;
  }
}
