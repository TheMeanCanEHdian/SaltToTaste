/// The composite row on the wire (v41, design_v3 §2.3; api_app §1, §4,
/// §5): a reference line's `child`, a rendered row's `parts`, and the
/// label's `includes` / `partial` — one builder for the matches GET, the
/// nutrition GET and the review queue.
library;

import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/nutrition/engine.dart';
import 'package:salt_server/src/nutrition/grams.dart';
import 'package:salt_shared/salt_shared.dart';

/// The holds of a reference line (`choose_recipe`, `nested_recipe`,
/// `discarded_recipe`): LINE holds, decided in their recipe only (A2).
final List<String> recipeLineHolds = holdsOf({HoldKind.recipe});

double _round2(double v) => double.parse(v.toStringAsFixed(2));

/// `child` of a match (v41): what a sub-recipe reference line is made from,
/// or null when [line] is no reference the engine reads as one (the
/// sub-recipe gate, [subRecipeRowFor]) or [row] stands on a food (a "plus"
/// part, a person's food pick on the line's alternative, A10). `state`:
/// `routed` (counted from a library recipe), `held` (a recipe hold:
/// `reason` `missing` | `generic` | `nested` | `marinade`) or `not_routed`
/// (the 0 g rule row: `reason` `section` | `served_with` | `no_amount` |
/// `no_share` | v47 `self` — a section's line naming its own host).
/// [slim] (the review queue, F14): `state`, `reason`, `name`,
/// `title`, `slug`, `default`, `why`, `share_text` — never `candidates`.
/// Every library read goes through [memo] (one per request).
///
/// v44 (sections as children, P3 §3): a SECTION child keeps `slug` = its
/// host's slug and `title` = the section's title, and adds `section` (the
/// title, read from the stored key — a section gone since, S15, still names
/// its old title) and `host_title` (the host's title only when the host is
/// ANOTHER recipe; null for an own section and a library child); not
/// routed for a section with no ingredient lines: `reason`
/// `no_ingredients`.
Map<String, Object?>? referenceChildJson(
  SaltDatabase db,
  Recipe recipe,
  int position,
  IngredientLine line,
  IngredientMatchRow row,
  ResolverMemo memo, {
  bool slim = false,
}) {
  if (row.fdcId != null || subRecipeRowFor(recipe, position, line) == null) {
    return null;
  }
  ReferenceResolution? resolution;
  ReferenceResolution found() =>
      resolution ??= resolveReference(db, recipe, line, memo);
  final hold = row.hold;
  final String state;
  final String? reason;
  if (recipeLineHolds.contains(hold)) {
    state = 'held';
    reason = switch (hold) {
      nestedRecipeHold => 'nested',
      discardedRecipeHold => 'marinade',
      // A decided row whose child is gone keeps its child's id (N6).
      _ =>
        row.childRecipeId != null ||
                (found().kind == ReferenceKind.held && found().missing)
            ? 'missing'
            : 'generic',
    };
  } else if (row.childRecipeId != null) {
    state = 'routed';
    reason = null;
  } else {
    state = 'not_routed';
    reason = switch (found().kind) {
      ReferenceKind.section when found().noIngredients => 'no_ingredients',
      ReferenceKind.section => 'section',
      ReferenceKind.servedWith => 'served_with',
      ReferenceKind.self => 'self',
      ReferenceKind.noAmount => 'no_amount',
      ReferenceKind.noShare => 'no_share',
      _ => null,
    };
  }
  final childId =
      row.childRecipeId ?? (state == 'not_routed' ? found().childId : null);
  final child = childId == null ? null : nutritionRecipeOf(db, childId)?.recipe;
  // The section the child is (v44): its stored key, else the prose section
  // a not-routed row names (no child id: nothing to count).
  final sectionKey = switch ((childId, state)) {
    (final id?, _) when hostOf(id) != id => id,
    (null, 'not_routed') => switch (found().section) {
      (:final host, :final title) => sectionKeyOf(host, title),
      null => null,
    },
    _ => null,
  };
  final sectionHost = sectionKey == null ? null : hostOf(sectionKey);
  final hostRecipe = sectionHost == null
      ? null
      : sectionHost == recipe.id
      ? recipe
      : memo.hostRecipe(sectionHost);
  final share =
      row.childShare ?? parseShare(line.raw, line.amounts, child?.servings);
  final isDefault = isDefaultRoute(db, recipe, line, row, memo);
  final slimJson = <String, Object?>{
    'state': state,
    'reason': reason,
    'name': referenceNameOf(line),
    'slug': child?.slug ?? hostRecipe?.slug,
    'title': child?.title ?? sectionKey?.substring(sectionHost!.length + 1),
    'section': sectionKey?.substring(sectionHost!.length + 1),
    'host_title': sectionHost == null || sectionHost == hostOf(recipe.id)
        ? null
        : hostRecipe?.title,
    'share_text': share == null ? null : shareText(share),
    'default': isDefault,
    // The fix sheet's why line (A4, F12): "(default)" on a flagged default
    // only; an exact or note-named route has none.
    'why': isDefault ? 'default' : 'none',
  };
  if (slim) {
    return slimJson;
  }
  final basis = db.nutritionFor(recipe.id)?.servingBasis ?? 1;
  final childNutrition = childId == null ? null : db.nutritionFor(childId);
  double? kcalOf(RecipeNutritionRow? nutrition) =>
      nutrition == null ? null : batchTotalsOf(nutrition)['energy'] ?? 0;
  final kcal = state == 'routed' && share != null && childNutrition != null
      ? kcalOf(childNutrition)! * share
      : null;
  final measure = yieldMeasureOf(child?.servings);
  final parentWords = recipe.title
      .toLowerCase()
      .split(RegExp('[^a-z]+'))
      .where((w) => w.isNotEmpty);
  final named = noteNamedTitles(recipe, referenceItemOf(line), memo);
  final candidates = [
    for (final candidate in referenceCandidates(recipe, line, memo))
      if (candidate.recipe case final library?)
        () {
          final picked = nutritionRecipeOf(db, library.id)?.recipe;
          final nutrition = db.nutritionFor(library.id);
          final batch = kcalOf(nutrition);
          final lineShare = parseShare(
            line.raw,
            line.amounts,
            picked?.servings,
          );
          final current = library.id == row.childRecipeId && state != 'held';
          return {
            'group': candidate.group,
            'slug': library.slug,
            'title': library.title,
            'section': null,
            'note': switch (candidate.group) {
              'note_named' => 'named ${_ordinal(candidate.rank!)}',
              'similar' when named.isNotEmpty => 'not named in the note',
              _ => null,
            },
            'yield_text': picked?.servings,
            'kcal': batch == null ? null : _round2(batch),
            'kcal_per_serving': batch == null || lineShare == null
                ? null
                : _round2(batch * lineShare / basis),
            'current': current,
            'default': current && isDefault,
            'state': null,
            // A recipe with stored totals (the PUT refuses one without);
            // v47 (F8): never on a SECTION's own line (one level is read).
            'pickable': hostOf(recipe.id) == recipe.id && nutrition != null,
            'host_title': null,
          };
        }()
      else
        _sectionCandidateJson(
          db,
          recipe,
          line,
          row,
          memo,
          candidate,
          basis: basis,
          held: state == 'held',
          isDefault: isDefault,
        ),
  ];
  return {
    ...slimJson,
    'yield_text': child?.servings,
    'share': share,
    'yield_units': [
      if (child != null) {'unit': 'recipe', 'per_recipe': 1},
      if (measure != null)
        {'unit': measure.unit, 'per_recipe': measure.quantity},
    ],
    'grams': row.grams,
    'kcal': kcal == null ? null : _round2(kcal),
    'kcal_per_serving': kcal == null ? null : _round2(kcal / basis),
    'status': childNutrition?.status,
    'matched_count': childNutrition?.matchedCount,
    'total_count': childNutrition?.totalCount,
    // {kind}: the item's last word ("double-crust pie dough": dough).
    'kind': referenceItemOf(line).split(' ').last,
    // {parent kind} (A4, F12): pie, tart or quiche, else recipe.
    'parent_kind': switch (parentWords.lastOrNull) {
      final word? when const {'pie', 'tart', 'quiche'}.contains(word) => word,
      _ => 'recipe',
    },
    'candidates': candidates,
  };
}

