/// Validates [parseIngredientLine] against the real ATK extraction corpus:
/// every ingredient line's `raw` is re-parsed and compared with the stored
/// extraction (which the reviewed Python extractor produced), measuring
/// agreement on the primary amount, the full amounts list, item, and prep.
library;

import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'corpus.dart';

/// One corpus ingredient line paired with its stored extraction.
class _CorpusLine {
  _CorpusLine(this.file, this.stored);

  final String file;
  final IngredientLine stored;
}

/// Every ingredient line in the corpus — top-level groups plus subsection
/// sub-recipes (both carry the same extraction shape).
List<_CorpusLine> _allCorpusLines() {
  final decode = decodeCorpus();
  expect(decode.failures, isEmpty, reason: 'corpus must decode cleanly');
  final lines = <_CorpusLine>[];
  for (final entry in decode.results.entries) {
    final recipe = entry.value.recipe;
    final groups = [
      ...recipe.ingredients,
      for (final subsection in recipe.subsections) ...?subsection.ingredients,
    ];
    for (final group in groups) {
      for (final item in group.items) {
        lines.add(_CorpusLine(entry.key, item));
      }
    }
  }
  return lines;
}

/// Comparable projection of one amount.
String _amountKey(Amount a) =>
    '${a.measure.name}|${a.quantity}|${a.unit}|${a.approximate}|${a.primary}';

String? _primaryKey(List<Amount> amounts) {
  for (final a in amounts) {
    if (a.primary) return '${a.measure.name}|${a.quantity}|${a.unit}';
  }
  return null;
}

String _amountsKey(List<Amount> amounts) => amounts.map(_amountKey).join(' + ');

