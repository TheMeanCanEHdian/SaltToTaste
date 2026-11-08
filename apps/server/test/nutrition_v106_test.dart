// Matcher v106 (batch fix106 at the base eb9614c; matcherVersion 97
// unchanged) — the fixes of dual-fleet review Run 081/082 over v105,
// union U1–U13 (.claude/diag/2026-11-07/review081/union_T.md; the rulings
// in fix106/brief.md). Every pin is a real corpus recipe through the real
// readers / compute on the recorded fixtures; each STATED synthesized input
// names its exception and its corpus source.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/handlers/nutrition_handlers.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

import 'support/corpus.dart';
import 'support/cost_bounds.dart';
import 'support/fdc_fixtures.dart';

const _bulalo = '1171-bulalo-hearty-beef-shank-and-vegetable-soup.yaml';
const _gravy = '0351-pasta-with-hearty-italian-meat-sauce-sunday-gravy.yaml';
const _herb = '0184-restaurant-style-herb-sauce-for-pan-seared-steaks.yaml';
const _source = 'atk-tv-2023';

final _fx = FixtureProvider(pending: pendingSearches);

SaltDatabase _db() {
  final dir = Directory.systemTemp.createTempSync('salt-v106-');
  final config = ServerConfig(
    dataDir: dir.path,
    logLevel: Level.WARNING,
    trustProxy: false,
  );
  final db = SaltDatabase.open(config.dbPath)
    ..upsertSource(slug: _source, name: 'ATK', type: 'epub');
  addTearDown(() {
    db.dispose();
    dir.deleteSync(recursive: true);
  });
  return db;
}

/// [r] stored and computed (its section children first); the stored copy.
Future<Recipe> _compute(SaltDatabase db, Recipe r) async {
  db.upsertRecipe(r, sourceSlug: _source, contentHash: contentHashOf(r));
  final stored = db.recipeByIdOrSlug(r.id)!.recipe;
  for (final key in sectionChildKeysOf(db, stored, ResolverMemo(db))) {
    expect(
      await matchAndCompute(db, _fx, nutritionRecipeOf(db, key)!.recipe),
      isNull,
    );
  }
  expect(await matchAndCompute(db, _fx, stored), isNull);
  return db.recipeByIdOrSlug(r.id)!.recipe;
}

/// [r] with its main line [position]'s raw text and amounts replaced.
Recipe _withLine(Recipe r, int position, String raw, List<Amount> amounts) {
  var at = 0;
  return r.copyWith(
    ingredients: [
      for (final g in r.ingredients)
        g.copyWith(
          items: [
            for (final l in g.items)
              (at++ == position) ? l.copyWith(raw: raw, amounts: amounts) : l,
          ],
        ),
    ],
  );
}

Future<Map<String, Object?>> _child(SaltDatabase db, String id, int at) async {
  final body = await matchesBody(db, _fx, nutritionRecipeOf(db, id)!.recipe);
  jsonEncode(body);
  final item = (body['items']! as List)
      .cast<Map<String, Object?>>()
      .singleWhere((i) => i['position'] == at);
  return (item['match']! as Map<String, Object?>)['child']!
      as Map<String, Object?>;
}

/// [corpus] with the one step sentence [sentence] replaced by [to].
Recipe _stepEdited(Recipe corpus, String sentence, String to) {
  var hits = 0;
  final steps = [
    for (final s in corpus.steps)
      s.text.contains(sentence)
          ? (() {
              hits++;
              return s.copyWith(text: s.text.replaceFirst(sentence, to));
            })()
          : s,
  ];
  expect(hits, 1, reason: sentence);
  return corpus.copyWith(steps: steps);
}

void main() {
  group('v106 (fix106: Run 081/082 U1–U13)', skip: skipIfNoCorpus, () {
    u1();
    u2();
    closer1();
    closer2();
  });
}