/// A section candidate on the wire (v44, P3 §3.1): `slug` its host's,
/// `title` and `section` its title, its yield, stored batch energy and the
/// line's share of it like a library candidate's, `host_title` only for
/// ANOTHER host's section, and `state` — `no_ingredients` (a prose
/// variation: never counted), `nested` (it holds a reference itself; a
/// pick is stored held, as a nested library child), `ready` (stored
/// totals) or `no_totals` (a child section not computed yet — until its
/// sweep). `pickable`: lines and stored totals, what the PUT accepts — on
/// a host's line only (v47, F8).
Map<String, Object?> _sectionCandidateJson(
  SaltDatabase db,
  Recipe recipe,
  IngredientLine line,
  IngredientMatchRow row,
  ResolverMemo memo,
  ReferenceCandidate candidate, {
  required int basis,
  required bool held,
  required bool isDefault,
}) {
  final hostId = candidate.hostId!;
  final title = candidate.section!;
  final own = hostId == recipe.id;
  final host = own ? recipe : memo.hostRecipe(hostId);
  final key = sectionKeyOf(hostId, title);
  final section = host == null ? null : sectionOf(host, key);
  final lines = section == null
      ? const <IngredientLine>[]
      : nutritionLines(section);
  final nutrition = db.nutritionFor(key);
  final batch = nutrition == null
      ? null
      : batchTotalsOf(nutrition)['energy'] ?? 0;
  final lineShare = parseShare(line.raw, line.amounts, section?.servings);
  final current = key == row.childRecipeId && !held;
  return {
    'group': candidate.group,
    'slug': host?.slug,
    'title': title,
    'section': title,
    'note': candidate.group == 'other_section'
        ? 'a section of ${candidate.hostTitle}'
        : null,
    'yield_text': section?.servings,
    'kcal': batch == null ? null : _round2(batch),
    'kcal_per_serving': batch == null || lineShare == null
        ? null
        : _round2(batch * lineShare / basis),
    'current': current,
    'default': current && isDefault,
    'state': lines.isEmpty
        ? 'no_ingredients'
        : lines.any((l) => isReferenceIn(section!, l))
        ? 'nested'
        : nutrition == null
        ? 'no_totals'
        : 'ready',
    // v47 (F8, Run 061 S7): never on a SECTION's own line — one level is
    // read, the PUT refuses every pick there.
    'pickable':
        hostOf(recipe.id) == recipe.id && lines.isNotEmpty && nutrition != null,
    // Never the host of the line in hand (a section's own host, F8).
    'host_title': hostId == hostOf(recipe.id) ? null : candidate.hostTitle,
  };
}