void main() {
  group('parseIngredientLine corpus agreement', skip: skipIfNoCorpus, () {
    test('agrees with the stored extraction across all corpus lines', () {
      final lines = _allCorpusLines();
      // 13,615 top-level lines + subsection sub-recipe lines.
      expect(lines.length, greaterThan(16000));

      var primaryAgree = 0;
      var amountsAgree = 0;
      var itemAgree = 0;
      var prepAgree = 0;
      var disagreeingLines = 0;
      var disagreeingFlagged = 0;
      var knownCorpusMisparses = 0;
      final examples = <String>[];

      for (final line in lines) {
        final stored = line.stored;
        final got = parseIngredientLine(stored.raw);

        final primaryOk =
            _primaryKey(got.amounts) == _primaryKey(stored.amounts);
        final amountsOk =
            _amountsKey(got.amounts) == _amountsKey(stored.amounts);
        final itemOk = got.item == stored.item;
        final prepOk = got.prep == stored.prep;

        if (primaryOk) primaryAgree++;
        if (amountsOk) amountsAgree++;
        if (itemOk) itemAgree++;
        if (prepOk) prepAgree++;

        if (!(amountsOk && itemOk && prepOk)) {
          // The extractor that produced the corpus could not match
          // multi-word units, so the champagne-cocktail `fluid ounce` lines
          // are stored misparsed (count primary, unit glued to the item).
          // parseIngredientLine now reads them correctly, so they disagree
          // by design — counted separately and pinned to exactly the known
          // set below, and kept out of the flagged-ratio gate (which
          // measures whether hand-edited review-queue shapes still get
          // routed to review, not deliberate improvements).
          if (stored.raw.toLowerCase().contains('fluid ounce')) {
            knownCorpusMisparses++;
            continue;
          }
          disagreeingLines++;
          // Nearly every disagreement is a line the human review queue
          // hand-edited; the confidence flag should have routed it there.
          if (got.confidence != ParseConfidence.parsed) disagreeingFlagged++;
          if (examples.length < 10) {
            examples.add(
              '[${line.file}] ${stored.raw}\n'
              '    want amounts=${_amountsKey(stored.amounts)} '
              'item=${stored.item} prep=${stored.prep}\n'
              '    got  amounts=${_amountsKey(got.amounts)} '
              'item=${got.item} prep=${got.prep} '
              '(${got.confidence.name})',
            );
          }
        }
      }

      // The corpus has exactly seven `fluid ounce` lines (all in
      // 1155-champagne-cocktail.yaml), every one stored misparsed; a change
      // here means either the corpus moved or the carve-out leaks.
      expect(
        knownCorpusMisparses,
        7,
        reason: 'known corpus fluid-ounce misparses drifted',
      );

      final total = lines.length;
      String pct(int n) => (n / total * 100).toStringAsFixed(2);
      // One-line summary so a regression is diagnosable from the test log.
      print(
        'ingredient parser agreement over $total corpus lines: '
        'primary ${pct(primaryAgree)}% | amounts ${pct(amountsAgree)}% | '
        'item ${pct(itemAgree)}% | prep ${pct(prepAgree)}% | '
        'disagreements flagged check/none: '
        '$disagreeingFlagged/$disagreeingLines '
        '(+$knownCorpusMisparses known corpus misparses)',
      );
      if (examples.isNotEmpty) {
        print('top disagreements:\n  ${examples.join('\n  ')}');
      }

      // Hard floors, one point below the measured rates (2026-07-15):
      // primary 99.76%, amounts 99.76%, item 99.09%, prep 99.35% (the
      // seven known fluid-ounce misparses count against agreement but are
      // pinned above). The remaining disagreements are hand edits from the
      // extraction's human review queue (`or` alternatives, leading-verb
      // preps, parenthetical moves), not parser regressions.
      expect(
        primaryAgree / total,
        greaterThanOrEqualTo(0.988),
        reason: 'primary amount agreement regressed',
      );
      expect(
        amountsAgree / total,
        greaterThanOrEqualTo(0.988),
        reason: 'full amounts-list agreement regressed',
      );
      expect(
        itemAgree / total,
        greaterThanOrEqualTo(0.981),
        reason: 'item agreement regressed',
      );
      expect(
        prepAgree / total,
        greaterThanOrEqualTo(0.983),
        reason: 'prep agreement regressed',
      );

      // The confidence flag must keep routing the hand-edited shapes to
      // review: measured 98.6% of disagreeing lines flagged (2026-07-15).
      expect(
        disagreeingFlagged / disagreeingLines,
        greaterThanOrEqualTo(0.95),
        reason: 'disagreeing lines are no longer flagged check/none',
      );
    });
  });

  group('parseIngredientLine on real corpus lines', skip: skipIfNoCorpus, () {
    // All raw lines below are from 0857-rich-chocolate-bundt-cake.yaml.
    test('dual-amount flour line: volume primary + weight equivalent', () {
      final parsed = parseIngredientLine(
        '1¾ cups (8¾ ounces) unbleached all-purpose flour',
      );
      expect(parsed.amounts, hasLength(2));
      final primary = parsed.amounts.first;
      expect(primary.measure, Measure.volume);
      expect(primary.quantity, '1 3/4');
      expect(primary.unit, 'cup');
      expect(primary.approximate, isFalse);
      expect(primary.primary, isTrue);
      final equivalent = parsed.amounts.last;
      expect(equivalent.measure, Measure.weight);
      expect(equivalent.quantity, '8 3/4');
      expect(equivalent.unit, 'ounce');
      expect(equivalent.approximate, isFalse);
      expect(equivalent.primary, isFalse);
      expect(parsed.item, 'unbleached all-purpose flour');
      expect(parsed.prep, isNull);
      expect(parsed.confidence, ParseConfidence.parsed);
    });

    test(
      'butter line: stick parenthetical stays on item, prep after comma',
      () {
        final parsed = parseIngredientLine(
          '12 tablespoons (1½ sticks) unsalted butter, softened, '
          'plus 1 tablespoon, melted, for the pan',
        );
        expect(parsed.amounts, hasLength(1));
        final amount = parsed.amounts.single;
        expect(amount.measure, Measure.volume);
        expect(amount.quantity, '12');
        expect(amount.unit, 'tablespoon');
        expect(amount.primary, isTrue);
        // `(1½ sticks)` is a size note, not a weight/volume equivalent — it
        // stays on the item, fractions normalized to ASCII.
        expect(parsed.item, '(1 1/2 sticks) unsalted butter');
        expect(parsed.prep, 'softened, plus 1 tablespoon, melted, for the pan');
        expect(parsed.confidence, ParseConfidence.parsed);
      },
    );

    test('eggs line: count amount with null unit', () {
      final parsed = parseIngredientLine('5 large eggs, at room temperature');
      expect(parsed.amounts, hasLength(1));
      final amount = parsed.amounts.single;
      expect(amount.measure, Measure.count);
      expect(amount.quantity, '5');
      expect(amount.unit, isNull);
      expect(amount.primary, isTrue);
      expect(parsed.item, 'large eggs');
      expect(parsed.prep, 'at room temperature');
      expect(parsed.confidence, ParseConfidence.parsed);
    });

    test(
      'amount-less line: empty amounts, trailing "for ..." clause is prep',
      () {
        final parsed = parseIngredientLine('Confectioners’ sugar, for dusting');
        expect(parsed.amounts, isEmpty);
        expect(parsed.item, 'Confectioners’ sugar');
        expect(parsed.prep, 'for dusting');
        expect(parsed.confidence, ParseConfidence.none);
      },
    );

    test('unit-only pinch line: count amount with empty-string quantity', () {
      // e.g. 0022-broccoli-cheese-soup.yaml
      final parsed = parseIngredientLine('Pinch cayenne pepper');
      expect(parsed.amounts, hasLength(1));
      final amount = parsed.amounts.single;
      expect(amount.measure, Measure.count);
      // The YAML codec's convention for v1 `quantity: null` unit-only lines.
      expect(amount.quantity, '');
      expect(amount.unit, 'pinch');
      expect(amount.primary, isTrue);
      expect(parsed.item, 'cayenne pepper');
      expect(parsed.prep, isNull);
      expect(parsed.confidence, ParseConfidence.parsed);
    });

    test('package-size line: leading parenthetical flags check', () {
      // 0089-braised-oxtails-with-white-beans-tomatoes-and-aleppo-pepper.yaml
      final parsed = parseIngredientLine(
        '1 (28-ounce) can whole peeled tomatoes',
      );
      expect(parsed.amounts, hasLength(1));
      final amount = parsed.amounts.single;
      expect(amount.measure, Measure.count);
      expect(amount.quantity, '1');
      expect(amount.unit, 'can');
      expect(parsed.item, '(28-ounce) whole peeled tomatoes');
      expect(parsed.prep, isNull);
      expect(parsed.confidence, ParseConfidence.check);
    });

    test('about-marked same-measure parenthetical folds into the primary', () {
      // 0044-mediterranean-chopped-salad.yaml — the parenthetical is a
      // yield restatement, not a conversion; it marks the pint approximate
      // instead of adding a second volume amount.
      final parsed = parseIngredientLine(
        '1 pint grape tomatoes, quartered (about 1½ cups)',
      );
      expect(parsed.amounts, hasLength(1));
      final amount = parsed.amounts.single;
      expect(amount.measure, Measure.volume);
      expect(amount.quantity, '1');
      expect(amount.unit, 'pint');
      expect(amount.approximate, isTrue);
      expect(amount.primary, isTrue);
      expect(parsed.item, 'grape tomatoes');
      expect(parsed.prep, 'quartered');
      expect(parsed.confidence, ParseConfidence.parsed);
    });

    test('corpus fluid-ounce line: multi-word unit parses as volume', () {
      // 1155-champagne-cocktail.yaml — stored misparsed in the corpus (the
      // extractor matched single-token units only); parsed correctly here.
      final parsed = parseIngredientLine(
        '5½ fluid ounces (½ cup plus 3 tablespoons) champagne, chilled',
      );
      expect(parsed.amounts, hasLength(1));
      final amount = parsed.amounts.single;
      expect(amount.measure, Measure.volume);
      expect(amount.quantity, '5 1/2');
      expect(amount.unit, 'fluid ounce');
      expect(amount.primary, isTrue);
      // `plus` breaks the equivalent shape, so the parenthetical stays on
      // the item rather than becoming a secondary amount.
      expect(parsed.item, '(1/2 cup plus 3 tablespoons) champagne');
      expect(parsed.prep, 'chilled');
      expect(parsed.confidence, ParseConfidence.parsed);
    });
  });

  // Shapes the corpus never produced but the recipe editor and bulk paste
  // legitimately do (metric equivalents, abbreviations, missing-vocabulary
  // units). Synthetic by necessity — the ATK corpus has no metric lines.
  group('parseIngredientLine on editor/bulk-paste lines', () {
    test('same-measure metric parenthetical becomes a secondary amount', () {
      final parsed = parseIngredientLine('1 cup (240 ml) milk');
      expect(parsed.amounts, hasLength(2));
      final primary = parsed.amounts.first;
      expect(primary.measure, Measure.volume);
      expect(primary.quantity, '1');
      expect(primary.unit, 'cup');
      expect(primary.primary, isTrue);
      final equivalent = parsed.amounts.last;
      expect(equivalent.measure, Measure.volume);
      expect(equivalent.quantity, '240');
      expect(equivalent.unit, 'milliliter');
      expect(equivalent.approximate, isFalse);
      expect(equivalent.primary, isFalse);
      expect(parsed.item, 'milk');
      expect(parsed.prep, isNull);
      expect(parsed.confidence, ParseConfidence.parsed);
    });

    test('leading metric parenthetical becomes a secondary amount', () {
      final parsed = parseIngredientLine('(200 g) flour');
      expect(parsed.amounts, hasLength(1));
      final amount = parsed.amounts.single;
      expect(amount.measure, Measure.weight);
      expect(amount.quantity, '200');
      expect(amount.unit, 'gram');
      expect(amount.primary, isFalse);
      expect(parsed.item, 'flour');
      expect(parsed.prep, isNull);
      // Leading parentheticals are a known-hard shape -> review.
      expect(parsed.confidence, ParseConfidence.check);
    });

    test('bare fluid ounces line parses as a volume primary', () {
      final parsed = parseIngredientLine('8 fluid ounces milk');
      expect(parsed.amounts, hasLength(1));
      final amount = parsed.amounts.single;
      expect(amount.measure, Measure.volume);
      expect(amount.quantity, '8');
      expect(amount.unit, 'fluid ounce');
      expect(amount.primary, isTrue);
      expect(parsed.item, 'milk');
      expect(parsed.prep, isNull);
      expect(parsed.confidence, ParseConfidence.parsed);
    });

    test('fl oz abbreviation (with or without dots) expands', () {
      for (final raw in ['8 fl oz milk', '8 fl. oz. milk']) {
        final parsed = parseIngredientLine(raw);
        final amount = parsed.amounts.single;
        expect(amount.measure, Measure.volume, reason: raw);
        expect(amount.quantity, '8', reason: raw);
        expect(amount.unit, 'fluid ounce', reason: raw);
        expect(parsed.item, 'milk', reason: raw);
        expect(parsed.confidence, ParseConfidence.parsed, reason: raw);
      }
    });

    test('unrecognized unit-like token flags check, not a silent count', () {
      // 'T' (a tablespoon abbreviation the vocabulary doesn't carry) and a
      // half-typed multi-word unit must not read as clean counts.
      for (final raw in ['2 T sugar', '8 fluid ouncez milk']) {
        final parsed = parseIngredientLine(raw);
        expect(parsed.amounts.single.measure, Measure.count, reason: raw);
        expect(parsed.confidence, ParseConfidence.check, reason: raw);
      }
      // A plain word after the quantity stays a clean count.
      expect(
        parseIngredientLine('5 large eggs').confidence,
        ParseConfidence.parsed,
      );
    });
  });
}