/// U1 (LOW ×8; S1 S4 C2 / O1 O2 O5 OC2 OC3): v105's `_negatesSkim` was 18
/// sentence-level substrings — object-blind (a negation of ANOTHER object
/// erased a real skim / pour-off / wipe: v105 regressions at reach 0) and
/// incomplete ('never' / 'no need to' / 'avoid' × pour / spoon / drain off;
/// the discard verb and the wipe arm unguarded). v106: ONE helper,
/// `_forbids(piece, act)` — a negation word, the act's verb, determiners,
/// the act's OWN object — read by `_skimsFatIn` (per arm), `defatsSentence`
/// and every arm of `_panFactsOf`'s `discarded`. Corpus reach 0 (the one
/// negated skim is 0492's, pinned unchanged in nutrition_v101 / v104). Every
/// input below is a STATED synthesized re-text of a real corpus sentence:
/// 1171 bulalo's K1 "Using wide, shallow spoon, skim excess fat from surface
/// of broth.", 0351's step 4 with 0142's real "Pour off and discard fat in
/// skillet." form (the v105 U5 pin's), 0357's real "… and discard the oil
/// left in the skillet.", 0224's real "Using wide, shallow spoon, skim fat
/// from surface and discard."
void u1() {
  const k1 =
      'Using wide, shallow spoon, skim excess fat from surface of broth.';
  Recipe bulalo(String to) => _stepEdited(loadCorpusRecipe(_bulalo), k1, to);

  // S1 / O2: the sibling negations — base true / {0} each.
  for (final negation in [
    'never pour off the fat',
    'there is no need to pour off the fat',
    'avoid pouring off the fat',
    'never spoon off the fat',
    'no need to spoon off the fat',
    'never drain off the fat',
    'refrain from skimming the fat',
    'avoid skimming the fat',
  ]) {
    test('U1: "($negation)" is no skim, no browning fat line', () {
      final e = bulalo(
        'Using wide, shallow spoon, remove the bones ($negation).',
      );
      expect(fatSkimmedOf(e), isFalse);
      expect(browningFatLinesOf(e), isEmpty);
    });
  }

  // S4 / O1 / O5: a negation of ANOTHER object keeps the real skim — base
  // (eb9614c) false / {}, v104 (5e6b4d7) and v106 true / {0}.
  for (final to in [
    'Using wide, shallow spoon, skim excess fat from surface of broth (do not pour off the broth).',
    'Using wide, shallow spoon, skim excess fat from surface of broth (do not pour off the marrow).',
    "Skim excess fat from surface of broth, but don't drain off the liquid.",
    'Skim excess fat from surface of broth without draining off the liquid.',
  ]) {
    test('U1: "$to" skims (the real skim kept)', () {
      final e = bulalo(to);
      expect(fatSkimmedOf(e), isTrue);
      expect(browningFatLinesOf(e), {0});
    });
  }

  Recipe gravy(String pour) {
    final g = loadCorpusRecipe(_gravy);
    final s3 = g.steps[3].text;
    const lift =
        'Transfer the meatballs to a paper towel–lined plate to drain briefly. ';
    const garlic =
        'Stir in the garlic and cook until fragrant, about 30 seconds. ';
    expect(s3, contains(lift));
    return g.copyWith(
      steps: [
        for (final (i, st) in g.steps.indexed)
          i == 3
              ? st.copyWith(text: s3.replaceFirst(lift, '$lift$pour$garlic'))
              : st,
      ],
    );
  }

  // `_panFactsOf`'s `discarded`, every arm (shallowFryLinesOf on 0351 |20:
  // {20} = the fat discarded, {} = reused).
  for (final (pour, lines) in const [
    // the controls (v105 U5's): the real discard, nothing, the negation.
    ('Pour off and discard fat in skillet. ', {20}),
    ('', <int>{}),
    ('Do not pour off the fat in skillet. ', <int>{}),
    // S1 / O2 siblings: base {20}.
    ('Never pour off the fat in skillet. ', <int>{}),
    ('There is no need to pour off the fat in skillet. ', <int>{}),
    // S4 / O1 / O5 mixed: base {} — the real pour-off / wipe kept.
    ('Pour off and discard fat in skillet (do not skim the sauce). ', {20}),
    ('Pour off and discard fat in skillet; do not skim the sauce. ', {20}),
    ('Pour off the fat in skillet (do not drain off the liquid). ', {20}),
    ('Do not drain off the liquid; pour off the fat in skillet. ', {20}),
    ('Wipe out the skillet (do not skim the sauce). ', {20}),
    // the wipe arm: real {20}; OC2 its negation (base {20}).
    ('Wipe out the skillet. ', {20}),
    ('Do not wipe out the skillet. ', <int>{}),
    // the partial reads NO discard (STATED, reach 0; base {} too).
    ('Do not pour off all the fat in skillet. ', <int>{}),
  ]) {
    test('U1: 0351 with "$pour" — shallowFryLinesOf $lines', () {
      expect(shallowFryLinesOf(gravy(pour)), lines);
    });
  }

  // OC2: the discard-verb arm — 0357's REAL sentence discards (|10 shallow);
  // its negation discards nothing (base {10}); a negated discard of
  // ANOTHER object keeps it.
  test('U1: 0357 "do not discard the oil" discards nothing', () {
    const real = 'and discard the oil left in the skillet.';
    final sm = loadCorpusRecipe('0357-spaghetti-and-meatballs.yaml');
    expect(shallowFryLinesOf(sm), {10});
    for (final (to, lines) in const [
      ('and do not discard the oil left in the skillet.', <int>{}),
      (
        'and discard the oil left in the skillet (do not discard the pasta water).',
        {10},
      ),
      (
        'and discard the oil left in the skillet (do not skim the sauce).',
        {10},
      ),
    ]) {
      expect(shallowFryLinesOf(_stepEdited(sm, real, to)), lines, reason: to);
    }
  });

  // C2 / OC3: the third reader — `defatsSentence` (base false on each of
  // the first four).
  test('U1: defatsSentence keeps a real skim beside another negation', () {
    for (final (s, defats) in const [
      (
        'using wide, shallow spoon, skim fat from surface and discard; do not pour off the braising liquid.',
        true,
      ),
      ("skim the fat from the stew and don't pour off the liquid.", true),
      ('skim the fat from the sauce without draining off the liquid.', true),
      ('skim the fat (never skim the sauce).', true),
      ('using wide, shallow spoon, skim fat from surface and discard.', true),
      ('remove the bay leaves (never skim the fat from the liquid).', false),
      (
        'remove the bay leaves (avoid skimming the fat from the liquid).',
        false,
      ),
    ]) {
      expect(defatsSentence(s), defats, reason: s);
    }
  });

  // C2 / OC3 through `braisedKeptOf`: 0224's real step with its skim
  // sentence re-texted AND its "return defatted liquid" read as "return
  // liquid" (STATED: the second defatting sentence would hold the pair on
  // its own) — the defatted-braise pair on 170827 (base null).
  test("U1: 0224's re-texted braise keeps its defatted pair", () {
    final pom = loadCorpusRecipe(
      '0224-braised-brisket-with-pomegranate-cumin-and-cilantro.yaml',
    );
    final flat = nutritionLines(pom)[0].raw;
    expect(braisedKeptOf(flat, 170827, pom), braisedKept[170827]);
    Recipe edited(String skim) => _stepEdited(
      _stepEdited(
        pom,
        'Using wide, shallow spoon, skim fat from surface and discard.',
        skim,
      ),
      'return defatted liquid to pan',
      'return liquid to pan',
    );
    expect(
      braisedKeptOf(
        flat,
        170827,
        edited(
          'Using wide, shallow spoon, skim fat from surface and discard; do not pour off the braising liquid.',
        ),
      ),
      braisedKept[170827],
    );
    expect(
      braisedKeptOf(
        flat,
        170827,
        edited(
          'Using wide, shallow spoon, remove the herbs (do not skim the fat).',
        ),
      ),
      isNull,
    );
  });
}

