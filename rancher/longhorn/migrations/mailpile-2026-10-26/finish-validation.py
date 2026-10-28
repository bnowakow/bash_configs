"""Guarded cutover after independently verified restore and fresh RO source recheck."""
import datetime,fcntl,json,pathlib,subprocess,threading,time,traceback
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent;ROOT=HERE.parents[2];PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026');NS='apps-mailpile'
K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=20s'];lock=(PRIVATE/'finish-validation.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
def state(phase,detail):
 tmp=HERE/'STATE.cutover.tmp';tmp.write_text(json.dumps({'phase':phase,'detail':detail,'updatedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')},indent=2)+'\n');tmp.replace(HERE/'STATE.json');log('RECOVERED CUTOVER STATE: '+phase+' '+detail)
def run(args):
 if any(x in args for x in ['delete','label','patch','scale']):log('RECOVERED CUTOVER RESOURCE ACTION: '+' '.join(args))
 return subprocess.run(K+args,check=True,stdout=subprocess.PIPE).stdout
def obj(args):return json.loads(run(args+['-o','json']))
def health():
 for extra in ([],['--server=https://10.0.0.72:6443']):assert subprocess.check_output(K+extra+['get','--raw=/readyz']).strip()==b'ok'
def targets():
 for claim in ['mailpile-path1-longhorn-rwo','mailpile-path2-longhorn-rwo']:
  p=obj(['-n',NS,'get','pvc',claim]);assert p['status']['phase']=='Bound';v=obj(['-n','longhorn-system','get','volumes.longhorn.io',p['spec']['volumeName']]);assert v['spec']['numberOfReplicas']==2
  if v['status']['state']=='detached':
   assert v['status']['robustness']=='unknown' and not v['status']['currentNodeID'] and not v['spec']['nodeID']
   rs=[r for r in obj(['-n','longhorn-system','get','replicas.longhorn.io'])['items'] if r['spec']['volumeName']==v['metadata']['name']]
   assert len(rs)==2 and len({r['spec']['nodeID'] for r in rs})==2
   assert all(r['spec'].get('healthyAt') and not r['spec'].get('failedAt') and r['status']['currentState']=='stopped' for r in rs)
   log('DETACHED TARGET PREFLIGHT PASSED: '+claim+'; two previously healthy nonfailed replicas on distinct hosts; attached runtime health remains mandatory')
  else:assert v['status']['robustness']=='healthy'
stop=threading.Event();gap=threading.Event();activated=False
try:
 assert json.loads((PRIVATE/'source-reverification-passed.json').read_text())['fullManifestMatched']
 assert not (PRIVATE/'writer-or-api-alert').exists()
 claims={'mailpile-path1-longhorn-rwo','mailpile-path2-longhorn-rwo'}
 activated=True
 arrived=False
 for _ in range(180):
  d=obj(['-n',NS,'get','deploy','mailpile']);refs={v.get('persistentVolumeClaim',{}).get('claimName') for v in d['spec']['template']['spec']['volumes']}
  if d['spec']['replicas']==1 and d['spec']['strategy']['type']=='Recreate' and refs>=claims:arrived=True;break
  time.sleep(5)
 assert arrived,'Fleet target mounts did not arrive'
 run(['-n',NS,'rollout','status','deployment/mailpile','--timeout=10m'])
 state('rollout_complete','Mailpile Ready on Longhorn targets; final independent runtime/Fleet/backup/HTTP checks running')
 subprocess.run(['/usr/bin/python3',str(HERE/'finalize.py')],check=True)
 state('complete','Mailpile migration final checks passed; maintenance watcher may restore applications to Fleet desired state')
except BaseException:
 stop.set();(PRIVATE/'finish-validation-private-error.txt').write_text(traceback.format_exc());state('validation_requires_review','Fleet rollout/final validation needs review; no blind rollback or application bulk restoration');raise
