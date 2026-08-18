import 'package:flutter_test/flutter_test.dart';
import 'package:salt_app/core/api/auth_repository.dart';
import 'package:salt_app/core/api/import_repository.dart';
import 'package:salt_app/core/api/library_repository.dart';
import 'package:salt_app/core/api/nutrition_repository.dart';
import 'package:salt_app/core/api/recipe_repository.dart';
import 'package:salt_app/core/api/tags_repository.dart';

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
        final match = row['match']! as Map<String, dynamic>;
        expect(line.match, isNotNull);
        expect(line.match!.fdcId, match['fdc_id']);
        expect(line.match!.description, match['description']);
        expect(line.match!.dataType, match['data_type']);
        expect(line.match!.confidence, match['confidence']);
        expect(line.match!.grams, match['grams']);
        expect(line.match!.gramSource, match['gram_source']);
        expect(line.match!.status, match['status']);
      }
    });
  });
}
