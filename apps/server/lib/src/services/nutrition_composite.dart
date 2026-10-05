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
/// `no_share`). [slim] (the review queue, F14): `state`, `reason`, `name`,
/// `title`, `slug`, `default`, `why`, `share_text` — never `candidates`.
/// Every library read goes through [memo] (one per request).
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
      ReferenceKind.section => 'section',
      ReferenceKind.servedWith => 'served_with',
      ReferenceKind.noAmount => 'no_amount',
      ReferenceKind.noShare => 'no_share',
      _ => null,
    };
  }
  final childId =
      row.childRecipeId ?? (state == 'not_routed' ? found().childId : null);
  final child = childId == null ? null : db.recipeByIdOrSlug(childId)?.recipe;
  final share =
      row.childShare ?? parseShare(line.raw, line.amounts, child?.servings);
  final isDefault = isDefaultRoute(db, recipe, line, row, memo);
  final slimJson = <String, Object?>{
    'state': state,
    'reason': reason,
    'name': referenceNameOf(line),
    'slug': child?.slug,
    'title': child?.title,
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
          final picked = db.recipeByIdOrSlug(library.id)?.recipe;
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
            // A recipe with stored totals (the PUT refuses one without).
            'pickable': nutrition != null,
            'host_title': null,
          };
        }()
      else
        {
          'group': candidate.group,
          'slug': null,
          'title': candidate.section,
          'note': candidate.group == 'other_section'
              ? 'a section of ${candidate.hostTitle}'
              : null,
          'yield_text': null,
          'kcal': null,
          'kcal_per_serving': null,
          'current': false,
          'default': false,
          // Sections are phase 2: listed, never picked (D6).
          'pickable': false,
          'host_title': candidate.hostTitle,
        },
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
/// rows on their own lines, skipped ones left out; in line order.
({List<Map<String, Object?>> includes, List<Map<String, Object?>> partial})
referenceSummary(
  SaltDatabase db,
  Recipe recipe,
  List<IngredientMatchRow> rows,
) {
  final lines = nutritionLines(recipe);
  final memo = ResolverMemo(db);
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