/// U2 (LOW; S2 / O3): `writesShare` / `_recipeShare` read only `_num`
/// (digits + a vulgar fraction), so '(1/2 recipe)' — the corpus's own
/// `item:` spelling of 0184|3 — '(0.5 recipe)', '(1.5 recipes)' wrote no
/// share and BOTH whole-batch arms read 1.0 (base: auto, 1.0, 1,456.7 g,
/// the GET routed 425.67 kcal), and '(1e9 recipes)' the whole batch for
/// `no_share`. v106: an ASCII fraction and a decimal read; any other
/// numeric-looking token is a written share no reader reads (no share).
/// STATED synthesized (negative path: every corpus `raw:` line writes '½';
/// grep in API.md): 0184 Herb Sauce line 3 "¼ cup Sauce Base (½ recipe;
/// recipe follows)" re-texted — A9 with amounts [count '1'], WB with none.
/// '(0.00001 recipe)' is a share (validShare's (0, 100]: stated).
void u2() {
  const one = [Amount(measure: Measure.count, quantity: '1', primary: true)];
  for (final (arm, amounts) in const [('A9', one), ('WB', <Amount>[])]) {
    for (final (written, share, grams, kcal) in const [
      ('(½ recipe', 0.5, 728.35, 212.83),
      ('(1/2 recipe', 0.5, 728.35, 212.83),
      ('(0.5 recipe', 0.5, 728.35, 212.83),
      ('(1.5 recipes', 1.5, 2185.05, 638.5),
      ('(0.00001 recipe', 0.00001, 0.014567, 0.0),
    ]) {
      final raw = arm == 'WB'
          ? 'Sauce Base $written; recipe follows)'
          : '1 Sauce Base $written)';
      test('U2 $arm: "$raw" reads $share', () async {
        final db = _db();
        final real = loadCorpusRecipe(_herb);
        expect(
          nutritionLines(real)[3].raw,
          '¼ cup Sauce Base (½ recipe; recipe follows)',
        );
        final s = await _compute(db, _withLine(real, 3, raw, amounts));
        final row = db
            .ingredientMatchesFor(s.id)
            .singleWhere((m) => m.position == 3);
        expect((row.status, row.childShare), ('auto', share));
        expect(row.grams, closeTo(grams, 0.0005));
        final child = await _child(db, s.id, 3);
        expect((child['state'], child['kcal']), ('routed', kcal));
      });
    }
    for (final written in const ['(1e9 recipes', '(0 recipe']) {
      final raw = arm == 'WB'
          ? 'Sauce Base $written; recipe follows)'
          : '1 Sauce Base $written)';
      test('U2 $arm: "$raw" is no share', () async {
        final db = _db();
        final s = await _compute(
          db,
          _withLine(loadCorpusRecipe(_herb), 3, raw, amounts),
        );
        final row = db
            .ingredientMatchesFor(s.id)
            .singleWhere((m) => m.position == 3);
        expect(
          (row.status, row.childShare, row.grams, row.gramSource),
          ('confirmed', null, 0.0, 'unmeasured'),
        );
        final child = await _child(db, s.id, 3);
        expect((child['state'], child['reason']), ('not_routed', 'no_share'));
      });
    }
  }
}

