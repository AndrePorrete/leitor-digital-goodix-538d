#!/usr/bin/env python3
"""Experimento 2: discriminar dedos com textura parecida (indicador x médio).
Ideias avaliadas sobre um conjunto rotulado (pastas por dedo):
  A) NCC global atual (molde central 60%)
  B) NCC com molde maior (80%)
  C) consistência local: após alinhar, correlação por blocos -> fração de blocos bons
  D) minúcias (fim/bifurcação de sulco) após esqueletização, contadas após alinhamento
Saída: para cada método, distribuição mesmo-dedo (indicador) x outros, e simulação
cadastro(N imagens) -> taxa de aceitação certo/errado no melhor limiar sem falso aceite."""
import sys, glob, os, random
import numpy as np, cv2

ROOT = sys.argv[1]
ALVO = "indicador-direito"
pastas = sorted(d for d in os.listdir(ROOT) if os.path.isdir(f"{ROOT}/{d}"))
imgs, lab = [], []
for d in pastas:
    for p in sorted(glob.glob(f"{ROOT}/{d}/*-image.pgm")):
        imgs.append(cv2.imread(p, cv2.IMREAD_UNCHANGED)); lab.append(d)
n = len(imgs)
print(f"{n} imagens:", {d: lab.count(d) for d in pastas})

def prep(u8):
    f = cv2.medianBlur(u8.astype(np.float32), 3)
    f = cv2.GaussianBlur(f, (0, 0), 1.0) - cv2.GaussianBlur(f, (0, 0), 4.0)
    return (f - f.mean()) / (f.std() + 1e-9)

P = [prep(x) for x in imgs]
H, W = P[0].shape

