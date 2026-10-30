// The per-family count bounds of RULE C (Run 056 I4/O20): what every
// cost pin checks its stepIndexCounts against, shared by the v25 and v26
// cost files so no pin there is a clock alone.
import 'dart:math';

import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/matcher.dart';
import 'package:salt_shared/salt_shared.dart';
import 'package:test/test.dart';

/// Every RULE C clock: a backstop, never the kill (count pins kill) — at
/// least 5× the slowest path the tree measures (797 ms quiet, v26
/// long-lines; Run 057 O12: brine measured 1,554 ms loaded, and a 2,000 ms
/// bound failed on machine load alone at 2,013 and 2,702 ms).
const backstopMs = 10000;

/// The most each counted family may derive on [r]: once per recipe, per
/// head, per step, per sentence, per line, per mention. An unknown family
/// fails ([expectBounded]).
Map<String, int> boundsOf(Recipe r, Map<String, int> c) {
  final lines = nutritionLines(r).length;
  final steps = r.steps.length;
  final sentences = c['sentences'] ?? 0;
  final mentions = c['mentions'] ?? 0;
  final heads =
      {
        for (final l in nutritionLines(r)) normalizeItem(lineItemOf(l)),
      }.length +
      6;
  final texts = {for (final l in nutritionLines(r)) l.raw}.length + 6;
  // The sentences carrying a three-digit run, the only ones a frying-heat
  // check reads in full (the verifier's D2, v26); counted on the written
  // steps, which the scan window only shortens.
  final runs = [
    for (final step in r.steps) ...step.text.split(RegExp(r'(?<=\.)\s+')),
  ].where(RegExp(r'\d\d\d').hasMatch).length;
  // Their characters: each check's governing reading is linear (v28, Run 058
  // S5/S9) — at most twice its sentence.
  final runChars = [
    for (final step in r.steps) ...step.text.split(RegExp(r'(?<=\.)\s+')),
  ].where(RegExp(r'\d\d\d').hasMatch).fold(0, (n, s) => n + s.length);
  return {
    for (final once in [
      'indexes',
      'heads',
      'lower',
      'allSentences',
      'cheese',
      'drained',
      'memo:fries',
      'memo:kept',
      'memo:starter',
      'memo:whey',
      'memo:dunked',
      'memo:brines',
      'memo:milkStep',
      'memo:lastRinse',
      'memo:braise',
      'memo:strain',
      'memo:namingAll',
      'memo:wordHeads',
      'memo:dredges',
      'memo:parting',
      'memo:drained',
      'memo:brineWords',
      'memo:dissolving',
      'memo:brinedByVolume',
      'memo:dredged',
      'memo:dissolveIndex',
      'memo:dissolveItems',
      'memo:plusIndex',
      // v31: the poured-away poach, the first frying verb, the crumb coat.
      'memo:pourAway',
      'memo:fryVerbAt',
      'memo:crumbsForTheCoat',
      // v50 (M50): the strain, its pot and fat; the discards, bundles and
      // printed parts kept; the dips and marinades flagged.
      'memo:strainAt',
      'memo:parenthetical',
      'memo:fatSkimmed',
      'memo:smooth',
      'memo:addsMixture',
      'memo:strainsAnotherPot',
      'memo:discards',
      'memo:bundles',
      'memo:keptCooked',
      'memo:savesRemainder',
      'memo:reservedWhole',
      'memo:measuresOut',
      'memo:leftInBowl',
      'memo:liftedFromMarinade',
      // v50 closer 1: the vegetables lifted out before a strain (V1-D1);
      // the numbered remaining parts (V1-D3).
      'memo:liftsVegetables',
      'memo:remainingParts',
      // v51 (M49): the first pour-off of the pan's fat; rule B1's pan
      // shared with an oil.
      'memo:pourOffFat',
      'memo:baconPan',
      // v53 (M52 Q24 b): the shallow fry of a coated food.
      'memo:shallowFries',
      // v59 (M60, verifier 2 D1/D2): rule B1's kept fat and the bacon that
      // drips; each sentence's paring and cooking acts.
      'memo:baconKept',
      'memo:baconDrips',
      'memo:peelActs',
      // v60 (M61, closer 2): the sentences naming the skin.
      'memo:skinSentences',
      // v61 (M62): an egg or buttermilk dip's lines, read once per base
      // word, never per dip sentence.
      'memo:dips',
      // v61 (M62's baked H shape reaches it first): whether the directions
      // leave an excess of a coat — the shipped v33 reader, once per recipe.
      'memo:leavesExcess',
      // v62 (M64 P10): the counted parts set aside for another use.
      'memo:setsAsidePieces',
      // v65 (M66 closer 1, D1): each line's item's last word — the dip
      // fallback's writers ([_amountWritersOf]'s ownHead), once per recipe.
      'memo:lastWords',
      // v66 (M67 A2): a rolled dough's cut share — the sheet, the count and
      // the cutter read once per recipe.
      'memo:cutShare',
      // v67 (M69 R1, closer 1 — verify1 D3): a step pounding the coated
      // food thin, read once per recipe.
      'memo:poundsThin',
      // v31 (the bread a held breading processes into its crumbs), first
      // met at the caps by M69's coated-vegetable shape (closer 1).
      'memo:processesBread',
      // v70 (review Run 063/064 F1): the giblets' stir gate, read once per
      // index; the host's bird, once per section instance.
      'memo:stirsGiblets',
      'memo:hostBird',
      // v54 (Q25), first met at the caps by v70's giblet section (its wine):
      // the steps' alcohol sentences, once per index.
      'memo:alcoholSentences',
      // v71 (M71): R-H1's prints with its two guards' sentences; R-E2's
      // kept solids; pF R3's fat names in the oil's add-or-combine
      // sentences and whether an oil line fries (closer 2, verify2 D1);
      // D-E1's coat mixtures — each once per index.
      'memo:stepAmounts',
      'memo:keptSolids',
      'memo:fatsIntoOil',
      'memo:friesOil',
      'memo:coatMixes',
      // v71 closer 1 (verify1 D2): whether any line could be a coat — the
      // D-E1 gate's first test.
      'memo:mayHoldCoat',
      // v72 (M72 R-E3): the braised pairs' gate — a step sentence skimming
      // fat, a fat separator, a defatted liquid — once per index.
      'memo:defatsLiquid',
      // v74 (M74, the owner's Q1 (b)): a step trimming a brisket's fat to a
      // printed depth — once per index.
      'memo:trimsFatTo',
      // v75 (M78, the owner's Q7 (c)): the fat lines a sauté heats between
      // the first coat sentence and the first pour-off or wipe — once per
      // index.
      'memo:panFatLines',
      // v96 (M94): the fat lines a browning heats before the first skim or
      // plain pour-off of fat — once per index.
      'memo:browningFat',
      // v76 (M79, Q10 (b′)): the dry-heat cooking a rack's pair reads —
      // grill, or oven and a fat pour-off — once per index.
      'memo:dryHeat',
      // v81 (review Run 065/066 F10): whether the steps strain or discard a
      // zest — once per index.
      'memo:zestStrained',
      // v81 (review Run 065/066 F7): the sentences naming a coat line — once
      // per index.
      'memo:coatLineSentences',
      // v81 (review Run 065/066 F2): the alcohol reader's text facts and its
      // recipe-level reads — each once per index.
      'memo:alcoholTexts',
      'memo:alcoholRecipe',
      // v82 (review Run 067/068 F3): each step's last drain and last rinse
      // sentence — once per index.
      'memo:rinseTails',
      // R3 (simplification ledger L8-5): whether a sentence coats the food
      // with crumbs (v33, [_crumbLineOfTheCoat]) — once per index.
      'memo:coatsWithCrumbs',
      // v85 (M83 B5): the lines carrying each item word, the own-word
      // fallback's "no other line" test — once per index.
      'memo:itemWords',
    ])
      once: 1,
    // v82 (review Run 067/068 F8): the M52 keys built — the request's plan
    // and each decided coat, dip or oil row a derivation keys (a confirm
    // that keys alike in O(1) builds none), at most four passes a line.
    'm52Keys': 4 * lines + 8,
    // v82 (review Run 067/068 F1, F2): the last sentence a tail guard reads
    // — the strain's solids once per index, the reserved fat's heat once
    // per frying fat's owners (oil, shortening, lard).
    'lastMatching': 4,
    // v81 (F2): each text the alcohol reader reads, its facts built once —
    // a sentence, its side-stripped form, a prefix before a stop and a
    // suffix after an offset at most twice each, and an adding sentence's
    // tail per line.
    'alcoholTexts': 8 * sentences + 2 * lines + 8,
    // v81 (F2): its recipe-level reads, once per key — a candidate's
    // mentions, a group's, a name's uses, part mentions, sharing lines and
    // the uses other groups leave (at most 8 a line), the last hand-off and
    // the mixture words.
    'alcoholRecipeReads': 8 * lines + 2,
    // v81 (F2): a run that reaches a state another run read takes what
    // follows it — at most once per run, a line's runs at most 4.
    'alcoholRunsShared': 4 * lines,
    // v81 (F2): the sentences the runs read themselves (the run memo's
    // RESIDUAL — count-pinned exactly by nutrition_v81_test's cap shapes;
    // unbounded sharing cannot be proved, so the bound is a line's runs
    // over every sentence).
    'alcoholRunSentences': 4 * lines * max(sentences, 1),
    // closer 2 (verify2 D1): the hash gate's TRUE path — a note folded by
    // its own text (no step read) — once per hash, a path hashing at most
    // four times (closer 1's `prepNoteScans`, the step scan, is gone).
    'prepNoteFolds': 4,
    // v81 closer 5 (verify5 D3): rule PV's choice of base, once per prose
    // section a hash reads (each named by a line text) and hash; each line's
    // share of it once per line and hash (the residual) — a path hashing at
    // most four times. Pinned EXACTLY by nutrition_v81_test's PROSE shape.
    'proseChoices': 4 * texts,
    'proseShares': 4 * lines,
    // v71 closer 1 (verify1 D2): the D-E1 mixing test, once per sentence
    // whichever reader asks (`memo:mixes`, each test counted `mixTests`);
    // the lines the coat-mixture pass reads, once per index.
    'memo:mixes': sentences,
    'mixTests': sentences,
    // v71 closer 2 (verify2 D1): pF R3's add-or-combine sentences in a step
    // naming the oil, each read once per index (`memo:fatsIntoOil`).
    'fatsIntoOilReads': sentences,
    'coatMixLines': lines,
    // v75 (M78): each fat line's mentions read once per index by the pan-fat
    // reader (`memo:panFatLines`).
    'panFatLineReads': lines,
    // v96 (M94): each fat line's mentions read once per index by the
    // browning-fat reader (`memo:browningFat`).
    'browningFatLineReads': lines,
    // v71 (M71 R-H1, pF R2): a line's scope, once per group heading and
    // once for every step.
    'memo:labelScope': r.ingredients.length + 1,
    // v71 (M71 R-H1): each amount-less line's prints, once per line; their
    // weighing once per line and record (a compute's old and new one).
    'memo:stepAmountsAt': lines,
    'memo:stepAmountGrams': 2 * lines,
    // v92 (M89): the counted repeats `_repeatsOf` finds — each sentence of a
    // step holding a print read once per index (`memo:stepAmounts`).
    'repeats': sentences,
    // v71 closer 1 (verify1 D1): the prints R-H1 indexes — one per match
    // of a unit amount, so at most one per character of the steps — and
    // the prints the read lines walk: each print is filed under at most
    // four of its words, a form is at most three heads' ("tomato",
    // "tomatoe", "tomatoes"), and a head's walking lines read disjoint
    // steps (tier i: one line of a head per scope; the scopes are the
    // labels' disjoint steps). The cap shape pins both exactly (v26
    // review71).
    'stepPrints': r.steps.fold(0, (n, s) => n + s.text.length),
    // v71 closer 3 (verify3 D1): pF R2's reserved spoonfuls — one per match,
    // so at most one per character of the steps for each of the four fat
    // heads; their scoped sum once per fat head and scope (each group
    // heading, and every step), each scope walking its own hits — the
    // labels' steps are disjoint, so a hit is walked by its label's scope
    // and the every-step scope at most.
    'reservedHits': 4 * r.steps.fold(0, (n, s) => n + s.text.length),
    'memo:reservedUseIn': 4 * (r.ingredients.length + 1),
    'reservedHitsRead': 2 * (c['reservedHits'] ?? 0),
    'stepPrintsWalked': 12 * (c['stepPrints'] ?? 0),
    // v54 (Q25): an alcohol line's reading, once per position and record —
    // a row's record, and a compute's old and new one at most.
    'memo:alcohol': 2 * lines,
    // v51 (M49): the oil a pour-off cuts, per pour-off sentence — the first
    // fat pour-off's and rule B1's (at most two per index).
    'memo:panOil': 2,
    for (final perHead in [
      'memo:naming',
      'memo:named',
      'memo:dredgeNamed',
      'memo:rinsedCure',
      'memo:amountWriters',
      'memo:oilOwners',
      'memo:eaten',
      'memo:eatenParts',
      'memo:eatenUnwritten',
      'memo:eatenOrder',
      'memo:mentions',
      'memo:shares',
      'memo:firstShare',
      'names',
      'memo:dissolvingWith',
      'memo:dissolvedWith',
      'memo:plusSteps',
      // v31: a fat's pieces after its last discard.
      'memo:eatenAfterDiscard',
      // v50 (M50): a head's food mentions, named after the strain, drained
      // before it; a count line's partition (per head and discard step —
      // one discard per head on every corpus line).
      'memo:foodNaming',
      'memo:namedAfterStrain',
      'memo:drainedBeforeStrain',
      'memo:partition',
      // v59 (M60 P7a, verifier 2 D2): a head's paring reading.
      'memo:paredIn',
      // v61 (M62): the coat's shape, once per coated record.
      'memo:coatShape',
      // v67 (M69 R2, closer 1 — verify1 D2): whether a coat sentence names a
      // vegetable's head.
      'memo:coatNamed',
      // v70 (review Run 063 F2/F3): the one line a set-aside half takes from.
      'memo:setAsideLine',
      // v71 (M71 pF R2): a fat head's reserved spoonfuls and remainders.
      'memo:reservedUse',
      'memo:remainingFat',
      // v81 (review Run 065/066 F13): whether a can's head is added with
      // its liquid.
      'memo:canLiquid',
      // v81 (review Run 065/066 F4): whether a frying sentence names a fried
      // class's word (with the oil for a vegetable).
      'memo:friedNamed',
    ])
      perHead: 3 * heads,
    'memo:says': 6 * heads,
    // Once per line TEXT: 398 identical oil lines read one.
    for (final perText in [
      'memo:keptOil',
      'memo:plusNamed',
      // v82 (review Run 067/068 F3): whether the steps rinse a plus part off,
      // once per lead amount and head.
      'memo:rinsedOff',
      // v82 (review Run 067/068 F10): R2's lean-only record bought, once per
      // line text and record while no FDC cache write lands.
      'leanOnlyReads',
      // v82 closer 2 (verify2 D5): a decision's moves on a line, once per
      // line text and record while no FDC cache write lands.
      'carriedReads',
      // R3 (simplification ledger L8-5): whether a sentence sets a plus
      // line's lead amount of its head out as a dredge's coat (v33), once
      // per lead amount and head.
      'memo:setsOut',
    ])
      perText: 3 * texts,
    'mentions': mentions,
    // v61 (M62 E-w): the dip lines a plan weighs — at most two plans per
    // request (a PUT's confirm and its totals; a pick's own plan weighs no
    // other dip).
    'dipsSized': 2 * lines,
    'lineMentions': 2 * lines,
    'ends': steps,
    'memo:lifted': steps,
    'rawSentences': steps,
    'lifted': steps,
    'hits': 20 * steps,
    'sentences': sentences,
    // The sentences a per-head scan reads one by one: only a head opening
    // on no word character's (v29: every other head visits the words).
    'namingReads': 3 * heads * sentences,
    // The steps' words, indexed once per step (v29, Run 059 O9): at most
    // one per character.
    'words': r.steps.fold(0, (n, s) => n + s.text.length),
    // Per such sentence: the fries check's three fats, then each head's
    // owners once.
    'heatChecks': 6 * runs,
    // Its reading built once, whichever fats and callers read it (v29, Run
    // 059 S15): four whole-sentence passes, two per fat (three fats), and
    // each of six checks' pointer steps at most once per list entry.
    'memo:heatReading': runs,
    'heatClauseChars': (4 + 2 * 3 + 6) * runChars,
    'memo:drainedLater': sentences,
    'memo:parted': 2 * sentences,
    'memo:sugarBeside': sentences,
    // Each group of each kind once per detector family (6 read them).
    'memo:firstOwn': 6 * 3 * (mentions + 1),
    'mentionVisits': 6 * mentions + 2 * lines,
    'eatenParses': 2 * sentences,
    // The inverted name indexes (v27): each text read once per index — the
    // dissolving sentences once, the steps once.
    'occurrenceScans': sentences + steps,
    'windowLogs': steps,
    // v73 closer 3 (M76 verify3 D1), closer 4 (verify4 D2) and closer 5
    // (verify5 D2): the yield-named own section's per-line reads, memoised
    // per recipe instance in their own store (never the step index: a
    // recompute reads its stored copy's lines, and memoising on the step
    // index built that copy's index) — a line's mark (by its text) and its
    // share reader (by its text and amounts) once per instance, a child's
    // yield once per line, instance and distinct servings string. Measured
    // EXACTLY on the v26 yield cap shapes, the routing ones (rtail, rtail1)
    // too: compute, GET and recompute each 400 of each family on 400 lines,
    // with v74's step indexes (the recompute 1). Before the memo a compute
    // read a routed line six times (isReferenceIn 3, the resolver's own list
    // 3) and a GET up to five (1 and 4) — over the four this bound once said.
    'memo:yieldMarks': lines,
    'memo:yieldShareReaders': lines,
    'yieldServingsReads':
        lines * {for (final s in r.subsections) s.servings}.length,
  };
}

/// Every family [c] counted is known and within its bound on [r] — times
/// [copies], the decodes of [r] a request made (the reach decodes the
/// recipe it reaches, [reachDecodes]: each is its own index).
void expectBounded(
  Recipe r,
  Map<String, int> c,
  String shape, {
  int copies = 1,
}) {
  final bounds = boundsOf(r, c);
  for (final MapEntry(:key, :value) in c.entries) {
    expect(bounds, contains(key), reason: '$shape: unpinned family $key');
    expect(
      value,
      lessThanOrEqualTo(copies * bounds[key]!),
      reason: '$shape: $key',
    );
  }
}