/// v106 closer 1 D3: `_skimsFatIn`'s skim arm was a new
/// `\bskim\w*\b[^.]*\bfat\b` regex — quadratic on a long sentence of skim
/// words (Run 064's class; verify1: 54.7 ms at 10k chars, ×4 per doubling)
/// — now two finds per period-free piece (`skimsTheFatForTest`). STATED
/// synthesized inputs (the negative-path exception: an equivalence fuzz and a
/// cost shape cannot come from the corpus), built from the words of 1171
/// bulalo's real K1 "skim excess fat from surface of broth" and 0224's real
/// "skim fat from surface and discard".
void closer1() {
  final regex = RegExp(r'\bskim\w*\b[^.]*\bfat\b');

  test('closer 1 D3: the linear skim arm answers as the regex (fuzz)', () {
    const words = [
      'skim',
      'skimming',
      'skimfat',
      'fat',
      'fats',
      'excess',
      'the',
      'broth',
      '.',
      ';',
      '(do',
      'not',
      'pour',
      'off',
      'fat.',
      'Skim',
    ];
    final rng = Random(106);
    var hits = 0;
    for (var i = 0; i < 4000; i++) {
      final s = [
        for (var j = 0; j < 1 + rng.nextInt(12); j++)
          words[rng.nextInt(words.length)],
      ].join(rng.nextBool() ? ' ' : '');
      final want = regex.hasMatch(s);
      expect(skimsTheFatForTest(s), want, reason: s);
      if (want) hits++;
    }
    // Not vacuous: both answers occur.
    expect(hits, inInclusiveRange(1, 3999));
    expect(
      skimsTheFatForTest('skim excess fat from surface of broth.'),
      isTrue,
    );
    expect(skimsTheFatForTest('fat from surface; skim the broth.'), isFalse);
  });

  // The skim arm's own gate (closer 1: no pin reached it — `_skimsTheFat`'s
  // call dropped SURVIVED every U1 pin): a forbidden pour-off of the fat
  // beside a real skim of it reads the skim. STATED re-text of 1171's K1.
  test('closer 1 D3: a real skim beside a forbidden pour-off skims', () {
    final e = _stepEdited(
      loadCorpusRecipe(_bulalo),
      'Using wide, shallow spoon, skim excess fat from surface of broth.',
      'Using wide, shallow spoon, skim excess fat from surface of broth '
          '(do not pour off the fat).',
    );
    expect(fatSkimmedOf(e), isTrue);
    expect(browningFatLinesOf(e), {0});
  });

  test('closer 1 D3: linear per sentence — the cap shape', () {
    // verify1's shape: a forbidden pour-off, then skim words to the cap.
    String shape(int n) => 'do not pour off the fat ${'skim ' * (n ~/ 5)}';
    int best(String s) {
      var min = 1 << 30;
      for (var k = 0; k < 5; k++) {
        final sw = Stopwatch()..start();
        skimsTheFatForTest(s);
        min = sw.elapsedMicroseconds < min ? sw.elapsedMicroseconds : min;
      }
      return min;
    }

    final small = best(shape(10000));
    final large = best(shape(40000));
    // ×4 the length: linear ≈ ×4, the regex ×16 (verify1: 54.7 → ~870 ms).
    // A clock RATIO (STATED): no step count exists for one regex find.
    expect(large, lessThan(8 * (small + 50)), reason: '$small → $large µs');
    // The reader cap: 120 distinct 10k-char steps through fatSkimmedOf.
    final b = loadCorpusRecipe(_bulalo);
    final capped = b.copyWith(
      steps: [
        for (var i = 0; i < 120; i++)
          b.steps[0].copyWith(
            text: 'Do not pour off the fat $i ${shape(9950)}.',
          ),
      ],
    );
    final sw = Stopwatch()..start();
    expect(fatSkimmedOf(capped), isFalse);
    expect(sw.elapsedMilliseconds, lessThan(backstopMs));
  });
}