def align(a, b, frac):
    """Melhor (ncc, ang, dx, dy) colocando o centro de a (frac) dentro de b."""
    ch, cw = int(H * frac), int(W * frac)
    pad = cv2.copyMakeBorder(b, ch // 2, ch // 2, cw // 2, cw // 2, cv2.BORDER_CONSTANT, value=0)
    best = (-1, 0, 0, 0)
    for ang in range(-30, 31, 3):
        R = cv2.getRotationMatrix2D((W / 2, H / 2), ang, 1.0)
        ar = cv2.warpAffine(a, R, (W, H))
        y0, x0 = (H - ch) // 2, (W - cw) // 2
        r = cv2.matchTemplate(pad, ar[y0:y0 + ch, x0:x0 + cw], cv2.TM_CCOEFF_NORMED)
        _, mx, _, loc = cv2.minMaxLoc(r)
        if mx > best[0]:
            best = (mx, ang, loc[0] - cw // 2 - x0, loc[1] - ch // 2 - y0)
    return best

def warp_to(a, ang, dx, dy):
    R = cv2.getRotationMatrix2D((W / 2, H / 2), ang, 1.0)
    R[0, 2] += dx; R[1, 2] += dy
    m = cv2.warpAffine(np.ones_like(a), R, (W, H)) > 0.99
    return cv2.warpAffine(a, R, (W, H)), m

def blocks(a, b, ang, dx, dy, bs=12, good=0.5):
    aw, m = warp_to(a, ang, dx, dy)
    tot = ok = 0; vals = []
    for y in range(0, H - bs + 1, bs // 2):
        for x in range(0, W - bs + 1, bs // 2):
            if m[y:y + bs, x:x + bs].mean() < 0.95: continue
            u = aw[y:y + bs, x:x + bs].ravel(); v = b[y:y + bs, x:x + bs].ravel()
            u = u - u.mean(); v = v - v.mean()
            c = float(u @ v / (np.linalg.norm(u) * np.linalg.norm(v) + 1e-9))
            vals.append(c); tot += 1; ok += c > good
    if tot < 6: return 0.0, 0.0
    return ok / tot, float(np.percentile(vals, 25))

def minutiae(u8):
    f = prep(u8)
    bw = (f > 0).astype(np.uint8)
    bw = cv2.morphologyEx(bw, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    sk = cv2.ximgproc.thinning(bw * 255) // 255 if hasattr(cv2, "ximgproc") else skel(bw)
    pts = []
    for y in range(4, H - 4):
        for x in range(4, W - 4):
            if sk[y, x]:
                nb = sk[y - 1:y + 2, x - 1:x + 2].sum() - 1
                if nb == 1 or nb >= 3: pts.append((x, y, 1 if nb == 1 else 3))
    return pts

def skel(bw):
    img = bw.copy(); sk = np.zeros_like(img); el = cv2.getStructuringElement(cv2.MORPH_CROSS, (3, 3))
    while img.any():
        er = cv2.erode(img, el); t = cv2.dilate(er, el); sk |= img - t; img = er
    return sk

MIN = [minutiae(x) for x in imgs]

def minu_score(a, b, ang, dx, dy, tol=4):
    R = cv2.getRotationMatrix2D((W / 2, H / 2), ang, 1.0); R[0, 2] += dx; R[1, 2] += dy
    A = MIN[a]; B = MIN[b]
    if len(A) < 3 or len(B) < 3: return 0.0
    pa = np.array([[x, y] for x, y, _ in A], np.float32)
    ta = np.array([t for _, _, t in A])
    pw = (R[:, :2] @ pa.T).T + R[:, 2]
    pb = np.array([[x, y] for x, y, _ in B], np.float32); tb = np.array([t for _, _, t in B])
    inside = (pw[:, 0] >= 4) & (pw[:, 0] < W - 4) & (pw[:, 1] >= 4) & (pw[:, 1] < H - 4)
    if inside.sum() < 3: return 0.0
    d = np.linalg.norm(pw[inside][:, None] - pb[None], axis=2)
    hit = ((d < tol) & (ta[inside][:, None] == tb[None])).any(1).sum()
    return hit / max(inside.sum(), 1)

res = {k: np.zeros((n, n)) for k in ("A", "B", "C", "C25", "D")}
for i in range(n):
    for j in range(n):
        if i == j: continue
        s, ang, dx, dy = align(P[i], P[j], 0.6)
        res["A"][i, j] = s
        res["B"][i, j] = align(P[i], P[j], 0.8)[0]
        fr, q25 = blocks(P[i], P[j], ang, dx, dy)
        res["C"][i, j] = fr; res["C25"][i, j] = q25
        res["D"][i, j] = minu_score(i, j, ang, dx, dy)
for k in res: res[k] = (res[k] + res[k].T) / 2
res["A*C"] = res["A"] * res["C"]
res["A*D"] = res["A"] * res["D"]
np.savez(f"{ROOT}/../exp2_{os.path.basename(ROOT)}.npz", lab=np.array(lab), **res)

alvo = [i for i in range(n) if lab[i] == ALVO]; outros = [i for i in range(n) if lab[i] != ALVO]
random.seed(1)
print(f"\n{'método':6} {'mesmo(med)':>10} {'outro(max)':>10} | cadastro 8 imgs: limiar sem falso aceite -> % dedo certo aceito")
for k, S in res.items():
    g = [S[a, b] for a in alvo for b in alvo if a < b]
    o = [S[a, b] for a in alvo for b in outros]
    # simulação: cadastro de 8 imagens do alvo; sonda = restantes do alvo e todos os outros
    sims = []
    for _ in range(300):
        enr = random.sample(alvo, min(8, len(alvo) - 2)); pr = [i for i in alvo if i not in enr]
        sims.append(([max(S[p, e] for e in enr) for p in pr], [max(S[p, e] for e in enr) for p in outros]))
    imp_max = max(max(x[1]) for x in sims)
    gen_all = np.concatenate([x[0] for x in sims])
    taxa = 100 * np.mean(gen_all > imp_max)
    print(f"{k:6} {np.median(g):10.3f} {max(o):10.3f} | limiar>{imp_max:.3f}: {taxa:5.1f}%")
