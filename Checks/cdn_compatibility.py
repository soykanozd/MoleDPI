# SPDX-License-Identifier: GPL-3.0-only
"""Opt-in live CDN transport regression, with certificate verification enabled.

Quit MoleDPI before running. Uses a locally built, unprivileged SOCKS listener.
Both variants contact the same fixed public CDN root. HTTP 403 is expected and
counts as a TLS transport response only, not successful content/game access.
No credentials, response bodies, addresses or user traffic are recorded.
"""
import subprocess,socket,time,concurrent.futures,json,statistics
rows=[]
for label,args in [('before',['--split-pos=2','--oob=tls']),('after',['--hostlist-exclude-domains=rbxcdn.com','--split-pos=2','--oob=tls','--new','--filter-tcp=80,443','--filter-l7=http,tls','--split-pos=host+1'])]:
 p=subprocess.Popen(['dist/MoleDPI.app/Contents/Resources/tpws','--socks','--bind-addr=127.0.0.1','--port=18081','--maxconn=128','--filter-tcp=80,443','--filter-l7=http,tls']+args,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 try:
  for _ in range(100):
   try: c=socket.create_connection(('127.0.0.1',18081),.1);c.close();break
   except OSError:time.sleep(.01)
  def probe(_):
   r=subprocess.run(['/usr/bin/curl','--disable','-s','-o','/dev/null','--proxy','socks5h://127.0.0.1:18081','--noproxy','','--connect-timeout','4','--max-time','5','-w','%{http_code} %{time_total}','https://sc0ak.rbxcdn.com/'],capture_output=True,text=True)
   return {'exit':r.returncode,'status':r.stdout.split()[0],'ms':float(r.stdout.split()[1])*1000}
  rr=list(concurrent.futures.ThreadPoolExecutor(max_workers=4).map(probe,range(12)))
  result={'variant':label,'requests':len(rr),'transport_successes':sum(r['exit']==0 for r in rr),'mean_ms':round(statistics.mean(r['ms'] for r in rr),2),'median_ms':round(statistics.median(r['ms'] for r in rr),2),'max_ms':round(max(r['ms'] for r in rr),2),'http_statuses':sorted(set(r['status'] for r in rr))}
  rows.append(result);print(result,flush=True)
 finally:p.terminate();p.wait(timeout=3)
with open('.build/cdn-compatibility.json','w') as output: json.dump(rows,output,indent=2)
assert rows[1]['transport_successes'] == rows[1]['requests'], 'Corrected CDN transport did not pass every request'
