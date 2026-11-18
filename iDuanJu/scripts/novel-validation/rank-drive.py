import json,subprocess,sys,concurrent.futures
binp,bundle,out=sys.argv[1:4]; lim=sys.argv[4] if len(sys.argv)>4 else '3'
src=json.load(open(bundle))
idx=[i for i,s in enumerate(src) if (s.get('bookSourceType') or 0)==0 and (s.get('exploreUrl') or '').strip()]
def run(i):
    try:
        p=subprocess.run([binp,bundle,str(i),lim],capture_output=True,text=True,timeout=120)
        line=[l for l in p.stdout.splitlines() if l.startswith('{')]
        return json.loads(line[-1]) if line else {'index':i,'name':src[i]['bookSourceName'],'crash':p.returncode,'stderr':p.stderr[-300:]}
    except subprocess.TimeoutExpired: return {'index':i,'name':src[i]['bookSourceName'],'timeout':True}
with concurrent.futures.ThreadPoolExecutor(8) as ex: res=list(ex.map(run,idx))
json.dump(res,open(out,'w'),ensure_ascii=False,indent=1)
ok=0
for r in res:
    ex=r.get('explore') or []
    good=any(e.get('count',0)>0 for e in ex)
    ok+=good
    print(('OK ' if good else 'BAD'),r['index'],r['name'],'cats=',r.get('categories'),r.get('catError','') or '', ' | '.join(f"{e['title']}:{e.get('count', 'ERR '+e.get('error','')[:90])}" for e in ex), 'TIMEOUT' if r.get('timeout') else '', 'CRASH' if 'crash' in r else '')
print('sources',len(res),'with books',ok)
