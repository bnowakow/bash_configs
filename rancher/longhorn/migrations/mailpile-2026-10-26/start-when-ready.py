"""Guarded start controller; keep the live source running while prerequisites recover."""
import datetime,fcntl,json,pathlib,shlex,subprocess,sys,time
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent;PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026');K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=15s'];statefile=HERE/'STATE.json';lock=(PRIVATE/'start-controller.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);source_stopped='--source-stopped' in sys.argv;reclaimer=None;last=None;stable=None;restart=None;deadline=time.monotonic()+86400

def state(phase,detail):
 global last
 out={'phase':phase,'detail':detail,'updatedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),'pid':__import__('os').getpid()};tmp=statefile.with_suffix('.tmp');tmp.write_text(json.dumps(out,indent=2)+'\n');tmp.replace(statefile)
 if (phase,detail)!=last:log('START CONTROLLER '+phase+': '+detail);last=(phase,detail)
def query(args):return json.loads(subprocess.check_output(K+args+['-o','json'],stderr=subprocess.PIPE,timeout=25))
state('waiting','Maximum-throttle workflow active; original Mailpile remains stopped' if source_stopped else 'Maximum-throttle workflow active; original Mailpile stays running until health/staging/capacity gates pass')
while time.monotonic()<deadline:
 try:
  if (PRIVATE/'migration-started').exists():raise RuntimeError('Existing actual migration marker; inspect before starting another coordinator')
  for extra in ([],['--server=https://10.0.0.72:6443']):assert subprocess.check_output(K+extra+['get','--raw=/readyz'],stderr=subprocess.PIPE,timeout=20).strip()==b'ok'
  current=subprocess.check_output(['systemctl','show','k3s','-p','NRestarts','--value']).strip()
  if current!=restart:stable=None;restart=current
  d=query(['-n','apps-mailpile','get','deploy','mailpile']);assert (d['spec']['replicas']==0 and d['status'].get('replicas',0)==0) if source_stopped else (d['spec']['replicas']==1 and d['status'].get('availableReplicas')==1),'Original app does not match requested stopped/running state'
  pod=query(['-n','apps-mailpile','get','pod','mailpile-transfer-20261026']);assert any(c['type']=='Ready' and c['status']=='True' for c in pod['status'].get('conditions',[])),'Transfer helper not Ready'
  for name in ['mailpile-path1-longhorn-rwo','mailpile-path2-longhorn-rwo']:
   p=query(['-n','apps-mailpile','get','pvc',name]);assert p['status']['phase']=='Bound';v=query(['-n','longhorn-system','get','volumes.longhorn.io',p['spec']['volumeName']]);assert v['status']['robustness']=='healthy' and v['spec']['numberOfReplicas']==2,'Target replicas not yet healthy'
  m=json.loads(subprocess.check_output([sys.executable,str(HERE/'reclaim-free-blocks.py'),'--status'],stderr=subprocess.PIPE,timeout=30));needed=int(m['size']*.2)+int(14.25*1024**3);existing=0
  if '--resume-copy' in sys.argv:
   existing=int(subprocess.check_output(K+['-n','apps-mailpile','exec','mailpile-transfer-20261026','-c','transfer','--','python','-c','import os;print(sum((s.f_blocks-s.f_bfree)*s.f_frsize for s in [os.statvfs("/target/data"),os.statvfs("/target/keys")]))'],stderr=subprocess.PIPE,timeout=25));needed-=min(existing,int(12.25*1024**3))
  if m['free']<needed:
   if reclaimer is None or reclaimer.poll() is not None:
    with (PRIVATE/'reclamation-output.log').open('ab') as output:reclaimer=subprocess.Popen([sys.executable,'-u',str(HERE/'reclaim-free-blocks.py')],stdout=output,stderr=subprocess.STDOUT)
    log('START CONTROLLER: bounded free-block reclamation requested/resumed under exclusive worker lock')
   stable=None;state('waiting_for_physical_headroom','peer_freeGiB=%.2f requiredGiB=%.2f to preserve20%% margin plus remaining target and2Gi buffer (already allocatedGiB=%.2f); bounded free-block reclamation may recover space'%(m['free']/1024**3,needed/1024**3,existing/1024**3));time.sleep(30);continue
  if m['some']>10 or m['full']>2:stable=None;state('waiting_for_low_io','Peer PSI above conservative some10%/full2% threshold');time.sleep(15);continue
  if stable is None:stable=time.monotonic()
  seconds=int(time.monotonic()-stable)
  if seconds<180:state('observing_stability','Health, healthy targets and physical headroom passed; requiring180s unchanged readiness; elapsed='+str(seconds));time.sleep(15);continue
  state('starting','Prerequisites stable; starting guarded resume; live byte and metadata limits are in RATE.json')
  with (PRIVATE/'coordinator-output.log').open('ab') as output:r=subprocess.run([sys.executable,'-u',str(HERE/'migrate.py')]+(['--source-stopped'] if source_stopped else [])+(['--resume-copy'] if '--resume-copy' in sys.argv else []),stdout=output,stderr=subprocess.STDOUT)
  if r.returncode:state('failed_requires_review','Migration stopped; inspect private diagnostics and ACTIONS.log; no automatic rerun over partial staging');raise SystemExit(1)
  state('rollout_complete','Coordinator reports app Ready on targets; running final independent runtime validation')
  result=subprocess.run([sys.executable,str(HERE/'finalize.py')])
  if result.returncode:state('validation_requires_review','Target rollout completed but final validation failed; no blind rollback');raise SystemExit(1)
  state('complete','Mailpile migrated and runtime/backup/restore checks passed; original local sources retained; user functional testing remains');break
 except subprocess.CalledProcessError:
  stable=None;state('waiting_for_api_or_staging','Readiness or staging read failed; original source remains in its requested state')
 except RuntimeError as e:
  state('requires_review',str(e));raise SystemExit(1)
 except AssertionError as e:
  stable=None;state('waiting_for_prerequisites',str(e) or 'A required health/staging gate has not passed')
 except subprocess.TimeoutExpired:
  stable=None;state('waiting_for_api_or_peer','Read-only prerequisite timed out; original source remains in its requested state')
 time.sleep(20)
else:state('deadline_reached','No safe start window within24h; original source remains in its requested state');raise SystemExit(1)
