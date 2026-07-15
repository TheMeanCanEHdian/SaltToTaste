import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/exceptions.dart';
import 'package:salt_server/src/handlers/image_handlers.dart';
import 'package:salt_server/src/handlers/recipe_handlers.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

const _corpusRoot =
    '/Users/drivard/Documents/Claude Projects/Recipe Extraction';
const _corpusBook =
    'The Complete America_s Test Kitchen TV Show Cookbook 2001–2023';

const _sourceSlug = 'atk-tv-2023';
const _heroJpg = '0857-rich-chocolate-bundt-cake-hero.jpg';

Recipe _load(String fileName) => RecipeYamlCodec.decode(
      File('$_corpusRoot/$_corpusBook/recipes/$fileName').readAsStringSync(),
    ).recipe;

String _hashOf(Recipe recipe) =>
    sha256.convert(utf8.encode(jsonEncode(recipe.toMap()))).toString();

void main() {
  late Recipe bundtCake; // Rich Chocolate Bundt Cake
  late Recipe sweetPotatoSoup; // Sweet Potato Soup
  late Directory tempDir;
  late String libraryDir;
  late String imagesDir;
  late SaltDatabase db;

  setUpAll(() {
    bundtCake = _load('0857-rich-chocolate-bundt-cake.yaml');
    sweetPotatoSoup = _load('0020-sweet-potato-soup.yaml');
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('salt_routes_test');
    libraryDir = '${tempDir.path}/library';
    imagesDir = '$libraryDir/$_sourceSlug/images';
    Directory(imagesDir).createSync(recursive: true);
    File('$_corpusRoot/$_corpusBook/images/$_heroJpg')
        .copySync('$imagesDir/$_heroJpg');

    db = SaltDatabase.open('${tempDir.path}/salt.db')
      ..upsertSource(
        slug: _sourceSlug,
        name: "The Complete America's Test Kitchen TV Show Cookbook "
            '2001–2023',
        type: 'epub',
      );
    for (final recipe in [bundtCake, sweetPotatoSoup]) {
      db.upsertRecipe(
        recipe,
        sourceSlug: _sourceSlug,
        contentHash: _hashOf(recipe),
      );
    }
  });

  tearDown(() {
    db.dispose();
    tempDir.deleteSync(recursive: true);
  });

  group('parseListParams', () {
    test('defaults to page 1 / limit 24', () {
      expect(parseListParams(const {}), (page: 1, limit: 24));
    });

    test('accepts explicit values within bounds', () {
      expect(
        parseListParams(const {'page': '3', 'limit': '100'}),
        (page: 3, limit: 100),
      );
      expect(parseListParams(const {'limit': '1'}).limit, 1);
    });

    test('rejects non-integer, zero, negative, and oversized values', () {
      for (final query in [
        const {'page': 'abc'},
        const {'page': '0'},
        const {'page': '-1'},
        const {'page': ''},
        const {'limit': 'abc'},
        const {'limit': '0'},
        const {'limit': '101'},
      ]) {
        expect(
          () => parseListParams(query),
          throwsA(isA<ValidationException>()),
          reason: 'query $query should be rejected',
        );
      }
    });
  });

  group('listRecipes', () {
    test('returns paged card maps ordered by title', () {
      final pageOne = listRecipes(db, page: 1, limit: 1);
      expect(pageOne['total'], 2);
      expect(pageOne['page'], 1);
      expect(pageOne['limit'], 1);
      final items = pageOne['items']! as List<Object?>;
      expect(items, hasLength(1));
      final card = items.first! as Map<String, dynamic>;
      expect(card['title'], 'Rich Chocolate Bundt Cake');
      expect(card['slug'], bundtCake.slug);
      expect(card['hero_image'], '/images/$_sourceSlug/$_heroJpg');

      final pageTwo = listRecipes(db, page: 2, limit: 1);
      final secondItems = pageTwo['items']! as List<Object?>;
      final secondCard = secondItems.first! as Map<String, dynamic>;
      expect(secondCard['title'], 'Sweet Potato Soup');
      expect(pageTwo['total'], 2);
    });

    test('returns an empty page past the end', () {
      final page = listRecipes(db, page: 9, limit: 24);
      expect(page['items'], isEmpty);
      expect(page['total'], 2);
    });
  });

  group('recipeDetail', () {
    test('resolves by id with source slug and hero image URL', () {
      final detail = recipeDetail(db, bundtCake.id);
      expect(detail['source_slug'], _sourceSlug);
      expect(detail['hero_image_url'], '/images/$_sourceSlug/$_heroJpg');
      final recipeMap = detail['recipe']! as Map<String, dynamic>;
      expect(RecipeMapper.fromMap(recipeMap), equals(bundtCake));
    });

    test('resolves by slug', () {
      final detail = recipeDetail(db, sweetPotatoSoup.slug);
      final recipeMap = detail['recipe']! as Map<String, dynamic>;
      expect(RecipeMapper.fromMap(recipeMap), equals(sweetPotatoSoup));
    });

    test('unknown key throws NotFoundException', () {
      expect(
        () => recipeDetail(db, 'no-such-recipe'),
        throwsA(
          isA<NotFoundException>().having(
            (e) => e.message,
            'message',
            'recipe not found: no-such-recipe',
          ),
        ),
      );
    });
  });

  group('recipeYaml', () {
    test('body round-trips to an equal Recipe with id-based file name', () {
      final result = recipeYaml(db, bundtCake.slug);
      expect(result.fileName, '${bundtCake.id}.yaml');
      final decoded = RecipeYamlCodec.decode(result.yaml);
      expect(decoded.recipe, equals(bundtCake));
    });

    test('unknown key throws NotFoundException', () {
      expect(
        () => recipeYaml(db, 'no-such-recipe'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('resolveLibraryImage', () {
    test('serves a real corpus jpg with image/jpeg', () {
      final image = resolveLibraryImage(
        libraryDir: libraryDir,
        source: _sourceSlug,
        file: _heroJpg,
      );
      expect(image.contentType, 'image/jpeg');
      expect(
        image.bytes,
        File('$imagesDir/$_heroJpg').readAsBytesSync(),
      );
    });

    test('rejects traversal and malformed segments with validation', () {
      final badSegments = [
        '..',
        '..%2Fsecret.jpg',
        '../secret.jpg',
        '/etc/passwd',
        r'..\secret.jpg',
        '.hidden.jpg',
        '',
      ];
      for (final bad in badSegments) {
        expect(
          () => resolveLibraryImage(
            libraryDir: libraryDir,
            source: _sourceSlug,
            file: bad,
          ),
          throwsA(isA<ValidationException>()),
          reason: "file segment '$bad' should be rejected",
        );
        expect(
          () => resolveLibraryImage(
            libraryDir: libraryDir,
            source: bad,
            file: _heroJpg,
          ),
          throwsA(isA<ValidationException>()),
          reason: "source segment '$bad' should be rejected",
        );
      }
    });

    test('missing file is NotFoundException', () {
      expect(
        () => resolveLibraryImage(
          libraryDir: libraryDir,
          source: _sourceSlug,
          file: 'nope.jpg',
        ),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('disallowed extension is NotFoundException without probing', () {
      File('$imagesDir/notes.txt').writeAsStringSync('not an image');
      expect(
        () => resolveLibraryImage(
          libraryDir: libraryDir,
          source: _sourceSlug,
          file: 'notes.txt',
        ),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('symlink escaping the library dir is NotFoundException', () {
      final outside = File('${tempDir.path}/outside.jpg')
        ..writeAsBytesSync(const [1, 2, 3]);
      Link('$imagesDir/escape.jpg').createSync(outside.path);
      expect(
        () => resolveLibraryImage(
          libraryDir: libraryDir,
          source: _sourceSlug,
          file: 'escape.jpg',
        ),
        throwsA(isA<NotFoundException>()),
      );
    });
  });
}
