"""Guarded cutover after independently verified restore and fresh RO source recheck."""
import datetime,fcntl,json,pathlib,subprocess,threading,time,traceback
from action_log import log
HERE=pathlib.Path(__file__).resolve().parent;ROOT=HERE.parents[2];PRIVATE=pathlib.Path('/tmp/longhorn-mailpile-20261026');NS='apps-mailpile'
K=['kubectl','--kubeconfig','/etc/rancher/k3s/k3s.yaml','--request-timeout=20s'];lock=(PRIVATE/'recovered-cutover.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
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
 assert json.loads((HERE/'STATE.json').read_text())['phase']=='source_reverified'
 evidence=json.loads((PRIVATE/'source-reverification-passed.json').read_text());assert evidence['fullManifestMatched'] and not evidence['guardGap']
 assert 'INDEPENDENT RESTORE RECOVERY PASSED:' in (HERE/'ACTIONS.log').read_text()
 health();targets();d=obj(['-n',NS,'get','deploy','mailpile']);assert d['spec']['replicas']==0 and d['status'].get('replicas',0)==0
 original=json.loads((PRIVATE/'source-deployment-final.json').read_text());assert d['spec']['template']['spec']['containers'][0]['image']==original['spec']['template']['spec']['containers'][0]['image']
 for row in json.loads((HERE/'maintenance-plan.json').read_text())['workloads']:
  if row['namespace'].startswith('apps-'):assert obj(['-n',row['namespace'],'get',row['kind'],row['name']])['spec']['replicas']==0
 claims={'mailpile-path1-longhorn-rwo','mailpile-path2-longhorn-rwo'}
 for p in obj(['-n',NS,'get','pods'])['items']:
  if p['status']['phase'] not in ['Succeeded','Failed']:assert not any(v.get('persistentVolumeClaim',{}).get('claimName') in claims for v in p['spec'].get('volumes',[]))
 for path,text in json.loads((PRIVATE/'source-repository-files.json').read_text()).items():assert (ROOT/path).read_text()==text,'Repository configuration changed since preparation'
 # The old alert remains audit evidence. Fresh full source verification resolves its gap.
 alert=PRIVATE/'writer-or-api-alert'
 if alert.exists():alert.rename(PRIVATE/('writer-or-api-alert-resolved-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')))
 log('PRIOR API GUARD RESOLVED: full original-source hashes/metadata/links and independent NAS restore passed; fresh source0/API/target/no-writer checks passed; old alert archived privately')
 def guard():
  while not stop.wait(5):
   try:
    assert obj(['-n',NS,'get','deploy','mailpile'])['spec']['replicas']==0;health()
   except BaseException:gap.set();alert.write_text('Source writer/API health gap during recovered cutover preflight');log('RECOVERED CUTOVER GUARD ALERT: cutover blocked');return
 threading.Thread(target=guard,daemon=True).start()
 state('cutover_preparation','Fresh source and independent restore verified; cleaning scratch resources before Fleet cutover')
 # Delete only verified scratch copies/helpers; retain all original and production claims.
 for pod in ['mailpile-restore-20261026','mailpile-transfer-20261026']:
  run(['-n',NS,'delete','pod',pod,'--ignore-not-found']);run(['-n',NS,'wait','--for=delete','pod/'+pod,'--timeout=5m'])
 run(['-n',NS,'delete','pvc','mailpile-data-restore-20261026','mailpile-keys-restore-20261026','--ignore-not-found'])
 run(['delete','storageclass','longhorn-mailpile-data-restore-20261026','longhorn-mailpile-keys-restore-20261026','--ignore-not-found'])
 label='recurring-job-group.longhorn.io/mailpile-migration-20261026'
 for claim in sorted(claims):run(['-n',NS,'label','pvc',claim,label+'-'])
 run(['delete','-f',str(PRIVATE/'recurring-job.json'),'--ignore-not-found'])
 health();targets();assert not gap.is_set() and not alert.exists()
 for name,text in json.loads((HERE/'prepared-fleet-files.json').read_text()).items():(ROOT/name).write_text(text)
 # Stop sole-writer guard immediately before intentional Fleet activation.
 stop.set();assert not gap.is_set() and not alert.exists();activated=True
 state('cutover_started','Applying verified Longhorn claim references through Fleet; no blind rollback')
 subprocess.run([str(HERE/'../pilot-2026-10-24/apply-bundle.sh'),'mailpile','rancher/fleet/apps/mailpile'],check=True)
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
 stop.set();(PRIVATE/'recovered-cutover-private-error.txt').write_text(traceback.format_exc())
 state('validation_requires_review' if activated else 'requires_review','Recovered cutover stopped; inspect private diagnostics; no blind rollback or bulk application restoration');raise
