#!/bin/zsh
# Compare the LIVE DB with a gate replay: buckets AND the kcal digest. usage digest.sh <gate-dir> [live-db]
R=${0:A:h:h:h:h:h}; T=$R/apps/server/tool/replay; G=$1; LIVE=${2:-$R/apps/server/.data/salt.db}
sqlite3 $LIVE < $T/bucket_v12.sql > $G/bucket_live.out 2>&1
cmp -s $G/bucket_live.out $G/bucket_replay.out && echo "LIVE BUCKETS == REPLAY BUCKETS" || { echo "BUCKETS DIFFER:"; diff $G/bucket_live.out $G/bucket_replay.out | head -12; }
Q='SELECT round(sum(calories_per_serving),2), round(sum(total_grams),2), count(*) FROM recipe_nutrition'
echo "digest live   : $(sqlite3 $LIVE "$Q")"; echo "digest replay : $(sqlite3 $G/rp_main.db "$Q")"
sqlite3 $LIVE "ATTACH '$G/rp_main.db' AS r; SELECT 'rows whose kcal/serving differ by > 0.01: ' || count(*) FROM recipe_nutrition l JOIN r.recipe_nutrition x ON x.recipe_id=l.recipe_id WHERE abs(l.calories_per_serving - x.calories_per_serving) > 0.01;"