String _ordinal(int rank) => switch (rank) {
  0 => 'first',
  1 => 'second',
  2 => 'third',
  3 => 'fourth',
  4 => 'fifth',
  _ => '${rank + 1}th',
};

/// `parts` of a match (v41, R2): a rendered row's two records — the cooked
/// bacon (`role` `cooked`) and the fat kept in the pan (`kept_fat`) — each
/// with its grams; `[]` on every other row.
List<Map<String, Object?>> partsJson(
  SaltDatabase db,
  IngredientMatchRow row,
) => [
  if (row.gramSource != GramSource.override.name)
    for (final (at, part) in partsOf(row.parts).indexed)
      () {
        final food = knownFood(db, part.fdcId);
        return {
          'fdc_id': part.fdcId,
          'description': food?.description,
          'data_type': food?.dataType,
          'grams': part.grams,
          'role': at == 0 ? 'cooked' : 'kept_fat',
        };
      }(),
];

/// `includes` and `partial` of `GET …/nutrition` (v41, api_app §4): the
/// child recipes the totals count (`{slug, title, flag}`, `flag`
/// "approximation" when the row carries one), and every line that makes the
/// label partial for a reference: `held` (a recipe hold not yet decided),
/// `child_partial` (a counted child that is partial: its `title`,
/// `matched`, `total`), `not_routed` (R3's 0 g row: its `reason`). Stored
/// rows on their own lines, skipped ones left out; in line order. [memo]:
/// the request's resolver reads.
({List<Map<String, Object?>> includes, List<Map<String, Object?>> partial})
referenceSummary(
  SaltDatabase db,
  Recipe recipe,
  List<IngredientMatchRow> rows,
  ResolverMemo memo,
) {
  final lines = nutritionLines(recipe);
  final includes = <Map<String, Object?>>[];
  final partial = <Map<String, Object?>>[];
  for (final row in [...rows]..sort((a, b) => a.position - b.position)) {
    if (row.status == 'skipped' || row.position >= lines.length) {
      continue;
    }
    final line = lines[row.position];
    if (line.raw != row.raw) {
      continue;
    }
    final routed = row.childRecipeId != null && row.hold == null;
    final held =
        recipeChoiceHolds.contains(row.hold) ||
        (row.hold == discardedRecipeHold && row.status == 'auto');
    final notRouted =
        row.fdcId == null &&
        row.status == 'confirmed' &&
        row.description == subRecipeNote;
    if (!routed && !held && !notRouted) {
      continue;
    }
    final child = referenceChildJson(
      db,
      recipe,
      row.position,
      line,
      row,
      memo,
      slim: true,
    );
    if (routed) {
      final stored = db.nutritionFor(row.childRecipeId!);
      if (stored == null || row.childShare == null) {
        continue;
      }
      includes.add({
        'slug': child?['slug'],
        'title': child?['title'],
        // v44: a section child's title and its host's (another host only).
        'section': child?['section'],
        'host_title': child?['host_title'],
        'flag': compositeFlagOf(db, recipe, line, row, memo) == null
            ? null
            : 'approximation',
      });
      if (stored.status != 'complete') {
        partial.add({
          'position': row.position,
          'kind': 'child_partial',
          'name': child?['name'],
          'title': child?['title'],
          'matched': stored.matchedCount,
          'total': stored.totalCount,
          'reason': null,
        });
      }
      continue;
    }
    partial.add({
      'position': row.position,
      'kind': held ? 'held' : 'not_routed',
      'name': child?['name'] ?? referenceNameOf(line),
      'title': child?['title'],
      'matched': null,
      'total': null,
      'reason': child?['reason'],
    });
  }
  return (includes: includes, partial: partial);
}
