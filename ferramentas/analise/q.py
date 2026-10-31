import numpy as np, cv2, sys
D=__import__("os").path.expanduser("~/")+".cache/instalar-goodix/dump-2053/20261030-205223-%03d-image.pgm"
def prep(u8):
    f=cv2.medianBlur(u8.astype(np.float32),3); f=cv2.GaussianBlur(f,(0,0),1)-cv2.GaussianBlur(f,(0,0),4)
    return (f-f.mean())/(f.std()+1e-9)
I={i:cv2.imread(D%i,cv2.IMREAD_UNCHANGED) for i in range(66)}
P={i:prep(v) for i,v in I.items()}; H,W=P[0].shape
def pdir(a,b,ang,fr=0.6):
    ch,cw=int(H*fr),int(W*fr); pad=cv2.copyMakeBorder(b,ch//2,ch//2,cw//2,cw//2,cv2.BORDER_CONSTANT,value=0)
    R=cv2.getRotationMatrix2D((W/2,H/2),ang,1); ar=cv2.warpAffine(a,R,(W,H)); y0,x0=(H-ch)//2,(W-cw)//2
    r=cv2.matchTemplate(pad,ar[y0:y0+ch,x0:x0+cw],cv2.TM_CCOEFF_NORMED); _,mx,_,l=cv2.minMaxLoc(r)
    return mx,l[0]-cw//2-x0,l[1]-ch//2-y0
def blk(a,b,ang,dx,dy,bs=12):
    R=cv2.getRotationMatrix2D((W/2,H/2),ang,1);R[0,2]+=dx;R[1,2]+=dy
    aw=cv2.warpAffine(a,R,(W,H)); m=cv2.warpAffine(np.ones_like(a),R,(W,H))>0.99; v=[]
    for y in range(0,H-bs+1,bs//2):
        for x in range(0,W-bs+1,bs//2):
            if m[y:y+bs,x:x+bs].mean()<.95: continue
            u=aw[y:y+bs,x:x+bs].ravel();w=b[y:y+bs,x:x+bs].ravel();u=u-u.mean();w=w-w.mean()
            v.append(float(u@w/(np.linalg.norm(u)*np.linalg.norm(w)+1e-9)))
    return np.percentile(v,25) if len(v)>=6 else 0
def E(i,j):
    a,b=P[i],P[j];best=(-1,)
    for ang in range(-15,16,3):
        f=pdir(a,b,ang);r=pdir(b,a,-ang);s=(f[0]+r[0])/2
        if s>best[0]:best=(s,ang,f[1],f[2])
    return int(round(100*best[0]*max(blk(a,b,*best[1:]),0)))
grp={"thumb?1":list(range(21,29)),"thumb?2":list(range(38,48)),"idx":[18,20,30,35,37,49]}
for p in [29,48,33,64]:
    print(p, {g:max(E(p,j) for j in js) for g,js in grp.items()})
print("std", {i:int(I[i].std()) for i in [18,20,21,24,27,29,38,44,48]})
print("---cadastro novo (000-017): parecido com indicador ou polegar?")
idx=[18,20,30,35,37,49]; th=list(range(21,29))+list(range(38,48))
for e in range(18):
    print(e, "idx",max(E(e,j) for j in idx),"pol",max(E(e,j) for j in th))
print("--- recusados do indicador contra cadastro novo")
for p in [33,64,65]: print(p, max(E(p,e) for e in range(18)))
