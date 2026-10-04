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
/// candidates the sheet shows: "Peppers, hot chile, sun-dried" was 11th of
/// the 16 records FDC returns for 'thai chiles', so the line read "nothing
/// names this ingredient" while the answer did. (Matcher v8's chile credit
/// lifts it into the eight; the flap meat of Crispy Orange Beef, 0536, was
/// the pin until matcher v30 made it a rank-as item; the pink peppercorns
/// of Grilled Scallops with Fennel and Orange Salad for Two, 0651, until
/// matcher v37 counted them as black pepper; the sugar stars of Meringue
/// Christmas Trees, 1198, are the pin now — the one food line of the corpus
/// whose cached answer, snapshot 15, names its food only below the eight
/// shown.)
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
        '1198-meringue-christmas-trees.yaml',
      );
      // The recorded answer, stored the way a compute stores it. No compute
      // ran: the line has no match row and nothing to show.
      final recorded =
          (jsonDecode(
                    File('test/fixtures/fdc/searches.json').readAsStringSync(),
                  )
                  as Map<String, dynamic>)['sugar stars']
              as List<dynamic>;
      db.fdcSearchCachePut('sugar stars', jsonEncode(recorded));
      final provider = FixtureProvider();
      final answer = await provider.search('sugar stars');
      final shown = rankCandidates(
        'sugar stars',
        answer,
      ).take(8).map((c) => c.candidate).toList();
      expect(candidatesNameIngredient('sugar stars', shown), isFalse);
      expect(candidatesNameIngredient('sugar stars', answer), isTrue);

      final searchesBefore = provider.searchCalls;
      final body = await matchesBody(db, provider, recipe);
      final line = (body['items']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere(
            (item) => item['candidates_query'] == 'sugar stars',
          );
      expect(line['raw'], 'Sugar stars');
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
