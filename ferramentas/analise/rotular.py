import os, sys, glob
D, T = sys.argv[1], sys.argv[2]
temp = [(float(a), float(b), " ".join(r)) for a, b, *r in (l.split() for l in open(T))]
out = []
for p in sorted(glob.glob(f"{D}/*-image.pgm")):
    t = os.path.getmtime(p); lab = "CADASTRO" if t < temp[0][0] else None
    for i, (a, b, d) in enumerate(temp):
        if a - 0.5 <= t <= b + 0.5: lab = f"T{i:02d} {d}"
    out.append((p, lab or "?"))
for p, l in out: print(os.path.basename(p), l)
