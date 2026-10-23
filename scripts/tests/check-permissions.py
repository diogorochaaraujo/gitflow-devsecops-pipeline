"""Confere que cada job que chama um reusable workflow concede pelo menos a
uniao das permissoes pedidas pelos jobs do reusable (inclusive os que o `if`
vai pular): o GitHub valida todos e recusa o workflow inteiro no startup."""
import yaml, glob, sys
rank={'none':0,'read':1,'write':2}
root=sys.argv[1]
wfs={f.split('/')[-1]:yaml.safe_load(open(f)) for f in glob.glob(root+'/.github/workflows/*.yml')}
def p(x): return x if isinstance(x,dict) else {}
# ./.github/workflows/x.yml ou <dono>/<repo>/.github/workflows/x.yml@<sha> (plataforma pinada)
def local(u):
    n=u.split('@')[0].split('/')[-1]
    return n if '.github/workflows/' in u and n in wfs else None
def needed(name):
    wf=wfs[name]; need={}
    for j in wf['jobs'].values():
        if local(j.get('uses','')):
            src=needed(local(j['uses']))
        else:
            src={k:rank[v] for k,v in p(j.get('permissions', wf.get('permissions',{}))).items()}
        for k,v in src.items(): need[k]=max(need.get(k,0),v)
    return need
bad=0
for fname,wf in wfs.items():
    for jid,j in wf['jobs'].items():
        u=local(j.get('uses',''))
        if not u: continue
        granted=p(j.get('permissions', wf.get('permissions',{})))
        for k,v in needed(u).items():
            if rank.get(granted.get(k,'none'),0) < v:
                bad+=1; print(f"FALTA {fname}:{jid} -> {u}: {k}={[n for n,r in rank.items() if r==v][0]} (concedido: {granted.get(k,'none')})")
print("permissoes: ok" if not bad else f"permissoes: {bad} problema(s)")
sys.exit(1 if bad else 0)
