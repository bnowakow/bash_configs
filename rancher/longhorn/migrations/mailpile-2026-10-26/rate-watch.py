"""Monitor both hosts and live copy, revalidation, hash and metadata limits."""
import argparse,datetime,fcntl,json,pathlib,subprocess,sys,time,os
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent;PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026')
lock=(PRIVATE/'rate-watch.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
try:prior=json.loads((HERE/'RATE.json').read_text())
except (OSError,ValueError):prior={}
parser=argparse.ArgumentParser();parser.add_argument('--cap',type=int,default=prior.get('copyKiBps',512));parser.add_argument('--verify-cap',type=int,default=prior.get('verifyKiBps',2048));parser.add_argument('--reuse-cap',type=int,default=prior.get('reuseKiBps',8192));parser.add_argument('--metadata-rate',type=int,default=prior.get('metadataEntriesPerSecond',100));args=parser.parse_args()
assert all(64<=v<=16384 for v in [args.cap,args.verify_cap,args.reuse_cap]) and 5<=args.metadata_rate<=500
limits={'copyKiBps':args.cap,'verifyKiBps':args.verify_cap,'reuseKiBps':args.reuse_cap,'metadataEntriesPerSecond':args.metadata_rate}
last_documented={k:prior.get(k,{'copyKiBps':None,'verifyKiBps':512,'reuseKiBps':prior.get('copyKiBps',512),'metadataEntriesPerSecond':20}[k]) for k in limits}
applied={};targets=[];last_log=0;good=0;paused=False
K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=10s']
def reduce_limits():
 limits.update(copyKiBps=min(limits['copyKiBps'],256),verifyKiBps=min(limits['verifyKiBps'],512),reuseKiBps=min(limits['reuseKiBps'],1024),metadataEntriesPerSecond=min(limits['metadataEntriesPerSecond'],20))
log('RATE MONITOR START: '+json.dumps(limits,sort_keys=True)+'; both hosts PSI some10%/full2%, pressure pause and conservative reductions; recovery requires3 low samples; continues through backup/restore verification')
while True:
 phase=json.loads((HERE/'STATE.json').read_text())['phase']
 if phase in ['complete','failed_requires_review','validation_requires_review','requires_review','deadline_reached']:
  log('RATE MONITOR STOP: workflow complete or requires review');break
 try:
  local={r.split()[0]:float(r.split()[1].split('=')[1]) for r in pathlib.Path('/proc/pressure/io').read_text().splitlines()}
  peer=json.loads(subprocess.check_output([sys.executable,str(HERE/'reclaim-free-blocks.py'),'--status'],stderr=subprocess.PIPE,timeout=30))
  high=max(local['some'],peer['some'])>10 or max(local['full'],peer['full'])>2 or peer['free']<int(peer['size']*.2)+2*1024**3
  if high:paused=True;reduce_limits();good=0
  else:
   good+=1
   if good>=3:paused=False
  metrics={'updatedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),'pid':os.getpid(),**limits,'paused':paused,'localPSI':local,'peerPSI':{'some':peer['some'],'full':peer['full']},'peerFreeGiB':peer['free']/1024**3}
  tmp=HERE/'RATE.tmp';tmp.write_text(json.dumps(metrics,indent=2)+'\n');tmp.replace(HERE/'RATE.json')
  if time.monotonic()-last_log>=60:
   log('RATE MONITOR: limits='+json.dumps(limits,sort_keys=True)+' pause=%s localPSI=%.2f/%.2f peerPSI=%.2f/%.2f peerFreeGiB=%.2f'%(paused,local['some'],local['full'],peer['some'],peer['full'],peer['free']/1024**3));last_log=time.monotonic()
  pods=json.loads(subprocess.check_output(K+['-n','apps-mailpile','get','pods','-o','json'],stderr=subprocess.PIPE,timeout=20))['items']
  targets=[(p['metadata']['name'],p['metadata']['uid']) for p in pods if p['metadata']['name'] in ['mailpile-transfer-20261026','mailpile-restore-20261026'] and not p['metadata'].get('deletionTimestamp') and any(c['type']=='Ready' and c['status']=='True' for c in p['status'].get('conditions',[]))]
 except (subprocess.SubprocessError,ValueError,OSError):
  paused=True;reduce_limits();good=0;log('RATE MONITOR: telemetry unavailable; requesting conservative pause')
 cfg=json.dumps({**limits,'pause':paused},sort_keys=True).encode()
 for pod,uid in targets:
  if applied.get((pod,uid))==cfg:continue
  code='import pathlib,sys;p=pathlib.Path("/tmp/mailpile-rate.json");t=p.with_suffix(".tmp");t.write_bytes(sys.stdin.buffer.read());t.replace(p)'
  try:
   subprocess.run(K+['-n','apps-mailpile','exec','-i',pod,'-c','transfer','--','python','-c',code],input=cfg,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,check=True,timeout=20);applied[(pod,uid)]=cfg
   log('RATE LIMITS APPLIED: helper='+pod+' '+json.dumps(limits,sort_keys=True)+' pause='+str(paused))
   if limits!=last_documented:
    changes='; '.join(k+': '+str(last_documented.get(k))+' → '+str(v) for k,v in limits.items() if last_documented.get(k)!=v)
    stamp=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds');reason='Safety reduction' if paused else 'User-requested monitored limits'
    with (HERE/'TRANSFER-CAPS.md').open('a') as f:
     f.write('| '+stamp+' | '+changes+' | '+reason+'; accepted by '+pod+'; pause='+str(paused)+'. KiB/s for byte limits, entries/s for metadata. See ACTIONS.log for pressure/outcome. |\n');f.flush();os.fsync(f.fileno())
    last_documented=dict(limits)
  except subprocess.SubprocessError:log('RATE MONITOR: limit update not accepted by '+pod+'; retry next sample')
 time.sleep(15)
