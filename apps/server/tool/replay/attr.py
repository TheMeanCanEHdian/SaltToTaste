import sys, re, csv
from collections import Counter
base, new, rbase, rnew = sys.argv[1:5]
def load(p):
    rows = {}
    for r in csv.reader(open(p, newline=''), delimiter='\t', quoting=csv.QUOTE_NONE):
        rows[(r[0], r[1], r[19] if len(r) > 19 else '')] = r  # key: slug, position, the section column (col 20) — never the hold (col 10)
    return rows
A, B = load(base), load(new)
new=[k for k in B if k not in A]; gone=[k for k in A if k not in B]
if new or gone: print(f'KEY SETS DIFFER: new {len(new)} gone {len(gone)} (a batch adding a section adds rows — attribute them by hand)')
for k in list(B):
    if k not in A: B.pop(k)
for k in list(A):
    if k not in B: A.pop(k)
changed = [k for k in A if A[k] != B[k]]
cols = Counter(); kinds = Counter(); sect = pers = 0; dk = 0.0; moves = []
def f(x):
    try: return float(x)
    except: return 0.0
for k in changed:
    a, b = A[k], B[k]
    diff = tuple(i+1 for i in range(max(len(a), len(b))) if (a[i] if i < len(a) else '') != (b[i] if i < len(b) else ''))
    cols[diff] += 1
    if k[2]: sect += 1
    if a[8] != 'auto' or b[8] != 'auto': pers += 1
    raw = a[2]
    gram_moved = a[6] != b[6]
    if not gram_moved: kinds['basis-only'] += 1
    elif '–' in raw: kinds['en dash'] += 1
    elif re.search(r'\d\s*(?:-\s*)?to\s+\d', raw) and not re.search(r'\d-\s*to', raw): kinds['fraction/to'] += 1
    else: kinds['hyphenated'] += 1
    d = f(b[16]) - f(a[16]); dk += d; moves.append((d, k[0], k[1], a[6], b[6]))
    pass  # (an M48-era sanity check, dropped 2026-10-17) assert 'the midpoint' in b[11] or a[6] == b[6] or b[11] == a[11], (k, b[11])
print(f'rows differing: {len(changed)} (grams moved {len(changed)-kinds["basis-only"]}, basis-only {kinds["basis-only"]})')
print('by spelling:', dict(kinds)); print('columns changed (1-based):', dict(cols))
print(f'section rows: {sect}  person rows: {pers}  kcal per batch delta: {dk:.1f}')
moves.sort(); print('largest kcal moves:', [(round(d,1), s, p, g0, g1) for d, s, p, g0, g1 in moves[:5]])
RA = {r[0]: r for r in csv.reader(open(rbase, newline=''), delimiter='\t', quoting=csv.QUOTE_NONE)}
RB = {r[0]: r for r in csv.reader(open(rnew, newline=''), delimiter='\t', quoting=csv.QUOTE_NONE)}
assert RA.keys() == RB.keys()
rc = Counter(); n = 0; st = 0
for k in RA:
    if RA[k] != RB[k]:
        n += 1; rc[tuple(i+1 for i in range(len(RA[k])) if RA[k][i] != RB[k][i])] += 1
        if RA[k][1] != RB[k][1]: st += 1
print(f'recs differing: {n}; columns: {dict(rc)}; status changes: {st}')
