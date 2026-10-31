#!/usr/bin/env python3
"""Exp3: regras de decisão com cadastro real (dump-real 000-015) contra sondas rotuladas.
Features por par (sonda x imagem do cadastro): NCC por ângulo, ângulo do melhor, blocos locais."""
import glob, os
import numpy as np, cv2

R = __import__("os").path.expanduser("~/")+".cache/instalar-goodix"
def ld(p): return cv2.imread(p, cv2.IMREAD_UNCHANGED)

cad = [ld(f"{R}/dump-real/20261030-170430-{i:03d}-image.pgm") for i in range(16)]
rot = dict(l.split(" ", 1) for l in open(f"{R}/rotulos.txt").read().splitlines())
sondas = []  # (img, é_certo, nome)
for f, lab in rot.items():
    if lab.startswith("T"):
        sondas.append((ld(f"{R}/dump-real/{f}"), "CERTO" in lab, lab))
for d in sorted(os.listdir(f"{R}/coleta-1621")):
    for p in sorted(glob.glob(f"{R}/coleta-1621/{d}/*-image.pgm")):
        sondas.append((ld(p), d == "indicador-direito", f"col {d}"))
print(f"cadastro {len(cad)} | sondas certo {sum(s[1] for s in sondas)} errado {sum(not s[1] for s in sondas)}")

def prep(u8):
    f = cv2.medianBlur(u8.astype(np.float32), 3)
    f = cv2.GaussianBlur(f, (0, 0), 1.0) - cv2.GaussianBlur(f, (0, 0), 4.0)
    return (f - f.mean()) / (f.std() + 1e-9)
C = [prep(x) for x in cad]; S = [prep(s[0]) for s in sondas]
H, W = C[0].shape
ANG = list(range(-30, 31, 3))

def per_angle(a, b, frac=0.6):
    ch, cw = int(H * frac), int(W * frac)
    pad = cv2.copyMakeBorder(b, ch // 2, ch // 2, cw // 2, cw // 2, cv2.BORDER_CONSTANT, value=0)
    out = []
    for ang in ANG:
        Rm = cv2.getRotationMatrix2D((W / 2, H / 2), ang, 1.0)
        ar = cv2.warpAffine(a, Rm, (W, H))
        y0, x0 = (H - ch) // 2, (W - cw) // 2
        r = cv2.matchTemplate(pad, ar[y0:y0 + ch, x0:x0 + cw], cv2.TM_CCOEFF_NORMED)
        _, mx, _, loc = cv2.minMaxLoc(r)
        out.append((mx, ang, loc[0] - cw // 2 - x0, loc[1] - ch // 2 - y0))
    return out

def blocks(a, b, ang, dx, dy, bs=12):
    Rm = cv2.getRotationMatrix2D((W / 2, H / 2), ang, 1.0); Rm[0, 2] += dx; Rm[1, 2] += dy
    aw = cv2.warpAffine(a, Rm, (W, H)); m = cv2.warpAffine(np.ones_like(a), Rm, (W, H)) > 0.99
    v = []
    for y in range(0, H - bs + 1, bs // 2):
        for x in range(0, W - bs + 1, bs // 2):
            if m[y:y + bs, x:x + bs].mean() < 0.95: continue
            u = aw[y:y + bs, x:x + bs].ravel(); w = b[y:y + bs, x:x + bs].ravel()
            u = u - u.mean(); w = w - w.mean()
            v.append(float(u @ w / (np.linalg.norm(u) * np.linalg.norm(w) + 1e-9)))
    return np.array(v) if len(v) >= 6 else np.array([0.0])

# feats[s][c] = dict
F = []
for si, s in enumerate(S):
    row = []
    for c in C:
        pa = per_angle(s, c); pb = per_angle(c, s)
        both = [((x[0] + y[0]) / 2, x[1], x[2], x[3]) for x, y in zip(pa, pb[::-1])]  # giro θ (s->c) com -θ (c->s)
        indep = (max(x[0] for x in pa) + max(y[0] for y in pb)) / 2  # como o driver faz hoje
        best = max(both); bv = blocks(s, c, best[1], best[2], best[3])
        row.append(dict(indep=indep, ncc=best[0], ang=best[1], by_ang={a: v[0] for a, v in zip(ANG, both)},
                        q25=float(np.percentile(bv, 25)), bmin=float(bv.min()), bmed=float(np.median(bv))))
    F.append(row)

def regra(nome, fn):
    sc = np.array([max(fn(f) for f in row) for row in F])
    certo = np.array([s[1] for s in sondas])
    imp = sc[~certo].max(); gen = sc[certo]
    acc = 100 * np.mean(gen > imp)
    margem = np.sort(gen)[len(gen) // 2] - imp
    pior = sondas[int(np.argmax(np.where(~certo, sc, -9)))][2]
    print(f"{nome:34} errado máx {imp:6.3f} ({pior[:24]:24}) | certo aceito acima disso {acc:5.1f}%  margem mediana {margem:+.3f}")

regra("0: driver hoje (giros independentes)", lambda f: f["indep"])
regra("A: NCC giro coerente ±30", lambda f: f["ncc"])
for lim in (9, 12, 15, 21):
    regra(f"B: NCC giro ±{lim}", lambda f, L=lim: max(v for a, v in f["by_ang"].items() if abs(a) <= L))
for k in (0.003, 0.006, 0.01):
    regra(f"C: NCC - {k}*|giro|", lambda f, K=k: max(v - K * abs(a) for a, v in f["by_ang"].items()))
regra("D: NCC * q25 blocos", lambda f: f["ncc"] * max(f["q25"], 0))
regra("E: (NCC giro±15) * q25", lambda f: max(v for a, v in f["by_ang"].items() if abs(a) <= 15) * max(f["q25"], 0))
regra("F: q25 blocos", lambda f: f["q25"])
regra("G: mediana blocos", lambda f: f["bmed"])
regra("H: (NCC-0.006|g|)*med blocos", lambda f: max(v - 0.006 * abs(a) for a, v in f["by_ang"].items()) * max(f["bmed"], 0))
np.save(f"{R}/exp3_feats.npy", np.array(F, dtype=object), allow_pickle=True)

def dist(nome, fn):
    sc = np.array([max(fn(f) for f in row) for row in F]); certo = np.array([s[1] for s in sondas])
    print(f"\n{nome}\n  certo  :", " ".join(f"{x:.2f}" for x in np.sort(sc[certo])))
    print("  errado :", " ".join(f"{x:.2f}" for x in np.sort(sc[~certo])[::-1][:10]))
E = lambda f: max(v for a, v in f["by_ang"].items() if abs(a) <= 15) * max(f["q25"], 0)
dist("E", E)
