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
/// lifts it into the eight; the flap meat of Crispy Orange Beef, 0536, is
/// the pin now: its answer names flap meat below the eight shown.)
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
      final recipe = loadCorpusRecipe('0536-crispy-orange-beef.yaml');
      // The recorded answer, stored the way a compute stores it. No compute
      // ran: the line has no match row and nothing to show.
      final recorded =
          (jsonDecode(
                    File('test/fixtures/fdc/searches.json').readAsStringSync(),
                  )
                  as Map<String, dynamic>)['beef flap meat']
              as List<dynamic>;
      db.fdcSearchCachePut('beef flap meat', jsonEncode(recorded));
      final provider = FixtureProvider();
      final answer = await provider.search('beef flap meat');
      final shown = rankCandidates(
        'beef flap meat',
        answer,
      ).take(8).map((c) => c.candidate).toList();
      expect(candidatesNameIngredient('beef flap meat', shown), isFalse);
      expect(candidatesNameIngredient('beef flap meat', answer), isTrue);

      final searchesBefore = provider.searchCalls;
      final body = await matchesBody(db, provider, recipe);
      final line = (body['items']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere(
            (item) => item['candidates_query'] == 'beef flap meat',
          );
      expect(line['raw'], '1½ pounds beef flap meat, trimmed');
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
