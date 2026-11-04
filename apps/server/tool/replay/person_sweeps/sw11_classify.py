# sw11's divergence classes (the Run 073 Sonnet fleet's classify.py, v101 adds 'err' and the per-verb split):
# usage: python3 sw11_classify.py <workdir>  (reads <workdir>/settled.db and sw_*.tsv)
# 'inherit' = only OTHER lines of a picked key differ (the decision reaches them at the next compute);
# 'other' = a touched line differs (U1's class); 'energy-only' = no row differs (here: `calls` > 0 — a pick
# of a move source whose detail no cache holds asks FDC once); 'err' = the sweep step threw.
import glob, sqlite3, sys, collections
w = sys.argv[1]
db = sqlite3.connect(w + '/settled.db')
keys = {}
for rid, pos, k in db.execute('select recipe_id, position, item_key from ingredient_matches'):
    keys[(rid, pos)] = k
cls = collections.Counter()
other = []
for f in glob.glob(w + '/sw_*.tsv'):
    lines = open(f).read().split('\n')
    for i, l in enumerate(lines):
        if l.startswith('ERR'):
            cls['err'] += 1; other.append((l.split('\t')[1], 'err')); continue
        if not l.startswith('DIV'):
            continue
        tag = l.split('\t')[1]
        rid, spec, fp, verb, order = tag.split('|')
        fp = int(fp)
        put = lines[i + 1].split('PUT  ')[1].split(' ')
        cmp_ = lines[i + 3].split('CMP  ')[1].split(' ')
        picked = set()
        if spec[0] == 'o':
            picked.add(int(spec[1:]))
        if verb.startswith('pickOther'):
            picked.add(fp)
        pk = {keys.get((rid, p)) for p in picked}
        dp = {}
        for a, b in zip(put, cmp_):
            if a != b and not a.startswith('E='):
                dp[int(a.split(':')[0])] = (a, b)
        if len(put) != len(cmp_):
            cls['len'] += 1; other.append((tag, 'len')); continue
        if not dp:
            cls['energy-only'] += 1; other.append((tag, 'E', put[-1], cmp_[-1])); continue
        if any(keys.get((rid, p)) in pk and p not in picked for p in dp):
            cls['inherit'] += 1
        else:
            cls['other'] += 1
            other.append((tag, [(p, v) for p, v in dp.items() if not (keys.get((rid, p)) in pk and p not in picked)]))
print(cls)
byverb = collections.Counter()
for o in other:
    byverb[o[0].split('|')[3] + ('|' + o[0].split('|')[4])] += 1
print('touched-line (other) by verb|order:', dict(byverb))
print('touched-line recipes:', len({o[0].split('|')[0] for o in other}))
for want in ['0082-simple-pot-roast|n|0|pickOtherSkip', '0091-home-corned-beef-with-vegetables|n|0|pickOtherSkip']:
    print(want, [o[0] for o in other if want in o[0]][:2])
import collections as C
print(C.Counter((o[0].split("|")[0], o[0].split("|")[3], str([x[0] for x in o[1]]) if isinstance(o[1], list) else o[1]) for o in other).most_common(80))
for o in other[:0]:
    print(o)
