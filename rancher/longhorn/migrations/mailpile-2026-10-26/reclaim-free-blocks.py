"""Bounded idle-priority FITRIM of only free ext4 blocks; no file/data deletion."""
import json,pathlib,subprocess,time,shlex,sys,fcntl
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent;PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026');K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=15s'];SSH=['ssh','-o','BatchMode=yes','-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=5','-i','/home/sup/.ssh/id_rsa','sup@10.0.0.72'];offset_file=PRIVATE/'trim-offset';step=256*1024**2
remote='''import json,pathlib,subprocess,os
s,a,f=map(int,subprocess.check_output(['zpool','list','-Hp','-o','size,alloc,free','rpool']).split())
v={r.split()[0]:float(r.split()[1].split('=')[1]) for r in pathlib.Path('/proc/pressure/io').read_text().splitlines()};st=os.statvfs('/var/lib/longhorn');print(json.dumps({'size':s,'allocated':a,'free':f,'some':v['some'],'full':v['full'],'filesystemBytes':st.f_blocks*st.f_frsize}))
'''
def peer():return json.loads(subprocess.check_output(SSH+['python3 -c '+shlex.quote(remote)],timeout=25))
if '--status' in sys.argv:print(json.dumps(peer()));raise SystemExit(0)
worker_lock=(PRIVATE/'reclamation-worker.lock').open('w');fcntl.flock(worker_lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
offset=int(offset_file.read_text()) if offset_file.exists() else step;deadline=time.monotonic()+7200;last_log=0;total_trimmed_ranges=0
log('FREE-BLOCK RECLAMATION START: 256MiB ranges, idle-priority, minimum free extent1MiB, >=5s between calls, PSI pause at some>10%/full>2%; no files deleted')
while time.monotonic()<deadline:
 m=peer();goal=int(m['size']*.20)+int(14.25*1024**3)
 if m['free']>=goal:log('FREE-BLOCK RECLAMATION GOAL: pool freeGiB=%.2f sufficient for20%% margin +12.25Gi target +2Gi buffer'%(m['free']/1024**3));break
 if offset>=m['filesystemBytes']:log('FREE-BLOCK RECLAMATION COMPLETE SCAN: pool still below forecast; leave source running and wait for capacity');break
 if m['some']>10 or m['full']>2:
  if time.monotonic()-last_log>=60:log('FREE-BLOCK RECLAMATION PAUSED: peer PSI some=%.2f full=%.2f'%(m['some'],m['full']));last_log=time.monotonic()
  time.sleep(5);continue
 if subprocess.run(K+['get','--raw=/readyz'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode:log('FREE-BLOCK RECLAMATION HOLD: API unavailable; no further discard requests');raise SystemExit(1)
 pods=json.loads(subprocess.check_output(K+['-n','longhorn-system','get','pods','-l','app=longhorn-manager','-o','json']))['items'];ps=[p for p in pods if p['spec'].get('nodeName')=='proxmox2-old' and any(c['type']=='Ready' and c['status']=='True' for c in p['status'].get('conditions',[])) and not p['metadata'].get('deletionTimestamp')];assert len(ps)==1,'Peer manager not Ready';p=ps[0];mounts=next(c for c in p['spec']['containers'] if c['name']=='longhorn-manager')['volumeMounts'];assert any(x['mountPath'].rstrip('/')=='/var/lib/longhorn' and not x.get('readOnly',False) for x in mounts);assert any(x['name']=='longhorn' and x.get('hostPath',{}).get('path','').rstrip('/')=='/var/lib/longhorn' for x in p['spec']['volumes'])
 result=subprocess.run(K+['-n','longhorn-system','exec',p['metadata']['name'],'-c','longhorn-manager','--','ionice','-c','3','timeout','30s','fstrim','-v','--offset',str(offset),'--length',str(step),'--minimum','1048576','/var/lib/longhorn'],capture_output=True,timeout=50)
 if result.returncode:
  (PRIVATE/'discard-last-error.txt').write_bytes(result.stdout+result.stderr);log('FREE-BLOCK RECLAMATION STOP: discard failed; private diagnostics saved');raise SystemExit(1)
 offset+=step;offset_file.write_text(str(offset));total_trimmed_ranges+=1
 if total_trimmed_ranges%8==0:log('FREE-BLOCK RECLAMATION PROGRESS: scanned_toGiB=%.2f pool_freeGiB=%.2f (discard reports free ranges, not exclusive ZFS delta)'%(offset/1024**3,m['free']/1024**3))
 time.sleep(5)
else:log('FREE-BLOCK RECLAMATION TIME LIMIT: leave source running; resume only after state review')
print(json.dumps(peer()),flush=True)
