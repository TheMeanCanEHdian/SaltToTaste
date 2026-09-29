import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/import_repository.dart';
import 'package:salt_app/core/api/library_repository.dart';
import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/api/tags_repository.dart';
import 'package:salt_app/features/nutrition/match_fix_panel.dart';

import 'support/contract_goldens.dart';

/// Parses the committed contract goldens — real `/api/v1` bodies captured
/// from the real server routes — with the real repositories and models.
///
/// This half of the pin needs NO corpus: it reads only the committed files.
/// The generating half (`apps/server/test/contract_golden_test.dart`) now
/// regenerates every corpus-free body in CI too, so a server-side key rename
/// fails there while the app-side cast that would swallow it fails here.
void main() {
  group('auth contract', () {
    test('/auth/me carries must_change_password through as TRUE', () async {
      final raw = golden('auth_me_must_change');
      final user = raw['user']! as Map<String, dynamic>;
      // The claim the whole fixture exists for: this key is what forces the
      // password change, so a server-side rename must be caught here rather
      // than in production (review T5). The parse now fails closed too —
      // pinned by the next test.
      expect(
        user['must_change_password'],
        isTrue,
        reason: 'the golden itself must describe a forced-change account',
      );

      final parsed = await AuthRepository(goldenDio(raw)).me();
      expect(parsed, isNotNull);
      expect(parsed!.mustChangePassword, isTrue);
      expect(parsed.mustChangePassword, user['must_change_password']);
      expect(parsed.id, user['id']);
      expect(parsed.username, user['username']);
      expect(parsed.role, user['role']);
      expect(parsed.isAdmin, isFalse, reason: "the golden's role is member");
    });

    test('a renamed must_change_password key fails CLOSED', () async {
      // The golden body minus the one key a server-side rename would move —
      // the only way to exercise the failure mode is to mutate the real
      // body. The safe answer is "still required", never "signed in".
      final raw = golden('auth_me_must_change');
      final user = Map<String, dynamic>.from(raw['user']! as Map);
      expect(user.remove('must_change_password'), isTrue);
      expect(AuthUserInfo.fromJson(user).mustChangePassword, isTrue);

      final parsed = await AuthRepository(goldenDio({'user': user})).me();
      expect(
        parsed!.mustChangePassword,
        isTrue,
        reason: 'a dropped key must not retire the forced change',
      );

      // /auth/login builds the same object from the same key.
      final loginRaw = Map<String, dynamic>.from(golden('auth_login_admin'));
      final loginUser = Map<String, dynamic>.from(loginRaw['user']! as Map)
        ..remove('must_change_password');
      loginRaw['user'] = loginUser;
      final loggedIn = await AuthRepository(goldenDio(loginRaw)).login(
        username: '${loginUser['username']}',
        password: 'unused-by-the-adapter',
        remember: false,
      );
      expect(loggedIn.mustChangePassword, isTrue);
    });

    test('a non-bool must_change_password is an error, not a sign-in', () {
      final user = Map<String, dynamic>.from(
        golden('auth_me_must_change')['user']! as Map,
      )..['must_change_password'] = 'true';
      return expectLater(
        AuthRepository(goldenDio({'user': user})).me(),
        throwsA(isA<RepositoryException>()),
        reason: 'an unparseable flag is surfaced, never guessed at',
      );
    });

    test('UserAccount reads the same key the same way', () {
      // The admin Users tab parses the same flag off its own row shape; the
      // two parses must not disagree about a missing key. Built from the
      // captured user object plus the `disabled` the users list adds.
      final row = Map<String, dynamic>.from(
        golden('auth_me_admin')['user']! as Map,
      )..['disabled'] = false;
      expect(UserAccount.fromJson(row).mustChangePassword, isFalse);
      row.remove('must_change_password');
      expect(
        UserAccount.fromJson(row).mustChangePassword,
        isTrue,
        reason: 'absent means "must change" on both parses',
      );
    });

    test(
      '/auth/setup and /auth/recover are the deliberate exemption',
      () async {
        // Those two bodies never carry the flag (auth_handlers.dart:162,295)
        // and their caller just chose the password, so failing closed there
        // would strand a fresh admin on a change screen the server rejects.
        final body = Map<String, dynamic>.from(golden('auth_login_admin'));
        final user = Map<String, dynamic>.from(body['user']! as Map)
          ..remove('must_change_password');
        body['user'] = user;
        final repository = AuthRepository(goldenDio(body));
        await expectLater(
          repository.setup(
            setupCode: 'unused-by-the-adapter',
            username: '${user['username']}',
            password: 'unused-by-the-adapter',
          ),
          completion(
            isA<AuthUserInfo>().having(
              (info) => info.mustChangePassword,
              'mustChangePassword',
              isFalse,
            ),
          ),
        );
        await expectLater(
          repository.recover(
            code: 'unused-by-the-adapter',
            username: '${user['username']}',
            newPassword: 'unused-by-the-adapter',
          ),
          completion(
            isA<AuthUserInfo>().having(
              (info) => info.mustChangePassword,
              'mustChangePassword',
              isFalse,
            ),
          ),
        );
      },
    );

    test('/auth/me for an ordinary admin', () async {
      final raw = golden('auth_me_admin');
      final user = raw['user']! as Map<String, dynamic>;
      final parsed = await AuthRepository(goldenDio(raw)).me();
      expect(parsed!.mustChangePassword, isFalse);
      expect(parsed.mustChangePassword, user['must_change_password']);
      expect(parsed.isAdmin, isTrue);
      expect(parsed.role, user['role']);
    });

    test('/auth/login reports the forced change too', () async {
      final raw = golden('auth_login_must_change');
      final user = raw['user']! as Map<String, dynamic>;
      expect(user['must_change_password'], isTrue);
      final parsed = await AuthRepository(goldenDio(raw)).login(
        username: '${user['username']}',
        password: 'unused-by-the-adapter',
        remember: false,
      );
      expect(parsed.mustChangePassword, isTrue);
      expect(parsed.id, user['id']);
      expect(parsed.role, user['role']);
    });

    test('/auth/login for an admin, and /auth/change_password', () async {
      final loginRaw = golden('auth_login_admin');
      final parsed = await AuthRepository(goldenDio(loginRaw)).login(
        username: 'admin',
        password: 'unused-by-the-adapter',
        remember: true,
      );
      expect(parsed.mustChangePassword, isFalse);
      expect(parsed.isAdmin, isTrue);

      final changeRaw = golden('auth_change_password');
      expect(changeRaw['ok'], isTrue, reason: 'the success envelope');
      // The app ignores the body but must not choke on it.
      await expectLater(
        AuthRepository(
          goldenDio(changeRaw),
        ).changePassword(currentPassword: 'old', newPassword: 'new'),
        completes,
      );
    });
  });

  group('tags contract', () {
    test('an unstyled tag parses with a null style', () async {
      final raw = golden('tags_unstyled');
      final items = raw['items']! as List<dynamic>;
      final tags = await TagsRepository(goldenDio(raw)).listTags();
      expect(tags, hasLength(items.length));
      for (final (index, tag) in tags.indexed) {
        final row = items[index]! as Map<String, dynamic>;
        expect(tag.name, row['name']);
        expect(tag.count, row['count']);
        expect(tag.style.isEmpty, isTrue);
      }
    });

    test('a styled tag parses icon and both colors', () async {
      final raw = golden('tags_styled');
      final rows = (raw['items']! as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final row = rows.firstWhere((entry) => entry['icon'] != null);
      final tags = await TagsRepository(goldenDio(raw)).listTags();
      final tag = tags.firstWhere((entry) => entry.name == row['name']);
      expect(tag.style.isEmpty, isFalse);
      expect(tag.style.icon, row['icon']);
      expect(tag.style.color, row['color']);
      // bg_color -> bgColor is exactly the kind of rename this pins.
      expect(tag.style.bgColor, row['bg_color']);
      expect(tag.style.bgColor, isNotNull);
      // The same body still carries unstyled rows, so both branches of the
      // style parse run against one real response.
      final plain = rows.firstWhere((entry) => entry['icon'] == null);
      expect(
        tags.firstWhere((entry) => entry.name == plain['name']).style.isEmpty,
        isTrue,
      );
    });
  });

  group('recipe contract', () {
    test('a page of cards parses every card field', () async {
      final raw = golden('recipes_page');
      final items = raw['items']! as List<dynamic>;
      final page = await RecipeRepository(
        dio: goldenDio(raw),
      ).listRecipes(page: 1);
      expect(page.total, raw['total']);
      expect(page.items, hasLength(items.length));
      expect(page.items, isNotEmpty);
      for (final (index, card) in page.items.indexed) {
        final row = items[index]! as Map<String, dynamic>;
        expect(card.id, row['id']);
        expect(card.slug, row['slug']);
        expect(card.title, row['title']);
        expect(card.category, row['category']);
        expect(card.heroImage, row['hero_image']);
        expect(card.tags, row['tags']);
        expect(card.servingsText, row['servings_text']);
        expect(card.totalMinutes, row['total_minutes']);
        expect(card.caloriesPerServing, row['calories_per_serving']);
        expect(card.favorite, row['favorite']);
        expect(card.variationCount, row['variation_count']);
      }
    });

    test('a search page carries the favorite flag as true', () async {
      // Captured from the ranked `?q=` path after the recipe was favorited,
      // so the card's `favorite` is pinned in BOTH states across the two
      // goldens instead of only its default.
      final raw = golden('recipes_search');
      final row =
          (raw['items']! as List<dynamic>).first as Map<String, dynamic>;
      expect(
        row['favorite'],
        isTrue,
        reason: 'the search golden is captured after the favorite is set',
      );
      expect(
        (golden('recipes_page')['items']! as List<dynamic>).first
            as Map<String, dynamic>,
        containsPair('favorite', false),
      );
      final page = await RecipeRepository(
        dio: goldenDio(raw),
      ).listRecipes(page: 1, query: 'asparagus');
      expect(page.items.single.favorite, isTrue);
      expect(page.items.single.slug, row['slug']);
    });

    test('the detail body parses the recipe and the personal data', () async {
      final raw = golden('recipe_detail');
      final recipe = raw['recipe']! as Map<String, dynamic>;
      final detail = await RecipeRepository(
        dio: goldenDio(raw),
      ).getRecipe('${recipe['slug']}');
      expect(detail.sourceSlug, raw['source_slug']);
      expect(detail.heroImageUrl, raw['hero_image_url']);
      expect(detail.baseHash, raw['base_hash']);
      expect(detail.baseHash, isNotNull, reason: 'the editor echoes this');
      expect(detail.favorite, raw['favorite']);
      expect(detail.note, raw['note']);
      expect(detail.note, isNotNull, reason: 'the golden carries a note');
      expect(detail.recipe.id, recipe['id']);
      expect(detail.recipe.slug, recipe['slug']);
      expect(detail.recipe.title, recipe['title']);
      expect(detail.recipe.tags, recipe['tags']);
      expect(
        detail.recipe.ingredients,
        hasLength((recipe['ingredients']! as List).length),
      );
      expect(detail.recipe.steps, hasLength((recipe['steps']! as List).length));
      expect(detail.recipe.ingredients, isNotEmpty);
      expect(detail.recipe.steps, isNotEmpty);
    });
  });

  group('library contract', () {
    test('a scan report parses every branch the server can report', () async {
      final raw = golden('library_last_scan');
      final scan = raw['last_scan']! as Map<String, dynamic>;
      final report = await LibraryRepository(goldenDio(raw)).lastScan();
      expect(report, isNotNull);
      expect(report!.startedAt, scan['started_at']);
      expect(report.filesSeen, scan['files_seen']);
      expect(report.elapsedMs, scan['elapsed_ms']);
      expect(report.updatedFromDisk, scan['updated_from_disk']);
      expect(report.added, scan['added']);
      expect(report.reExported, scan['re_exported']);
      expect(report.conflictFiles, scan['conflict_files']);

      final skipped = scan['skipped']! as List<dynamic>;
      expect(report.skipped, hasLength(skipped.length));
      for (final (index, entry) in report.skipped.indexed) {
        final row = skipped[index]! as Map<String, dynamic>;
        expect(entry.file, row['file']);
        expect(entry.reason, row['reason']);
        expect(entry.file, isNotEmpty);
        expect(entry.reason, isNotEmpty);
      }
      // The golden deliberately exercises all five lists, so a report that
      // parsed them away would read as "clean".
      expect(report.clean, isFalse);
    });
  });

  group('import contract', () {
    test('candidates parse the import dir and each source folder', () async {
      final raw = golden('import_candidates');
      final items = raw['items']! as List<dynamic>;
      final parsed = await ImportRepository(goldenDio(raw)).candidates();
      expect(parsed.importDir, raw['import_dir']);
      expect(parsed.items, hasLength(items.length));
      for (final (index, candidate) in parsed.items.indexed) {
        final row = items[index]! as Map<String, dynamic>;
        expect(candidate.path, row['path']);
        expect(candidate.kind, row['kind']);
        expect(candidate.fileCount, row['file_count']);
      }
    });

    test('a finished import job parses its counters and log', () async {
      final raw = golden('import_job');
      final parsed = await ImportRepository(
        goldenDio(raw),
      ).job((raw['id']! as num).toInt());
      expect(parsed.id, raw['id']);
      expect(parsed.status, raw['status']);
      expect(parsed.running, isFalse);
      expect(parsed.legacy, raw['legacy']);
      expect(parsed.sourcePath, raw['source_path']);
      expect(parsed.total, raw['total']);
      expect(parsed.done, raw['done']);
      expect(parsed.imported, raw['imported']);
      expect(parsed.updated, raw['updated']);
      expect(parsed.skipped, raw['skipped']);
      expect(parsed.failed, raw['failed']);
      expect(parsed.log, hasLength((raw['log']! as List).length));
      expect(parsed.log, isNotEmpty, reason: 'the golden records a failure');
    });
  });

  group('nutrition contract', () {
    test('the label body parses totals and every nutrient row', () async {
      final raw = golden('nutrition');
      final perServing = raw['per_serving']! as Map<String, dynamic>;
      final parsed = await NutritionRepository(
        goldenDio(raw),
      ).nutrition('rich-chocolate-bundt-cake');
      expect(parsed.status, raw['status']);
      expect(parsed.exists, isTrue);
      expect(parsed.servingBasis, raw['serving_basis']);
      expect(raw['basis_kind'], 'per_serving');
      expect(parsed.basisKind, raw['basis_kind']);
      expect(parsed.perBatch, isFalse);
      expect(parsed.caloriesPerServing, raw['calories_per_serving']);
      expect(parsed.totalGrams, raw['total_grams']);
      expect(parsed.matchedCount, raw['matched_count']);
      expect(parsed.totalCount, raw['total_count']);
      expect(parsed.lowConfidence, raw['low_confidence']);
      expect(parsed.computedAt, raw['computed_at']);
      expect(parsed.computingJobId, isNull, reason: 'no compute in flight');

      expect(parsed.perServing.keys, perServing.keys);
      for (final entry in perServing.entries) {
        final row = entry.value! as Map<String, dynamic>;
        final value = parsed.perServing[entry.key]!;
        expect(value.label, row['label']);
        expect(value.amount, row['amount']);
        expect(value.unit, row['unit']);
        expect(value.dvPercent, row['dv_percent']);
      }
      // This real body is honestly partial — fewer lines contribute
      // nutrients than the recipe has — so the amber badge must be lit.
      expect(
        raw['matched_count']! as num,
        lessThan(raw['total_count']! as num),
        reason: 'the golden is a partially-matched recipe',
      );
      expect(parsed.needsReview, isTrue);
    });

    test(
      'the match list parses matches, grams basis, and candidates',
      () async {
        final raw = golden('nutrition_matches');
        final items = raw['items']! as List<dynamic>;
        final parsed = await NutritionRepository(
          goldenDio(raw),
        ).matches('rich-chocolate-bundt-cake');
        expect(parsed, hasLength(items.length));
        expect(parsed, isNotEmpty);

        var withGramBasis = 0;
        var withoutGrams = 0;
        for (final (index, line) in parsed.indexed) {
          final row = items[index]! as Map<String, dynamic>;
          expect(line.position, row['position']);
          expect(line.raw, row['raw']);
          // The apply-to-all reach, in both units.
          expect(line.others, row['others']);
          expect(line.othersLines, row['others_lines']);

          final candidates = (row['candidates'] as List<dynamic>?) ?? const [];
          expect(line.candidates, hasLength(candidates.length));
          for (final (slot, candidate) in line.candidates.indexed) {
            final entry = candidates[slot]! as Map<String, dynamic>;
            expect(candidate.fdcId, entry['fdc_id']);
            expect(candidate.description, entry['description']);
            expect(candidate.dataType, entry['data_type']);
            expect(candidate.confidence, entry['confidence']);
          }

          // Every line of a computed recipe carries a match; the null-match
          // branch has its own golden below.
          final match = row['match']! as Map<String, dynamic>;
          expect(line.fdcId, match['fdc_id']);
          expect(line.description, match['description']);
          expect(line.dataType, match['data_type']);
          expect(line.confidence, match['confidence']);
          expect(line.grams, match['grams']);
          expect(line.gramSource, match['gram_source']);
          expect(line.gramBasis, match['gram_basis']);
          expect(line.status, match['status']);
          if (match['gram_basis'] != null) {
            withGramBasis += 1;
          }
          if (match['grams'] == null) {
            withoutGrams += 1;
          }
        }
        // The golden is a real, honestly-partial recipe, so both sides of the
        // nullable fields are actually exercised above rather than assumed.
        expect(withGramBasis, greaterThan(0));
        expect(
          withoutGrams,
          greaterThan(0),
          reason: 'the un-resolvable lines keep the null-grams branch alive',
        );
        expect(withGramBasis, lessThan(parsed.length));
      },
    );

    test('the matcher-v8 bases and holds parse and read in words', () async {
      // Real corpus lines computed over the recorded FDC answers: the
      // citrus-juice and egg-sum second foods, a pinch, bird pieces on the
      // whole-bird record and a fresh ham (v14: on the fresh shank half,
      // no longer held off the cured record — checkpoint 8, B7).
      final raw = golden('nutrition_matches_rules');
      final items = (raw['items']! as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final parsed = await NutritionRepository(
        goldenDio(raw),
      ).matches('nutrition-rules-sample');
      expect(parsed, hasLength(items.length));
      for (final (index, line) in parsed.indexed) {
        final match = items[index]['match']! as Map<String, dynamic>;
        expect(line.gramBasis, match['gram_basis']);
        expect(line.hold, match['hold']);
      }
      expect(
        [for (final line in parsed) line.gramBasis],
        containsAll(<Matcher>[
          contains('juice only (the zest is dropped)'),
          contains('summed on the whole egg'),
          contains('1/16 tsp (USDA tsp portion)'),
          contains('approximate (gross weight, no USDA refuse portion)'),
          contains('× 0.61 edible (USDA ready-to-cook yield)'),
          contains('nutrients of "Cabbage, chinese (pe-tsai), raw"'),
          // Matcher v11: napa grams entered by hand, and the pasta water's
          // held salt whose eaten "plus" part is its grams.
          equals(
            'entered by hand · nutrients of "Cabbage, chinese (pe-tsai), raw"',
          ),
          equals(
            'discarded in cooking — only "plus 1 teaspoon table salt" counted',
          ),
        ]),
      );
      final held = {
        for (final line in parsed)
          if (line.hold != null) line.hold!: holdReason(line.hold),
      };
      expect(held.keys, {'in_shell', 'discarded_medium'});
      // No golden line carries it since v14: the reason is read directly.
      expect(holdReason('cured_for_fresh'), contains('a preserved record'));
      expect(held['in_shell'], contains('Bought in the shell'));
      expect(held['discarded_medium'], contains('drained cooking water'));
    });

    test('an uncomputed recipe parses as unmatched lines', () async {
      // A real GET .../nutrition/matches on a recipe nobody has computed:
      // every item is `"match": null`, which is the branch that turns into
      // fdcId == null / status == 'unmatched'.
      final raw = golden('nutrition_matches_uncomputed');
      final items = (raw['items']! as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(items, isNotEmpty);
      expect(
        items.every((row) => row['match'] == null),
        isTrue,
        reason: 'this golden exists to carry null matches',
      );
      final parsed = await NutritionRepository(goldenDio(raw)).matches(
        'brown-butter-gemelli-with-asparagus-walnuts-and-lemony-ricotta',
      );
      expect(parsed, hasLength(items.length));
      for (final (index, line) in parsed.indexed) {
        expect(line.position, items[index]['position']);
        expect(line.raw, items[index]['raw']);
        expect(line.fdcId, isNull);
        expect(line.status, 'unmatched');
        expect(line.grams, isNull);
        expect(line.candidates, isEmpty);
        // The uncached branch keeps the line's own amount (S3: a bare
        // count reads as the count, "1 unit Lemon" -> "1").
        expect(line.lineAmount, items[index]['line_amount']);
        expect(line.kcalPer100g, items[index]['kcal_per_100g']);
        expect(line.portions, hasLength(0));
      }
      expect(
        [for (final line in parsed.take(2)) line.lineAmount],
        ['8 ounce', '1'],
      );
      expect(parsed.last.lineAmount, isNull);
    });

    test('Run 046: every line_amount, kcal_per_100g and portion field of '
        'the matches golden parses, a portion unit included', () async {
      final raw = golden('nutrition_matches');
      final items = (raw['items']! as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final parsed = await NutritionRepository(
        goldenDio(raw),
      ).matches('nutrition-sample');
      var units = 0;
      for (final (index, line) in parsed.indexed) {
        final row = items[index];
        expect(line.lineAmount, row['line_amount']);
        expect(line.kcalPer100g, row['kcal_per_100g']);
        final portions = (row['portions'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
        expect(line.portions, hasLength(portions.length));
        for (final (i, portion) in line.portions.indexed) {
          expect(portion.unit, portions[i]['unit']);
          expect(portion.grams, portions[i]['grams']);
          if (portion.unit != null) {
            units += 1;
          }
        }
      }
      // The sour cream and the flour carry an FDC "racc" portion.
      expect(units, greaterThan(0));
    });

    test('the bulk counts parse every scope and fail CLOSED', () async {
      final raw = golden('nutrition_bulk_counts');
      final dio = goldenDio(raw);
      final counts = await NutritionRepository(dio).bulkCounts();
      expect(counts.missing, raw['missing']);
      expect(counts.stale, raw['stale']);
      expect(counts.all, raw['all']);
      for (final scope in BulkScope.values) {
        expect(counts.of(scope), raw[scope.wireName]);
      }
      expect(
        (dio.httpClientAdapter as GoldenAdapter).requests.single.path,
        '/api/v1/nutrition/bulk/counts',
      );
      // A dropped key must be an error, never 0 — a 0 here disables the
      // compute button (a Stale of 0 reads as "nothing is stale").
      for (final scope in BulkScope.values) {
        final mutated = Map<String, dynamic>.from(raw)..remove(scope.wireName);
        await expectLater(
          NutritionRepository(goldenDio(mutated)).bulkCounts(),
          throwsA(isA<RepositoryException>()),
          reason: 'a missing ${scope.wireName} count must not read as 0',
        );
      }
    });

    test('the review queue parses buckets, rows, and their recipes', () async {
      final raw = golden('nutrition_review');
      final buckets = (raw['buckets']! as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final items = (raw['items']! as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final report = await RecipeRepository(
        dio: goldenDio(raw),
      ).getNutritionReview(page: 1);
      expect(report.total, raw['total']);
      expect(report.page, raw['page']);
      expect(report.limit, raw['limit']);

      expect(report.buckets, hasLength(buckets.length));
      expect(report.buckets, isNotEmpty);
      for (final (index, bucket) in report.buckets.indexed) {
        expect(bucket.id, buckets[index]['id']);
        expect(bucket.label, buckets[index]['label']);
        expect(bucket.count, buckets[index]['count']);
      }

      expect(report.items, hasLength(items.length));
      expect(report.items, isNotEmpty, reason: 'the golden flags a line');
      expect(
        report.items.map((line) => line.finishes),
        contains(1),
        reason: 'the golden holds a last open line',
      );
      for (final (index, line) in report.items.indexed) {
        final row = items[index];
        final recipe = row['recipe']! as Map<String, dynamic>;
        expect(line.position, row['position']);
        expect(line.raw, row['raw']);
        expect(line.bucket, row['bucket']);
        expect(line.recipe.id, recipe['id']);
        expect(line.recipe.slug, recipe['slug']);
        expect(line.recipe.title, recipe['title']);
        expect(line.key, '${recipe['slug']}#${row['position']}');
        // A line item's `finishes`: 1 on its recipe's last open line.
        expect(line.finishes, row['finishes']);
        final match = row['match']! as Map<String, dynamic>;
        expect(line.match, isNotNull);
        expect(line.match!.fdcId, match['fdc_id']);
        expect(line.match!.description, match['description']);
        expect(line.match!.dataType, match['data_type']);
        expect(line.match!.confidence, match['confidence']);
        expect(line.match!.grams, match['grams']);
        expect(line.match!.gramSource, match['gram_source']);
        expect(line.match!.status, match['status']);
        expect(line.match!.hold, match['hold']);
      }
    });

    test('the grouped queue parses the group fields', () async {
      final raw = golden('nutrition_review_grouped');
      final items = (raw['items']! as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final dio = goldenDio(raw);
      final report = await RecipeRepository(
        dio: dio,
      ).getNutritionReview(page: 1, grouped: true);

      // Grouped mode is a MODE on the same endpoint, not a new one.
      final sent = (dio.httpClientAdapter as GoldenAdapter).requests.single;
      expect(sent.path, '/api/v1/admin/nutrition_review');
      expect(sent.queryParameters['group'], 'item');

      // `total` stays a LINE count in both modes; `groups` is the new one.
      expect(report.total, raw['total']);
      expect(report.groups, raw['groups']);
      expect(report.groups, isNotNull);
      for (final (index, bucket) in report.buckets.indexed) {
        final b =
            (raw['buckets']! as List<dynamic>)[index] as Map<String, dynamic>;
        expect(bucket.count, b['count']);
        expect(bucket.groups, b['groups']);
      }

      expect(report.items, hasLength(items.length));
      expect(report.items, isNotEmpty, reason: 'the golden flags a group');
      for (final (index, group) in report.items.indexed) {
        final row = items[index];
        final grams = (row['grams']! as Map).cast<String, dynamic>();
        // The example line is at TOP LEVEL, so the key, the fix pane and
        // queueShouldAdvance are untouched by grouping.
        expect(
          group.key,
          '${(row['recipe']! as Map)['slug']}#'
          '${row['position']}',
        );
        expect(group.raw, row['raw']);
        expect(group.itemKey, row['item_key']);
        expect(group.item, row['item']);
        expect(group.lines, row['lines']);
        expect(group.recipes, row['recipes']);
        expect(group.decided, row['decided']);
        expect(group.gramsMin, grams['min']);
        expect(group.gramsMax, grams['max']);
        expect(group.gramsMissing, grams['missing']);
        expect(group.finishes, row['finishes']);
        expect(group.lastOpen, row['last_open']);
        expect([
          for (final r in group.finishesRecipes) {'id': r.id, 'title': r.title},
        ], row['finishes_recipes']);
      }
      // The whole-library banner.
      expect(report.finishable, raw['finishable']);
      expect(report.openRecipes, raw['open_recipes']);
      expect(report.finishable, greaterThan(0));
      expect(
        report.items.any((group) => group.finishes > 0),
        isTrue,
        reason: 'the golden carries a group that finishes a recipe',
      );

      // The order rides as `sort`, and only in grouped mode.
      final sorted = goldenDio(raw);
      await RecipeRepository(
        dio: sorted,
      ).getNutritionReview(page: 1, grouped: true, sort: 'worst');
      expect(
        (sorted.httpClientAdapter as GoldenAdapter)
            .requests
            .single
            .queryParameters['sort'],
        'worst',
      );
    });

    test(
      'C1: the confirm-with-amount receipt parses applied.completed',
      () async {
        final raw = golden('nutrition_confirm_applied');
        final applied = raw['applied']! as Map<String, dynamic>;
        expect(applied.keys, containsAll(['recipes', 'lines', 'failed']));
        expect(applied, contains('completed'));
        final dio = goldenDio(raw);
        final result = await NutritionRepository(dio).overrideMatch(
          'nutrition-rules-sample',
          12,
          confirmed: true,
          grams: 452,
          applyToAll: true,
        );
        expect(result.applied!.completed, applied['completed']);
        expect(result.applied!.completedRecipes, applied['completed_recipes']);
        expect(result.applied!.recipes, applied['recipes']);
        // The butter line took its amount with the confirm.
        final butter = result.matches.singleWhere((m) => m.position == 12);
        expect(butter.status, 'confirmed');
        expect(butter.grams, 452);
        expect((dio.httpClientAdapter as GoldenAdapter).requests.single.data, {
          'grams': 452.0,
          'confirmed': true,
          'apply_to_all': true,
        });
      },
    );

    test('C1: line_amount, portions (with fill) and the approximation basis '
        'parse from the rules golden', () async {
      final raw = golden('nutrition_matches_rules');
      final items = (raw['items']! as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final parsed = await NutritionRepository(
        goldenDio(raw),
      ).matches('nutrition-rules-sample');
      for (final (index, line) in parsed.indexed) {
        final row = items[index];
        expect(line.lineAmount, row['line_amount']);
        expect(line.kcalPer100g, row['kcal_per_100g']);
        final portions = (row['portions']! as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(line.portions, hasLength(portions.length));
        for (final (i, portion) in line.portions.indexed) {
          expect(portion.grams, portions[i]['grams']);
          expect(portion.amount, portions[i]['amount']);
          expect(portion.unit, portions[i]['unit']);
          expect(portion.description, portions[i]['description']);
          expect(portion.fill, portions[i]['fill']);
        }
      }
      final butter = parsed.singleWhere((m) => m.position == 12);
      expect(butter.lineAmount, '4 stick');
      // "Butter, without salt" (173430): its energy, 717 kcal per 100 g.
      expect(butter.kcalPer100g, 717);
      expect(
        [
          for (final p in butter.portions)
            if (p.fill != null) (p.description, p.fill),
        ],
        [('stick', 452.0)],
      );
      final pancetta = parsed.singleWhere((m) => m.position == 11);
      expect(
        pancetta.gramBasis,
        endsWith(
          ' · approximation (counted as Pork, cured, bacon, unprepared)',
        ),
      );
    });
  });
}
