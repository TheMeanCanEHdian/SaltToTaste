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
/// of Grilled Scallops with Fennel and Orange Salad for Two, 0651, are the
/// pin now — the one corpus line whose answer names its food only below
/// the eight shown.)
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
        '0651-grilled-scallops-with-fennel-and-orange-salad-for-two.yaml',
      );
      // The recorded answer, stored the way a compute stores it. No compute
      // ran: the line has no match row and nothing to show.
      final recorded =
          (jsonDecode(
                    File('test/fixtures/fdc/searches.json').readAsStringSync(),
                  )
                  as Map<String, dynamic>)['pink peppercorns']
              as List<dynamic>;
      db.fdcSearchCachePut('pink peppercorns', jsonEncode(recorded));
      final provider = FixtureProvider();
      final answer = await provider.search('pink peppercorns');
      final shown = rankCandidates(
        'pink peppercorns',
        answer,
      ).take(8).map((c) => c.candidate).toList();
      expect(candidatesNameIngredient('pink peppercorns', shown), isFalse);
      expect(candidatesNameIngredient('pink peppercorns', answer), isTrue);

      final searchesBefore = provider.searchCalls;
      final body = await matchesBody(db, provider, recipe);
      final line = (body['items']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere(
            (item) => item['candidates_query'] == 'pink peppercorns',
          );
      expect(line['raw'], '2 teaspoons pink peppercorns, crushed');
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
