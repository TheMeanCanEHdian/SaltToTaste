#!/bin/zsh
# The series gate replay: usage gate.sh <gate-dir> <snapshot.db> <prev-prefix>
#   <prev-prefix> names the reference TSVs <prev-prefix>_{rows,recs,sections,notes}.tsv
#   (the v82 set: .claude/diag/2026-10-09/v82). Fresh snapshot copies, rp43 main and
#   --reverse-parents, cmp main == rev, cmp against the reference, attribution, buckets.
set -eu; setopt null_glob
R=${0:A:h:h:h:h:h}; T=$R/apps/server/tool/replay; G=$1; SNAP=$2; PREV=$3; PK=$R/.dart_tool/package_config.json
mkdir -p $G
for side in main rev; do
  rm -f $G/rp_$side.db*; cp $SNAP $G/rp_$side.db; sqlite3 $G/rp_$side.db "PRAGMA journal_mode=DELETE" >/dev/null
  extra=""; [ $side = rev ] && extra="--reverse-parents"
  (cd $R/apps/server && dart --packages=$PK $T/rp43.dart $G/rp_$side.db $G/rows_$side.tsv $G/recs_$side.tsv $G/sections_$side.tsv --calls=$G/calls_$side.tsv --notes=$G/notes_$side.tsv $extra) | tee $G/rp_$side.out | tail -3
done
for f in rows recs sections calls notes; do cmp $G/${f}_main.tsv $G/${f}_rev.tsv; done && echo "main == rev (rows, recs, sections, calls, notes)"
for f in rows recs sections calls notes; do cmp $G/${f}_main.tsv ${PREV}_$f.tsv && echo "$f == reference"; done || true
python3 $T/attr.py ${PREV}_rows.tsv $G/rows_main.tsv ${PREV}_recs.tsv $G/recs_main.tsv
sqlite3 $G/rp_main.db < $T/bucket_v12.sql > $G/bucket_replay.out 2>&1
cmp $G/bucket_replay.out ${PREV}_bucket.out && echo "buckets == reference"
