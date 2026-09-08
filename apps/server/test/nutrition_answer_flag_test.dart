import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/fdc_fixtures.dart';

/// The Opus fleet found `candidates_name_ingredient` judged only the eight
/// candidates the sheet shows: "Peppers, hot chile, sun-dried" is 11th of the
/// 16 records FDC returns for 'thai chiles', so the line read "nothing names
/// this ingredient" while the answer did.
void main() {
  test(
    'the matches body judges the WHOLE cached answer, not the eight it shows',
    skip: skipIfNoCorpus,
    () async {
      final tempDir = Directory.systemTemp.createTempSync('salt-answer-flag');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final db = SaltDatabase.open(
        ServerConfig(
          dataDir: tempDir.path,
          logLevel: Level.WARNING,
          trustProxy: false,
        ).dbPath,
      );
      addTearDown(db.dispose);
      final recipe = loadCorpusRecipe(
        '0642-thai-grilled-cornish-game-hens-with-gai-yang-chili-dipping-sauce.yaml',
      );
      // The recorded answer, stored the way a compute stores it. No compute
      // ran: the line has no match row and nothing to show.
      final recorded =
          (jsonDecode(
                    File('test/fixtures/fdc/searches.json').readAsStringSync(),
                  )
                  as Map<String, dynamic>)['thai chiles']
              as List<dynamic>;
      db.fdcSearchCachePut('thai chiles', jsonEncode(recorded));
      final provider = FixtureProvider();
      final answer = await provider.search('thai chiles');
      final shown = rankCandidates(
        'thai chiles',
        answer,
      ).take(8).map((c) => c.candidate).toList();
      expect(candidatesNameIngredient('thai chiles', shown), isFalse);
      expect(candidatesNameIngredient('thai chiles', answer), isTrue);

      final searchesBefore = provider.searchCalls;
      final body = await matchesBody(db, provider, recipe);
      final line = (body['items']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere(
            (item) => item['candidates_query'] == 'thai chiles',
          );
      expect(line['raw'], '1 tablespoon minced Thai chiles');
      expect(line['candidates_name_ingredient'], isTrue);
      expect(line['candidates'], isEmpty, reason: 'no compute ran');
      expect(
        provider.searchCalls,
        searchesBefore,
        reason: 'a GET never searches',
      );
    },
  );
}
