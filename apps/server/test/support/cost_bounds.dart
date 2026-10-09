// The per-family count bounds of RULE C (Run 056 I4/O20): what every
// cost pin checks its stepIndexCounts against, shared by the v25 and v26
// cost files so no pin there is a clock alone.
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
    ])
      once: 1,
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
    ])
      perHead: 3 * heads,
    'memo:says': 6 * heads,
    // Once per line TEXT: 398 identical oil lines read one.
    for (final perText in ['memo:keptOil', 'memo:plusNamed'])
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
