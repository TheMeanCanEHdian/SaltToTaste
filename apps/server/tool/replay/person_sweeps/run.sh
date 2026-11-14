#!/bin/zsh
# sw4–sw13: settle a fresh snapshot copy, then sweep it in shards (each shard clones the settled DB).
# usage: run.sh <swN.dart> <tree-root> <snapshot.db> <workdir> <nshards>
# Fails (exit 1) unless the settle exits 0 with a non-empty settled.db and every shard exits 0 with its SUMMARY.
set -u
SW=$1; T=$2; SNAP=$3; D=$4; N=$5; mkdir -p $D
dart compile kernel --packages=$T/.dart_tool/package_config.json $SW -o $D/sw.dill > $D/compile.log 2>&1 || { echo "compile failed: $D/compile.log"; exit 1; }
rm -f "${D:?}"/settled.db*(N) "${D:?}"/sw_*.tsv(N)  # (N): either glob may match nothing (v108 V12); no earlier run's shard output survives
(cd $T/apps/server && dart $D/sw.dill settle $SNAP $D/settled.db) > $D/settle.log 2>&1 || { echo "settle failed: $D/settle.log"; exit 1; }
[[ -s $D/settled.db ]] || { echo "settle wrote no settled.db: $D/settle.log"; exit 1; }
sqlite3 $D/settled.db "PRAGMA journal_mode=DELETE" >> $D/settle.log || exit 1
pids=(); for i in $(seq 0 $((N-1))); do (cd $T/apps/server && dart $D/sw.dill sweep $D/settled.db $D $i $N > $D/shard_$i.log 2>&1) & pids+=($!); done
bad=0; for p in $pids; do wait $p || (( bad++ )); done; echo ALLDONE >> $D/settle.log
out=($D/sw_*.tsv(N)); (( ${#out} )) || { echo "no shard output in $D: see $D/settle.log and $D/shard_*.log"; exit 1; }
grep -h SUMMARY $out
got=$(cat $out | grep -c '^SUMMARY')
(( bad == 0 && got == N )) || { echo "FAILED: $got of $N SUMMARY lines, $bad shard(s) exited non-zero: see $D/shard_*.log"; exit 1; }