/// v106 closer 2 (verify2 D2 / D3): `_skimsFatIn`'s two arms a forbidden
/// skim leaves (the separator, the pour-off) and `_negatedAct`'s qualifiers
/// any / excess / of / off had no pin (each dropped SURVIVED). STATED
/// synthesized re-texts of 1171 bulalo's real K1 "Using wide, shallow
/// spoon, skim excess fat from surface of broth." (corpus reach 0).
void closer2() {
  const k1 =
      'Using wide, shallow spoon, skim excess fat from surface of broth.';
  Recipe bulalo(String to) => _stepEdited(loadCorpusRecipe(_bulalo), k1, to);

  // D2: a forbidden skim beside a real separator / pour-off of the fat
  // reads that arm — base (eb9614c) false / {}.
  for (final to in [
    'Do not skim the fat; pour the broth into a fat separator.',
    'Do not skim the fat; pour off the fat from the broth.',
  ]) {
    test('closer 2 D2: "$to" skims (its other arm)', () {
      final e = bulalo(to);
      expect(fatSkimmedOf(e), isTrue);
      expect(browningFatLinesOf(e), {0});
    });
  }

  // D3: each qualifier between the verb and the object forbids the act.
  for (final negation in [
    'do not pour off any fat',
    'do not pour off excess fat',
    'do not pour off all of the fat',
    'do not skim off the fat',
  ]) {
    test('closer 2 D3: "($negation)" is no skim', () {
      final e = bulalo(
        'Using wide, shallow spoon, remove the bones ($negation).',
      );
      expect(fatSkimmedOf(e), isFalse);
      expect(browningFatLinesOf(e), isEmpty);
    });
  }
}
