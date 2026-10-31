import sys; sys.argv=["x"]
exec(open(__import__("os").path.expanduser("~/")+".cache/instalar-goodix/q.py").read().split("grp=")[0].replace("for i in range(66)}","for i in range(1)}"))
R=__import__("os").path.expanduser("~/")+".cache/instalar-goodix/"
L=lambda p: prep(cv2.imread(p,cv2.IMREAD_UNCHANGED))
ang=[L(R+"dump-2113/20261030-211228-%03d-image.pgm"%i) for i in range(16)]
idx=[L(R+"dump-real/20261030-170430-%03d-image.pgm"%i) for i in range(16)]
tests={1:"C",2:"E medio",3:"C",13:"E polegar",14:"C",15:"E med-esq",16:"C",17:"E anelar",18:"C",19:"E medio",20:"C",23:"E polegar",24:"C",31:"E ind-esq",32:"C",33:"E med-esq"}
for k,lab in tests.items():
    p=L(R+"dump-2113/20261030-211405-%03d-image.pgm"%k)
    def Ep(a,b):
        P[0],P[1]=a,b; return E(0,1)
    sa=max(Ep(p,e) for e in ang); si=max(Ep(p,e) for e in idx)
    print(f"{k:3} {lab:10} angulos {sa:3} indicador {si:3} -> {max(sa,si)}")
