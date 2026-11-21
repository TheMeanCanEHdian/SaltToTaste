#!/bin/zsh
# tool/replay/panel_digest.sh (v123, batch PB1): the label's whole panel on two replayed databases.
# usage: panel_digest.sh [--stamp same|bumped] <a.db> <b.db> [moving-key ...]
#   (default moving key: none — every key must be identical)
# READS: the two databases' recipe_nutrition (each opened file:...?mode=ro). NEVER WRITES: anything but stdout and two
#   mktemp files it removes on exit. Never point it at snapshot 33 or snap33w in place unless read-only is enough (it is).
# PRINTS (1) per side the library sum of every totals key (key, sum at 4 dp, ids carrying it);
#   (2) every (recipe_id, key) whose totals value (T) or nutrients per-serving amount (S) differs;
#   (3) the ids whose totals / nutrients JSON differs OUTSIDE the moving keys, or whose serving_basis,
#       calories_per_serving, total_grams, matched_count, total_count, status, layout_seq or computing differs
#       (computed_at excluded; ingredients_hash excluded — it is (3c));
#   (3b) the ids on one side only;
#   (3c) THE STAMP on its own line: the ids whose ingredients_hash differs, of the ids both sides hold.
#       ingredientsHashOf (engine.dart) hashes a payload whose first key is matcherVersion, so the stamp differs on
#       EVERY id when the two trees' matcherVersion differ (G1 -> G2, G0 -> G3 across PB1's bump) and on NONE when they
#       match (G0 -> G1). --stamp bumped expects every id; --stamp same expects none; without --stamp it is reported only.
# EXIT: 0 = (3) is 0, (3b) is 0 / 0 and, when --stamp is given, (3c) matches it; 1 = any of those fails; 2 usage.
set -eu
STAMP=""
if [ "${1:-}" = "--stamp" ]; then STAMP=${2:-}; shift 2; fi
if [ $# -lt 2 ] || { [ -n "$STAMP" ] && [ "$STAMP" != same ] && [ "$STAMP" != bumped ]; }; then
  sed -n '2,18p' $0 >&2; exit 2
fi
A=$1; B=$2; shift 2; MOV=("$@")
for f in $A $B; do [ -f $f ] || { echo "no such database: $f" >&2; exit 2; }; done
RM_A="r.totals"; RM_B="x.totals"; RN_A="r.nutrients"; RN_B="x.nutrients"
for k in $MOV; do RM_A="json_remove($RM_A,'\$.$k')"; RM_B="json_remove($RM_B,'\$.$k')"; RN_A="json_remove($RN_A,'\$.$k')"; RN_B="json_remove($RN_B,'\$.$k')"; done
TA=$(mktemp); TB=$(mktemp); trap 'rm -f $TA $TB' EXIT INT TERM HUP
Q="SELECT j.key, printf('%.4f', SUM(j.value)), count(*) FROM recipe_nutrition r, json_each(r.totals) j GROUP BY j.key ORDER BY j.key"
sqlite3 -separator ' ' "file:$A?mode=ro" "$Q" > $TA; sqlite3 -separator ' ' "file:$B?mode=ro" "$Q" > $TB
print -r -- "-- (1) library sums per totals key (key, sum, ids carrying it): a | b   (* = differs)"
paste -d'|' $TA $TB | awk -F'|' '{print ($1==$2 ? "  " : "* ") $1 " | " $2}'
OUT=$(sqlite3 -separator $'\t' "file:$A?mode=ro" "ATTACH 'file:$B?mode=ro' AS b;
SELECT '-- (2) (recipe_id, key) differing: T|S, id, key, a, b';
SELECT 'T', r.recipe_id, k.key, json_extract(r.totals, '\$.\"' || k.key || '\"'), json_extract(x.totals, '\$.\"' || k.key || '\"')
  FROM recipe_nutrition r JOIN b.recipe_nutrition x USING (recipe_id),
       (SELECT DISTINCT j.key FROM recipe_nutrition r2, json_each(r2.totals) j UNION SELECT DISTINCT j.key FROM b.recipe_nutrition r3, json_each(r3.totals) j) k
 WHERE json_extract(r.totals, '\$.\"' || k.key || '\"') IS NOT json_extract(x.totals, '\$.\"' || k.key || '\"') ORDER BY 2, 3;
SELECT 'S', r.recipe_id, k.key, json_extract(r.nutrients, '\$.\"' || k.key || '\".amount'), json_extract(x.nutrients, '\$.\"' || k.key || '\".amount')
  FROM recipe_nutrition r JOIN b.recipe_nutrition x USING (recipe_id),
       (SELECT DISTINCT j.key FROM recipe_nutrition r2, json_each(r2.nutrients) j UNION SELECT DISTINCT j.key FROM b.recipe_nutrition r3, json_each(r3.nutrients) j) k
 WHERE json_extract(r.nutrients, '\$.\"' || k.key || '\".amount') IS NOT json_extract(x.nutrients, '\$.\"' || k.key || '\".amount') ORDER BY 2, 3;
SELECT 'N3', count(*) FROM recipe_nutrition r JOIN b.recipe_nutrition x USING (recipe_id)
 WHERE $RM_A IS NOT $RM_B OR $RN_A IS NOT $RN_B OR r.serving_basis IS NOT x.serving_basis OR r.calories_per_serving IS NOT x.calories_per_serving
    OR r.total_grams IS NOT x.total_grams OR r.matched_count IS NOT x.matched_count OR r.total_count IS NOT x.total_count
    OR r.status IS NOT x.status OR r.layout_seq IS NOT x.layout_seq OR r.computing IS NOT x.computing;
SELECT 'N3B', (SELECT count(*) FROM recipe_nutrition WHERE recipe_id NOT IN (SELECT recipe_id FROM b.recipe_nutrition)),
  (SELECT count(*) FROM b.recipe_nutrition WHERE recipe_id NOT IN (SELECT recipe_id FROM main.recipe_nutrition));
SELECT 'N3C', (SELECT count(*) FROM recipe_nutrition r JOIN b.recipe_nutrition x USING (recipe_id) WHERE r.ingredients_hash IS NOT x.ingredients_hash),
  (SELECT count(*) FROM recipe_nutrition r JOIN b.recipe_nutrition x USING (recipe_id));")
print -r -- "$OUT" | grep -v '^N3'
N3=$(print -r -- "$OUT" | awk -F'\t' '$1=="N3"{print $2}')
read B1 B2 <<< "$(print -r -- "$OUT" | awk -F'\t' '$1=="N3B"{print $2, $3}')"
read C1 C2 <<< "$(print -r -- "$OUT" | awk -F'\t' '$1=="N3C"{print $2, $3}')"
print -r -- "-- (3) ids differing outside the moving keys (must be 0): $N3"
print -r -- "-- (3b) ids on one side only (must be 0 / 0): $B1 / $B2"
print -r -- "-- (3c) THE STAMP: ids whose ingredients_hash differs: $C1 of $C2 common ids${STAMP:+ (expected: $STAMP)}"
rc=0
[ "$N3" = 0 ] || rc=1
[ "$B1" = 0 ] && [ "$B2" = 0 ] || rc=1
if [ "$STAMP" = same ] && [ "$C1" != 0 ]; then print -r -- "   STAMP FAIL: expected none to differ"; rc=1; fi
if [ "$STAMP" = bumped ] && [ "$C1" != "$C2" ]; then print -r -- "   STAMP FAIL: expected every id to differ"; rc=1; fi
print -r -- "-- verdict: $([ $rc = 0 ] && echo PASS || echo FAIL)"
exit $rc
