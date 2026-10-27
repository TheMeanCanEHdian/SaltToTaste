#!/bin/zsh
# sw4–sw8: settle a fresh snapshot copy, then sweep it in shards (each shard clones the settled DB).
# usage: run.sh <swN.dart> <tree-root> <snapshot.db> <workdir> <nshards>
set -u
SW=$1; T=$2; SNAP=$3; D=$4; N=$5; mkdir -p $D
dart compile kernel --packages=$T/.dart_tool/package_config.json $SW -o $D/sw.dill > $D/compile.log 2>&1 || { echo "compile failed: $D/compile.log"; exit 1; }
rm -f "${D:?}"/settled.db*
(cd $T/apps/server && dart $D/sw.dill settle $SNAP $D/settled.db) > $D/settle.log 2>&1
sqlite3 $D/settled.db "PRAGMA journal_mode=DELETE" >> $D/settle.log
for i in $(seq 0 $((N-1))); do (cd $T/apps/server && dart $D/sw.dill sweep $D/settled.db $D $i $N > $D/shard_$i.log 2>&1) & done
wait; echo ALLDONE >> $D/settle.log; grep -h SUMMARY $D/sw_*.tsv 2>/dev/null
