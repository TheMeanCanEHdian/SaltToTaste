import 'package:logging/logging.dart';
import 'package:salt_server/src/config.dart';
import 'package:salt_server/src/db/salt_database.dart';
import 'package:salt_server/src/services/library_io.dart';
import 'package:salt_shared/salt_shared.dart';

final Logger _log = Logger('backfill');

/// Settings key marking the serves backfill as already applied. Its value is
/// the completion timestamp (informational).
const String servesBackfillSetting = 'backfill.serves_vs_yield';

/// One-shot correction for recipes stored before the servings parser learned
/// to tell a YIELD from a SERVING count.
///
/// Those rows carry the yield's number in `serves`: `MAKES 2 LOAVES` became
/// `serves 2` and `MAKES ENOUGH FOR ONE 9-INCH PIE` became `serves 1`. That
/// renders as a false "Serves N" and, worse, seeds the per-serving nutrition
/// basis — so a loaf's calories get reported as a serving's. [parseServings]
/// no longer does this, but existing rows keep the stale value until they are
/// re-saved, which is what this pass does.
///
/// For every recipe whose `serves` disagrees with a fresh parse of its
/// verbatim servings text, rewrites the row (its columns, its JSON doc, and
/// its content hash) and re-exports its canonical YAML. Recipes that parse
/// the same are not touched at all.
///
/// Runs at most once per database, guarded by [servesBackfillSetting].
/// Returns the number of recipes corrected (0 when already applied).
///
/// A hand-edited library file is NOT clobbered: each export passes the
/// recipe's current stored hash, so [exportRecipeYaml] preserves a diverged
/// file as `.conflict-<timestamp>.yaml` exactly as any other edit would.
int backfillServes(SaltDatabase db, ServerConfig config) {
  if (db.getSetting(servesBackfillSetting) != null) {
    return 0;
  }
  final ids = db.allRecipeIds();
  var corrected = 0;
  for (final id in ids) {
    final found = db.recipeByIdOrSlug(id);
    if (found == null) {
      continue; // Deleted between the id scan and here.
    }
    final recipe = found.recipe;
    final fresh = parseServings(recipe.servings);
    if (_sameServes(recipe.serves, fresh)) {
      continue;
    }
    // `serves` must be settable back to null (a bare yield states none), and
    // the generated copyWith reads a null argument as "leave unchanged" — so
    // round-trip through the map to express the absence.
    final map = recipe.toMap();
    map['serves'] = fresh?.toMap();
    final fixed = RecipeMapper.fromMap(map);

    final previousHash = db.contentHashOf(id);
    final canonical = RecipeYamlCodec.encode(fixed);
    db.upsertRecipe(
      fixed,
      sourceSlug: found.sourceSlug,
      contentHash: contentHashOfText(canonical),
    );
    exportRecipeYaml(
      config: config,
      sourceSlug: found.sourceSlug,
      recipeId: id,
      canonical: canonical,
      previousHash: previousHash,
    );
    _log.fine(
      'serves backfill: ${recipe.id} '
      '${_describe(recipe.serves)} -> ${_describe(fresh)} '
      '(${recipe.servings})',
    );
    corrected += 1;
  }
  db.setSetting(
    servesBackfillSetting,
    DateTime.now().toUtc().toIso8601String(),
  );
  if (corrected > 0) {
    _log.info(
      'serves backfill: corrected $corrected of ${ids.length} recipes whose '
      'yield had been stored as a serving count',
    );
  }
  return corrected;
}

bool _sameServes(Serves? a, Serves? b) {
  if (a == null || b == null) {
    return a == null && b == null;
  }
  return a.min == b.min && a.max == b.max;
}

String _describe(Serves? serves) =>
    serves == null ? 'none' : '${serves.min}-${serves.max}';
