#!/bin/zsh
# sw3 (verify3's F7 sweep; no settle step): usage run_sw3.sh <tree-root> <snapshot-copy.db> <workdir> <nshards> [combo-filter]
set -u
T=$1; SRC=$2; D=$3; N=$4; FL=${5:-}; mkdir -p $D
dart compile kernel --packages=$T/.dart_tool/package_config.json ${0:A:h}/sw3.dart -o $D/sw3.dill > $D/compile.log 2>&1 || exit 1
for i in $(seq 0 $((N-1))); do (cd $T/apps/server && dart $D/sw3.dill $SRC $D $i $N $FL > $D/out_$i.log 2>&1) & done
wait; echo DONE > $D/DONE
